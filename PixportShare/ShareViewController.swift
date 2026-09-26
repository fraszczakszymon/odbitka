import PixportKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Wejście z systemowego arkusza udostępniania (Zdjęcia → Udostępnij → Pixport).
///
/// Zachowanie zależy od wielkości paczki:
/// - **do `PixportConfig.extensionPhotoLimit` zdjęć** rozszerzenie robi wszystko na miejscu:
///   pokazuje ustawienia, przetwarza szeregowo i od razu otwiera arkusz udostępniania.
///   Użytkownik nie opuszcza Zdjęć.
/// - **powyżej progu** kopiuje pliki do wspólnego kontenera i przekazuje robotę aplikacji.
///
/// Powód podziału jest twardy: rozszerzenia dostają rzędu stu kilkudziesięciu megabajtów
/// pamięci. Przy skalowaniu przez `ImageIO` jedno zdjęcie mieści się w tym spokojnie,
/// ale duża paczka, RAW albo panorama potrafią ten budżet przebić — a system ubija
/// rozszerzenie bez ostrzeżenia i bez komunikatu dla użytkownika.
final class ShareViewController: UIViewController {

    private var workingDirectory: URL?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        Task { await prepare() }
    }

    private func prepare() async {
        let providers = collectProviders()

        guard !providers.isEmpty else {
            present(message: L.s("share.error.noImages"))
            return
        }

        if providers.count > PixportConfig.extensionPhotoLimit {
            await handOffToApp(providers: providers)
        } else {
            await processInPlace(providers: providers)
        }
    }

    private func collectProviders() -> [NSItemProvider] {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return [] }
        return items
            .compactMap(\.attachments)
            .flatMap { $0 }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
    }

    // MARK: - Duża paczka: przekazanie do aplikacji

    private func handOffToApp(providers: [NSItemProvider]) async {
        showStatus(L.s("share.preparing"))
        do {
            let session = try HandoffStore.createSession()
            var items: [HandoffItem] = []

            for (index, provider) in providers.enumerated() {
                guard let source = try? await loadFile(from: provider) else { continue }
                let fileName = String(format: "%05d.%@", index, source.pathExtension.isEmpty ? "img" : source.pathExtension)
                let destination = session.directory.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: source, to: destination)
                items.append(makeItem(fileName: fileName, fileURL: destination, originalName: source.lastPathComponent))
            }

            guard !items.isEmpty else {
                present(message: L.s("share.error.noImages"))
                return
            }

            try HandoffStore.write(HandoffManifest(sessionID: session.id, items: items))

            if let url = HandoffStore.handoffURL(sessionID: session.id) {
                _ = await extensionContext?.open(url)
            }
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            present(message: ErrorPresentation(error).message)
        }
    }

    // MARK: - Mała paczka: przetwarzanie na miejscu

    private func processInPlace(providers: [NSItemProvider]) async {
        showStatus(L.s("share.preparing"))

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PixportShare-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        workingDirectory = directory

        var photos: [HandoffPhoto] = []
        for (index, provider) in providers.enumerated() {
            guard let source = try? await loadFile(from: provider) else { continue }
            let fileName = String(format: "%05d.%@", index, source.pathExtension.isEmpty ? "img" : source.pathExtension)
            let destination = directory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.copyItem(at: source, to: destination)
            let item = makeItem(fileName: fileName, fileURL: destination, originalName: source.lastPathComponent)
            photos.append(HandoffPhoto(item: item, fileURL: destination))
        }

        guard !photos.isEmpty else {
            present(message: L.s("share.error.noImages"))
            return
        }

        showRoot(photos: photos)
    }

    // MARK: - Pomocnicze

    /// Wyciąga plik z `NSItemProvider`.
    ///
    /// `loadFileRepresentation` oddaje adres ważny wyłącznie wewnątrz domknięcia —
    /// po jego zakończeniu plik znika. Dlatego kopiujemy go na własne miejsce
    /// jeszcze zanim wrócimy z tej funkcji.
    private func loadFile(from provider: NSItemProvider) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                let staging = FileManager.default.temporaryDirectory
                    .appendingPathComponent("stage-\(UUID().uuidString)-\(url.lastPathComponent)")
                do {
                    try FileManager.default.copyItem(at: url, to: staging)
                    continuation.resume(returning: staging)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func makeItem(fileName: String, fileURL: URL, originalName: String) -> HandoffItem {
        var width = 0
        var height = 0
        var created: Date?

        if let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
            width = properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0
            height = properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0
            if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any],
               let raw = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                created = Self.exifFormatter.date(from: raw)
            }
        }

        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)??.int64Value ?? 0

        return HandoffItem(
            fileName: fileName,
            originalFileName: originalName,
            creationDate: created,
            pixelWidth: width,
            pixelHeight: height,
            byteCount: size
        )
    }

    private static let exifFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // MARK: - Prezentacja

    private func showStatus(_ text: String) {
        let hosting = UIHostingController(rootView: ShareStatusView(text: text))
        embed(hosting)
    }

    private func showRoot(photos: [HandoffPhoto]) {
        let hosting = UIHostingController(
            rootView: ShareRootView(
                photos: photos,
                onFinish: { [weak self] in self?.finish() }
            )
        )
        embed(hosting)
    }

    private func present(message: String) {
        let hosting = UIHostingController(
            rootView: ShareMessageView(message: message, onClose: { [weak self] in self?.finish() })
        )
        embed(hosting)
    }

    private func embed(_ controller: UIViewController) {
        children.forEach {
            $0.willMove(toParent: nil)
            $0.view.removeFromSuperview()
            $0.removeFromParent()
        }
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(controller.view)
        controller.didMove(toParent: self)
    }

    private func finish() {
        if let workingDirectory {
            try? FileManager.default.removeItem(at: workingDirectory)
        }
        extensionContext?.completeRequest(returningItems: nil)
    }
}
