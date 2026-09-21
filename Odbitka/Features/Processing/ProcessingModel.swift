import Foundation
import OdbitkaKit
import SwiftUI

/// Sterowanie jednym przebiegiem przetwarzania.
@Observable
@MainActor
final class ProcessingModel {

    enum State {
        case running
        case finished(ConversionResult)
        case failed(ErrorPresentation)
    }

    private(set) var state: State = .running
    private(set) var progress: ConversionPipeline.Progress?
    private(set) var workspace: Workspace?

    private var task: Task<Void, Never>?

    /// Równoległość dwóch zadań. Pojedyncze nie wysyca rdzeni, cztery przy RAW-ach
    /// potrafią przekroczyć budżet pamięci procesu.
    private static let concurrency = 2

    func start(request: JobRequest, isNetworkAvailable: Bool) {
        guard task == nil else { return }

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let workspace = try Workspace()
                self.workspace = workspace
                // Sprzątamy pozostałości po poprzednich uruchomieniach, ale nie po tym.
                Workspace.cleanUpPreviousSessions(keeping: workspace.sessionID)

                let pipeline = ConversionPipeline(workspace: workspace, maxConcurrency: Self.concurrency)
                let result = try await pipeline.run(
                    photos: request.photos,
                    settings: request.settings,
                    isNetworkAvailable: isNetworkAvailable
                ) { progress in
                    Task { @MainActor in self.progress = progress }
                }
                self.state = .finished(result)
            } catch {
                self.state = .failed(ErrorPresentation(error))
            }
        }
    }

    /// Anulowanie kasuje wyniki częściowe — semantyka aplikacji to wszystko albo nic,
    /// więc połowa paczki nie ma prawa trafić do udostępniania.
    func cancel() {
        task?.cancel()
        task = nil
        workspace?.discardOutputs()
    }

    /// Opis bieżącego etapu dla paska postępu.
    var stageDescription: String {
        guard let progress else { return L.s("processing.stage.preparing") }
        switch progress.stage {
        case .preparing:
            return L.s("processing.stage.preparing")
        case .downloading(let fileName, let fraction):
            return L.f("processing.stage.downloading", fileName, Int(fraction * 100))
        case .converting(let fileName):
            return fileName
        case .retryingForBudget(let pass):
            return L.f("processing.stage.budget", pass)
        case .packaging(let part, let partCount, _):
            return partCount > 1
                ? L.f("processing.stage.packagingPart", part + 1, partCount)
                : L.s("processing.stage.packaging")
        }
    }

    var countDescription: String {
        guard let progress, progress.total > 0 else { return "" }
        return L.f("processing.count", progress.completed, progress.total)
    }

    var fraction: Double {
        guard let progress else { return 0 }
        if case .packaging(_, _, let value) = progress.stage { return value }
        return progress.fraction
    }
}
