import PixportKit
import SwiftUI

@main
struct PixportApp: App {
    @State private var library = PhotoLibraryModel()
    @State private var settings = SettingsStore()
    @State private var network = NetworkMonitor()
    @State private var handoff = HandoffInbox()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(settings)
                .environment(network)
                .environment(handoff)
                .task {
                    // Pozostałości po poprzednich uruchomieniach znikają cicho, przy starcie.
                    Workspace.cleanUpPreviousSessions()
                    HandoffStore.cleanUp()
                }
                .onOpenURL { url in
                    handoff.receive(url)
                }
        }
    }
}

struct RootView: View {
    @Environment(PhotoLibraryModel.self) private var library
    @Environment(HandoffInbox.self) private var handoff
    @AppStorage("pl.froncek.pixport.welcomeShown") private var welcomeShown = false

    var body: some View {
        Group {
            if welcomeShown {
                LibraryView()
            } else {
                WelcomeView {
                    welcomeShown = true
                    Task { await library.requestAccess() }
                }
            }
        }
        .task {
            // O status uprawnień pytamy dopiero po ekranie powitalnym. Przed nim
            // aplikacja nie dotyka biblioteki zdjęć w żaden sposób.
            guard welcomeShown else { return }
            library.refreshAuthorization()
            // Powitanie już było, a zgody wciąż nie ma — tak kończy się zwinięcie
            // aplikacji w chwili, gdy stał na ekranie systemowy prompt. Bez tego
            // ekran zostawałby na kręciołku bez żadnego wyjścia.
            if library.access == .undetermined {
                await library.requestAccess()
            }
        }
        .sheet(item: handoffBinding) { session in
            NavigationStack {
                SettingsView(photos: session.photos)
            }
        }
    }

    private var handoffBinding: Binding<HandoffSession?> {
        Binding(
            get: { handoff.pending },
            set: { if $0 == nil { handoff.clear() } }
        )
    }
}
