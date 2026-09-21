import Foundation
import OdbitkaKit

/// Szacunek rozmiaru wyniku, odświeżany przy zmianie ustawień.
///
/// Debounce jest tu konieczny, a nie kosmetyczny: każde przeliczenie realnie koduje
/// kilka zdjęć. Bez opóźnienia przeciągnięcie suwaka jakości uruchomiłoby kilkadziesiąt
/// przebiegów kodowania, grzejąc telefon bez żadnej korzyści.
@Observable
@MainActor
final class EstimateModel {
    private(set) var estimate: SizeEstimator.Estimate?
    private(set) var isEstimating = false

    private var task: Task<Void, Never>?
    private static let debounce = Duration.milliseconds(400)

    func schedule(photos: [any SourcePhoto], settings: ConversionSettings) {
        task?.cancel()
        guard !photos.isEmpty else {
            estimate = nil
            return
        }

        task = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }

            self?.isEstimating = true
            let result = await SizeEstimator.estimate(photos: photos, settings: settings)
            guard !Task.isCancelled else { return }
            self?.estimate = result
            self?.isEstimating = false
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
