import Foundation
import OdbitkaKit
import Photos

/// Zapis gotowych plików z powrotem do biblioteki zdjęć.
///
/// Prosimy o uprawnienie `addOnly` i **dopiero przy pierwszym użyciu tego przycisku** —
/// nigdy przy starcie aplikacji. Większość sesji kończy się udostępnieniem, więc
/// pytanie z góry byłoby pytaniem o coś, czego użytkownik może nigdy nie potrzebować.
enum PhotoSaver {

    enum SaveError: LocalizedError {
        case denied
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .denied: L.s("result.savePhotos.denied")
            case .failed(let message): message
            }
        }
    }

    static func save(_ files: [ProcessedFile]) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw SaveError.denied
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                for file in files {
                    // Archiwum ZIP nie jest zdjęciem — biblioteka go nie przyjmie.
                    guard file.url.pathExtension.lowercased() != "zip" else { continue }
                    PHAssetCreationRequest.forAsset()
                        .addResource(with: .photo, fileURL: file.url, options: nil)
                }
            }
        } catch {
            throw SaveError.failed(error.localizedDescription)
        }
    }
}
