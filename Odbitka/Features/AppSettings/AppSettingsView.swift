import OdbitkaKit
import SwiftUI

/// Ustawienia aplikacji: miejsce na dysku, informacje, prywatność.
struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var occupiedBytes: Int64 = 0

    private var version: String {
        let bundle = Bundle.main
        let short = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(L.s("appSettings.storage.used"), value: ByteFormatting.string(occupiedBytes))
                    Button(L.s("appSettings.storage.clear"), role: .destructive) {
                        Workspace.cleanUpPreviousSessions()
                        refresh()
                    }
                    .disabled(occupiedBytes == 0)
                } header: {
                    Text(L.s("appSettings.section.storage"))
                } footer: {
                    Text(L.s("appSettings.storage.footer"))
                }

                Section {
                    Text(L.s("appSettings.privacy.body"))
                        .font(.callout)
                } header: {
                    Text(L.s("appSettings.section.privacy"))
                }

                Section {
                    LabeledContent(L.s("appSettings.version"), value: version)
                } header: {
                    Text(L.s("appSettings.section.about"))
                } footer: {
                    Text(L.s("appSettings.about.footer"))
                }
            }
            .navigationTitle(L.s("appSettings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.s("common.done")) { dismiss() }
                }
            }
            .task { refresh() }
        }
    }

    private func refresh() {
        occupiedBytes = Workspace.occupiedBytes()
    }
}
