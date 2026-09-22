import OdbitkaKit
import SwiftUI

/// Krok czwarty: co powstało i co z tym zrobić.
struct ResultView: View {
    let result: ConversionResult

    @State private var sharedURLs: [URL]?
    @State private var exportedURLs: [URL]?
    @State private var showsBatches = false
    @State private var saveMessage: String?
    @State private var isSaving = false

    private var shareable: [ProcessedFile] { result.shareableFiles }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                summary
                if let note = budgetNote {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                thumbnails
                actions
            }
            .padding(.vertical, 24)
        }
        .navigationTitle(L.s("result.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .sheet(item: Binding(get: { sharedURLs.map(URLBox.init) }, set: { sharedURLs = $0?.urls })) { box in
            ShareSheet(urls: box.urls)
        }
        .sheet(item: Binding(get: { exportedURLs.map(URLBox.init) }, set: { exportedURLs = $0?.urls })) { box in
            DocumentExporter(urls: box.urls)
        }
        .sheet(isPresented: $showsBatches) {
            BatchShareView(files: shareable)
        }
        .alert(
            L.s("result.savePhotos.title"),
            isPresented: Binding(get: { saveMessage != nil }, set: { if !$0 { saveMessage = nil } })
        ) {
            Button(L.s("common.ok"), role: .cancel) { saveMessage = nil }
        } message: {
            Text(saveMessage ?? "")
        }
    }

    // MARK: - Podsumowanie

    private var summary: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text(ByteFormatting.string(result.originalByteCount))
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                Text(ByteFormatting.string(result.producedByteCount))
                    .fontWeight(.semibold)
            }
            .font(.title2)
            .monospacedDigit()

            if let percent = ByteFormatting.savingsPercent(
                original: result.originalByteCount,
                produced: result.producedByteCount
            ), percent > 0 {
                Text(L.f("result.saved", percent))
                    .font(.headline)
                    .foregroundStyle(.green)
            }

            Text(
                result.archives.isEmpty
                    ? L.f("result.fileCount", result.files.count)
                    : L.f("result.archiveCount", result.archives.count, result.files.count)
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    /// Informacja o tym, że tryb budżetowy zmienił ustawienia — użytkownik ma prawo
    /// wiedzieć, że dostał 1200 px zamiast zamówionych 1600 px, skoro sam prosił
    /// o zmieszczenie się w limicie.
    private var budgetNote: String? {
        guard result.budgetPasses > 1 else { return nil }
        let size = result.effectiveSettings.targetSize.pixels.map(TargetSize.label(forLongEdge:))
            ?? L.s("settings.longEdge.original")
        return L.f("result.budgetAdjusted", size, Int(result.effectiveSettings.quality * 100))
    }

    // MARK: - Miniatury

    private var thumbnails: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(result.files.prefix(16), id: \.url) { file in
                ResultThumbnail(url: file.url)
            }
        }
        .padding(.horizontal)
        .overlay(alignment: .bottom) {
            if result.files.count > 16 {
                Text(L.f("result.andMore", result.files.count - 16))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(.thinMaterial, in: Capsule())
                    .offset(y: 14)
            }
        }
    }

    // MARK: - Akcje

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                sharedURLs = shareable.map(\.url)
            } label: {
                Label(L.s("result.share"), systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            // Porcjowanie pokazujemy tylko wtedy, gdy realnie może być potrzebne.
            // Część komunikatorów przyjmuje najwyżej dziesięć elementów naraz, a my
            // nie mamy jak wykryć, którą aplikację użytkownik wybierze.
            if shareable.count > 10 {
                Button {
                    showsBatches = true
                } label: {
                    Label(L.s("result.shareBatches"), systemImage: "square.stack")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Text(L.s("result.batchHint"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                exportedURLs = shareable.map(\.url)
            } label: {
                Label(L.s("result.saveFiles"), systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                Task { await saveToPhotos() }
            } label: {
                HStack {
                    if isSaving { ProgressView().controlSize(.small) }
                    Label(L.s("result.savePhotos"), systemImage: "photo.badge.plus")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isSaving || result.files.isEmpty)
        }
        .padding(.horizontal)
    }

    private func saveToPhotos() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await PhotoSaver.save(result.files)
            saveMessage = L.f("result.savePhotos.success", result.files.count)
        } catch {
            saveMessage = error.localizedDescription
        }
    }
}

/// Miniatura pliku wynikowego, wczytywana z dysku w rozmiarze miniatury.
private struct ResultThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Color(.secondarySystemFill))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: url) {
            image = await ResultThumbnailLoader.load(url: url)
        }
    }
}

enum ResultThumbnailLoader {
    /// Dekodujemy od razu w rozmiarze miniatury. Wczytanie szesnastu pełnowymiarowych
    /// obrazów tylko po to, żeby je pokazać jako kwadraciki, byłoby najprostszą drogą
    /// do ubicia aplikacji zaraz po udanym przetworzeniu.
    static func load(url: URL) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [String: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways as String: true,
                kCGImageSourceThumbnailMaxPixelSize as String: 240,
                kCGImageSourceCreateThumbnailWithTransform as String: true
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return UIImage(cgImage: cgImage)
        }.value
    }
}
