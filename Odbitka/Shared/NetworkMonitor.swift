import Foundation
import Network

/// Czy urządzenie ma jakiekolwiek połączenie.
///
/// Potrzebne wyłącznie do kontroli wstępnej: zdjęcia trzymane w iCloud wymagają
/// pobrania, a bez sieci przebieg i tak by padł — lepiej powiedzieć to w pierwszej
/// sekundzie niż w dziesiątej minucie. Aplikacja nie wykonuje żadnych własnych
/// zapytań sieciowych.
@Observable
@MainActor
final class NetworkMonitor {
    private(set) var isConnected = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "pl.froncek.odbitka.network")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in self?.isConnected = connected }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
