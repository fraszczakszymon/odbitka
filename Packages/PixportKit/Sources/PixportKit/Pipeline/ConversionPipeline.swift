import Foundation

/// Orkiestracja całego przebiegu: kontrola wstępna → pobranie → konwersja →
/// ewentualne dociśnięcie pod limit → pakowanie.
public struct ConversionPipeline: Sendable {

    public enum Stage: Sendable, Equatable {
        case preparing
        case downloading(fileName: String, fraction: Double)
        case converting(fileName: String)
        /// Tryb „zmieść w X MB" nie trafił za pierwszym razem i powtarza przebieg.
        case retryingForBudget(pass: Int)
        case packaging(part: Int, partCount: Int, fraction: Double)
    }

    public struct Progress: Sendable, Equatable {
        public let stage: Stage
        public let completed: Int
        public let total: Int

        public var fraction: Double {
            guard total > 0 else { return 0 }
            return Double(completed) / Double(total)
        }
    }

    /// Ile zdjęć przetwarzamy równolegle.
    ///
    /// Dwa to kompromis: jedno zadanie nie wysyca rdzeni, a cztery przy RAW-ach
    /// potrafią przekroczyć budżet pamięci. W rozszerzeniu udostępniania, gdzie limit
    /// jest rzędu 120 MB, aplikacja ustawia tu jedynkę.
    public var maxConcurrency: Int
    /// Ile razy tryb budżetowy może powtórzyć przebieg, zanim się podda.
    public var maxBudgetPasses: Int

    public let workspace: Workspace

    public init(workspace: Workspace, maxConcurrency: Int = 2, maxBudgetPasses: Int = 4) {
        self.workspace = workspace
        self.maxConcurrency = max(1, maxConcurrency)
        self.maxBudgetPasses = max(1, maxBudgetPasses)
    }

    public func run(
        photos: [any SourcePhoto],
        settings: ConversionSettings,
        isNetworkAvailable: Bool,
        onProgress: @Sendable @escaping (Progress) -> Void
    ) async throws -> ConversionResult {
        guard !photos.isEmpty else {
            return ConversionResult(
                files: [], archives: [], originalByteCount: 0,
                producedByteCount: 0, budgetPasses: 0, effectiveSettings: settings
            )
        }

        onProgress(Progress(stage: .preparing, completed: 0, total: photos.count))
        _ = try await Preflight.check(photos: photos, settings: settings, isNetworkAvailable: isNetworkAvailable)

        let ordered = FileNamer.ordered(photos)
        let originalTotal = ordered.reduce(Int64(0)) { $0 + $1.byteCount }
        let sourceLongEdge = ordered.map { max($0.pixelWidth, $0.pixelHeight) }.max() ?? 0

        do {
            var current = settings
            var files: [ProcessedFile] = []
            var pass = 0

            while true {
                pass += 1
                if pass > 1 {
                    onProgress(Progress(stage: .retryingForBudget(pass: pass), completed: 0, total: ordered.count))
                    workspace.discardOutputs()
                }

                files = try await convertAll(
                    ordered,
                    settings: current,
                    // W trybie budżetowym oryginały mogą być potrzebne do powtórki,
                    // więc nie kasujemy ich po drodze.
                    keepSources: settings.budget.isEnabled,
                    onProgress: onProgress
                )

                let produced = files.reduce(Int64(0)) { $0 + $1.byteCount }
                guard settings.budget.isEnabled, produced > settings.budget.bytes else { break }

                guard pass < maxBudgetPasses,
                      let tightened = BudgetSolver.tighten(
                          current,
                          achieved: produced,
                          budget: settings.budget.bytes,
                          sourceLongEdge: sourceLongEdge
                      )
                else {
                    throw ConversionError.budgetUnreachable(target: settings.budget.bytes, best: produced)
                }
                current = tightened
            }

            workspace.discardSources()

            let archives = settings.packaging.makeZip
                ? try makeArchives(from: files, settings: current, onProgress: onProgress)
                : []

            let produced = archives.isEmpty
                ? files.reduce(Int64(0)) { $0 + $1.byteCount }
                : archives.reduce(Int64(0)) { $0 + $1.byteCount }

            return ConversionResult(
                files: files,
                archives: archives,
                originalByteCount: originalTotal,
                producedByteCount: produced,
                budgetPasses: pass,
                effectiveSettings: current
            )
        } catch {
            // „Wszystko albo nic": po nieudanym przebiegu nie zostaje ani jeden plik,
            // żeby nie dało się przypadkiem wysłać niekompletnej paczki.
            workspace.discardOutputs()
            workspace.discardSources()
            throw error
        }
    }

    // MARK: - Konwersja

    private func convertAll(
        _ photos: [any SourcePhoto],
        settings: ConversionSettings,
        keepSources: Bool,
        onProgress: @Sendable @escaping (Progress) -> Void
    ) async throws -> [ProcessedFile] {
        let names = FileNamer.names(for: photos, prefix: settings.namePrefix, format: settings.format)
        let total = photos.count
        let counter = Counter()
        let concurrency = min(maxConcurrency, total)

        var results = [ProcessedFile?](repeating: nil, count: total)

        try await withThrowingTaskGroup(of: (Int, ProcessedFile).self) { group in
            var next = 0

            func addTask(_ index: Int) {
                let photo = photos[index]
                let name = names[index]
                group.addTask {
                    let file = try await convertOne(
                        photo,
                        name: name,
                        settings: settings,
                        keepSources: keepSources,
                        total: total,
                        counter: counter,
                        onProgress: onProgress
                    )
                    return (index, file)
                }
            }

            while next < concurrency {
                addTask(next)
                next += 1
            }

            while let (index, file) = try await group.next() {
                results[index] = file
                if next < total {
                    addTask(next)
                    next += 1
                }
            }
        }

        return results.compactMap { $0 }
    }

