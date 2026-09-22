import OdbitkaKit
import SwiftUI

/// Interfejs rozszerzenia: ustawienia, przetwarzanie i udostępnianie w jednym arkuszu.
///
/// Celowo osobny od ekranów aplikacji, a nie współdzielony. Widoki aplikacji sięgają po
/// `UIApplication.shared` i bibliotekę zdjęć, a w rozszerzeniu jedno jest niedostępne,
/// a drugie zbędne. Powielenie kilkudziesięciu linii formularza jest tańsze niż
/// utrzymywanie widoków, które muszą działać w dwóch różnych środowiskach.
struct ShareRootView: View {
    let photos: [HandoffPhoto]
    let onFinish: () -> Void

    @State private var store = SettingsStore()
    @State private var phase: Phase = .settings
    @State private var sharedURLs: [URL]?

    private enum Phase {
        case settings
        case working(String)
        case failed(ErrorPresentation)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .settings:
                    settingsForm
                case .working(let label):
                    working(label)
                case .failed(let error):
                    ContentUnavailableView {
                        Label(error.title, systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error.message)
                    } actions: {
                        Button(L.s("share.tryAgain")) { phase = .settings }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle(L.s("share.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.s("common.cancel")) { onFinish() }
                }
            }
            .sheet(item: Binding(get: { sharedURLs.map(URLBox.init) }, set: { sharedURLs = $0?.urls })) { box in
                ShareSheet(urls: box.urls) { _ in onFinish() }
            }
        }
    }

    private var settingsForm: some View {
        @Bindable var store = store

        return Form {
            Section(L.s("settings.section.format")) {
                Picker(L.s("settings.format"), selection: $store.settings.format) {
                    Text(L.s("settings.format.jpg")).tag(ImageFormat.jpeg)
                    Text(L.s("settings.format.png")).tag(ImageFormat.png)
                }
                .pickerStyle(.segmented)
            }

            Section(L.s("settings.section.size")) {
                Picker(L.s("settings.longEdge"), selection: Binding(
                    get: { store.settings.targetSize.pixels ?? 0 },
                    set: { store.settings.targetSize = $0 == 0 ? .original : .longEdge($0) }
                )) {
                    ForEach(TargetSize.presets) { Text($0.label).tag($0.pixels) }
                    Text(L.s("settings.longEdge.original")).tag(0)
                }
                if store.settings.format.supportsQuality {
                    VStack(alignment: .leading) {
                        HStack {
                            Text(L.s("settings.quality"))
                            Spacer()
                            Text("\(Int(store.settings.quality * 100))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $store.settings.quality, in: 0.3...1.0, step: 0.01)
                    }
                }
            }

            Section(L.s("settings.section.metadata")) {
                Toggle(L.s("settings.metadata.location"), isOn: $store.settings.metadata.keepLocation)
                Toggle(L.s("settings.metadata.dateTime"), isOn: $store.settings.metadata.keepDateTime)
                Toggle(L.s("settings.metadata.camera"), isOn: $store.settings.metadata.keepCameraInfo)
            }

            Section {
                TextField(L.s("settings.name.placeholder"), text: $store.settings.namePrefix)
                    .autocorrectionDisabled()
            } header: {
                Text(L.s("settings.section.name"))
            } footer: {
                Text(namePreview).monospaced()
            }

            Section(L.s("settings.section.packaging")) {
                Toggle(L.s("settings.zip"), isOn: $store.settings.packaging.makeZip)
            }

            Section {
                Button {
                    Task { await run() }
                } label: {
                    Text(L.f("share.process", photos.count))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }

    private func working(_ label: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var namePreview: String {
        let names = FileNamer.names(for: photos, prefix: store.settings.namePrefix, format: store.settings.format)
        guard let first = names.first else { return "" }
        guard names.count > 1, let last = names.last else { return first }
        return "\(first) … \(last)"
    }

    private func run() async {
        phase = .working(L.s("processing.stage.preparing"))
        do {
            let workspace = try Workspace()
            // Szeregowo, bez równoległości: w rozszerzeniu budżet pamięci jest tak wąski,
            // że dwa zdjęcia naraz to niepotrzebne ryzyko ubicia procesu przez system.
            let pipeline = ConversionPipeline(workspace: workspace, maxConcurrency: 1)
            let result = try await pipeline.run(
                photos: photos,
                settings: store.settings,
                isNetworkAvailable: true
            ) { progress in
                let label: String
                switch progress.stage {
                case .converting(let name): label = name
                case .packaging: label = L.s("processing.stage.packaging")
                default: label = L.s("processing.stage.preparing")
                }
                Task { @MainActor in phase = .working(label) }
            }
            sharedURLs = result.shareableFiles.map(\.url)
        } catch {
            phase = .failed(ErrorPresentation(error))
        }
    }
}

struct ShareStatusView: View {
    let text: String

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ShareMessageView: View {
    let message: String
    let onClose: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(L.s("share.title"), systemImage: "photo.badge.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button(L.s("common.close")) { onClose() }
                .buttonStyle(.borderedProminent)
        }
    }
}
