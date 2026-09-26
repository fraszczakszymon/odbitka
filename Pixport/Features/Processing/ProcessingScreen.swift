import PixportKit
import SwiftUI

/// Kroki trzeci i czwarty: postęp, a po nim wynik.
///
/// Oba żyją w jednym ekranie nawigacji, bo po zakończeniu przetwarzania nie ma
/// sensownego powodu, żeby użytkownik mógł cofnąć się do paska postępu.
struct ProcessingScreen: View {
    let request: JobRequest

    @Environment(NetworkMonitor.self) private var network
    @Environment(\.dismiss) private var dismiss
    @State private var model = ProcessingModel()

    var body: some View {
        Group {
            switch model.state {
            case .running:
                ProgressContent(model: model) {
                    model.cancel()
                    dismiss()
                }
            case .finished(let result):
                ResultView(result: result)
            case .failed(let error):
                FailureContent(error: error) { dismiss() }
            }
        }
        .navigationBarBackButtonHidden(isRunning)
        .interactiveDismissDisabled(isRunning)
        .task {
            model.start(request: request, isNetworkAvailable: network.isConnected)
        }
        .onAppear {
            // Ekran nie gaśnie w trakcie pracy. iOS daje aplikacji w tle około
            // trzydziestu sekund, więc zablokowanie telefonu przy dużej paczce
            // i tak by ją przerwało.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var isRunning: Bool {
        if case .running = model.state { return true }
        return false
    }
}

private struct ProgressContent: View {
    let model: ProcessingModel
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView(value: model.fraction)
                .progressViewStyle(.linear)
                .padding(.horizontal, 40)

            VStack(spacing: 6) {
                Text(model.countDescription)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text(model.stageDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(role: .destructive, action: onCancel) {
                Text(L.s("processing.cancel"))
            }
            .padding(.bottom, 32)
        }
        .padding()
        .navigationTitle(L.s("processing.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FailureContent: View {
    let error: ErrorPresentation
    let onBack: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(error.title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.message)
        } actions: {
            Button(L.s("processing.back")) { onBack() }
                .buttonStyle(.borderedProminent)
        }
        .navigationTitle(L.s("processing.failed.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