    private func convertOne(
        _ photo: any SourcePhoto,
        name: String,
        settings: ConversionSettings,
        keepSources: Bool,
        total: Int,
        counter: Counter,
        onProgress: @Sendable @escaping (Progress) -> Void
    ) async throws -> ProcessedFile {
        try Task.checkCancellation(mapping: ConversionError.cancelled)

        let displayName = photo.originalFileName ?? name
        let sourceURL = workspace.sourcesDirectory
            .appendingPathComponent(FileNamer.normalize(photo.id) + "." + sourceExtension(for: photo))

        if !FileManager.default.fileExists(atPath: sourceURL.path) {
            let completed = await counter.value
            onProgress(Progress(stage: .downloading(fileName: displayName, fraction: 0), completed: completed, total: total))
            try await photo.materialize(at: sourceURL) { fraction in
                onProgress(Progress(
                    stage: .downloading(fileName: displayName, fraction: fraction),
                    completed: completed,
                    total: total
                ))
            }
        }

        try Task.checkCancellation(mapping: ConversionError.cancelled)
        onProgress(Progress(stage: .converting(fileName: displayName), completed: await counter.value, total: total))

        let destinationURL = workspace.outputDirectory.appendingPathComponent(name)
        let byteCount = try autoreleasepoolCompat {
            try ImageConverter.convert(
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                settings: settings,
                quality: settings.effectiveQuality,
                displayName: displayName
            )
        }

        // Data pliku ustawiana z daty zrobienia zdjęcia — bez tego u odbiorcy wszystkie
        // pliki dostają dzisiejszą datę i sortują się losowo. Gdy użytkownik świadomie
        // usuwa datę z metadanych, nie przywracamy jej tylnymi drzwiami.
        if settings.metadata.keepDateTime, let date = photo.creationDate {
            try? FileManager.default.setAttributes(
                [.modificationDate: date, .creationDate: date],
                ofItemAtPath: destinationURL.path
            )
        }

        if !keepSources {
            try? FileManager.default.removeItem(at: sourceURL)
        }

        let completed = await counter.increment()
        onProgress(Progress(stage: .converting(fileName: displayName), completed: completed, total: total))

        return ProcessedFile(
            sourceID: photo.id,
            url: destinationURL,
            fileName: name,
            byteCount: byteCount,
            originalByteCount: photo.byteCount
        )
    }

    private func sourceExtension(for photo: any SourcePhoto) -> String {
        guard let name = photo.originalFileName else { return "img" }
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? "img" : ext.lowercased()
    }

    // MARK: - Pakowanie

    private func makeArchives(
        from files: [ProcessedFile],
        settings: ConversionSettings,
        onProgress: @Sendable @escaping (Progress) -> Void
    ) throws -> [ProcessedFile] {
        let entries = files.map { SplitPlanner.Entry(name: $0.fileName, size: $0.byteCount) }
        let plan: [[Int]] = settings.packaging.splitIntoParts
            ? try SplitPlanner.plan(entries: entries, partLimit: settings.packaging.partBytes)
            : [Array(files.indices)]

        let totalBytes = max(files.reduce(Int64(0)) { $0 + $1.byteCount }, 1)
        var written: Int64 = 0
        var archives: [ProcessedFile] = []
        let now = Date()

        for (partIndex, indices) in plan.enumerated() {
            try Task.checkCancellation(mapping: ConversionError.cancelled)
            let name = FileNamer.archiveName(
                prefix: settings.namePrefix,
                partIndex: partIndex,
                partCount: plan.count,
                date: now
            )
            let url = workspace.outputDirectory.appendingPathComponent(name)
            let writer = try ZipWriter(url: url)

            for index in indices {
                let file = files[index]
                try writer.add(
                    fileAt: file.url,
                    name: file.fileName,
                    modificationDate: now
                ) { chunk in
                    written += chunk
                    onProgress(Progress(
                        stage: .packaging(
                            part: partIndex,
                            partCount: plan.count,
                            fraction: Double(written) / Double(totalBytes)
                        ),
                        completed: files.count,
                        total: files.count
                    ))
                }
            }

            let size = try writer.finish()
            archives.append(
                ProcessedFile(
                    sourceID: "archive-\(partIndex)",
                    url: url,
                    fileName: name,
                    byteCount: size,
                    originalByteCount: totalBytes
                )
            )
        }

        return archives
    }
}

/// Licznik ukończonych zdjęć, współdzielony przez równoległe zadania.
actor Counter {
    private(set) var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}

extension Task where Success == Never, Failure == Never {
    /// `Task.checkCancellation()` rzuca `CancellationError`; my chcemy jeden typ błędu
    /// w całym silniku, żeby warstwa UI miała jedno miejsce do tłumaczenia komunikatów.
    static func checkCancellation(mapping error: ConversionError) throws {
        if Task<Never, Never>.isCancelled { throw error }
    }
}

/// `autoreleasepool` wokół każdego zdjęcia. `ImageIO` i Core Graphics alokują obiekty
/// Objective-C; bez jawnego zwalniania pamięć puchnie do końca zadania, a przy paczce
/// RAW-ów kończy się ubiciem procesu przez system.
@inline(__always)
func autoreleasepoolCompat<T>(_ body: () throws -> T) rethrows -> T {
    try autoreleasepool { try body() }
}
