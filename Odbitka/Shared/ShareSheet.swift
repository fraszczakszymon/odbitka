import SwiftUI
import UIKit

/// Systemowy arkusz udostępniania.
///
/// **Reguła nienegocjowalna: przekazujemy `URL`-e plików z dysku, nigdy `UIImage`.**
/// Aplikacja, która dostaje obiekt obrazu, ma prawo osadzić go w treści wiadomości
/// i przekodować po swojemu — wtedy cała praca nad formatem, rozmiarem i metadanymi
/// idzie na marne. Plik na dysku Gmail dokłada jako **załącznik**, a nie wkleja w treść,
/// i to jest jedyna dźwignia, jaką nad tym mamy.
struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    var onComplete: ((Bool) -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            // Uwaga: `completed` mówi tylko tyle, że arkusz się zamknął bez anulowania.
            // Nie wiemy, czy wiadomość faktycznie poszła ani do kogo — dlatego
            // porcjowanie wysyłki jest sterowane ręcznie przez użytkownika.
            onComplete?(completed)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Eksport do aplikacji Pliki — a przez nią do Dysku Google, iCloud Drive czy OneDrive.
///
/// Osobna droga obok arkusza udostępniania, bo „wrzuć na dysk" przez arkusz to trzy
/// dodatkowe tapnięcia, a jest to jeden z dwóch głównych celów tej aplikacji.
struct DocumentExporter: UIViewControllerRepresentable {
    let urls: [URL]
    var onComplete: ((Bool) -> Void)?

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onComplete: ((Bool) -> Void)?
        init(onComplete: ((Bool) -> Void)?) { self.onComplete = onComplete }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onComplete?(true)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onComplete?(false)
        }
    }
}

/// Opakowanie listy adresów, żeby dało się jej użyć w `sheet(item:)`.
///
/// Współdzielone przez aplikację i rozszerzenie — oba prezentują arkusz w ten sam sposób.
struct URLBox: Identifiable {
    let urls: [URL]
    var id: String { urls.map(\.path).joined() }
}
