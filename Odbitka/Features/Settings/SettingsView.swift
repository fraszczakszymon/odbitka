import OdbitkaKit
import SwiftUI

/// Krok drugi: wszystkie ustawienia naraz.
///
/// Świadomie bez presetów i bez chowania opcji pod „Dostosuj" — użytkownik widzi
/// komplet decyzji na jednym ekranie, a wartości domyślne to te z ostatniego użycia.
struct SettingsView: View {
    let photos: [any SourcePhoto]

    @Environment(SettingsStore.self) private var store
    @State private var estimate = EstimateModel()
    @State private var customLongEdge = ""
    @State private var request: JobRequest?

    private var settings: ConversionSettings { store.settings }

    var body: some View {
        @Bindable var store = store

        Form {
            formatSection
            sizeSection
            metadataSection
            nameSection
            packagingSection
        }
        .navigationTitle(L.s("settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { actionBar }
        .navigationDestination(item: $request) { request in
            ProcessingScreen(request: request)
        }
        .onAppear { refreshEstimate() }
        .onChange(of: settings) { _, _ in refreshEstimate() }
        .onDisappear { estimate.cancel() }
    }

    // MARK: - Sekcje

    private var formatSection: some View {
        @Bindable var store = store

        return Section {
            Picker(L.s("settings.format"), selection: $store.settings.format) {
                Text(L.s("settings.format.jpg")).tag(ImageFormat.jpeg)
                Text(L.s("settings.format.png")).tag(ImageFormat.png)
            }
            .pickerStyle(.segmented)
        } header: {
            Text(L.s("settings.section.format"))
        } footer: {
            // PNG jest bezstratny, więc zdjęcie z aparatu potrafi w nim zająć kilka razy
            // więcej niż oryginalny HEIC. Bez tego ostrzeżenia użytkownik wybiera PNG
            // „bo lepszy" i dostaje paczkę cięższą od tego, co miał na wejściu.
            Text(settings.format == .png ? L.s("settings.format.png.warning") : L.s("settings.format.jpg.hint"))
        }
    }

    private var sizeSection: some View {
        @Bindable var store = store

        return Section {
            Picker(L.s("settings.longEdge"), selection: longEdgeBinding) {
                ForEach(TargetSize.presetValues, id: \.self) { value in
                    Text("\(value) px").tag(LongEdgeChoice.preset(value))
                }
                Text(L.s("settings.longEdge.original")).tag(LongEdgeChoice.original)
                Text(L.s("settings.longEdge.custom")).tag(LongEdgeChoice.custom)
            }

            if longEdgeBinding.wrappedValue == .custom {
                HStack {
                    Text(L.s("settings.longEdge.customValue"))
                    Spacer()
                    TextField("2000", text: $customLongEdge)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                        .onChange(of: customLongEdge) { _, value in
                            if let number = Int(value), number > 0 {
                                store.settings.targetSize = .longEdge(min(number, 20000))
                            }
                        }
                    Text("px").foregroundStyle(.secondary)
                }
            }

            if settings.format.supportsQuality {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L.s("settings.quality"))
                        Spacer()
                        Text("\(Int(settings.quality * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $store.settings.quality, in: 0.3...1.0, step: 0.01)
                }
            }

            Toggle(L.s("settings.budget"), isOn: $store.settings.budget.isEnabled)
            if settings.budget.isEnabled {
                Stepper(
                    L.f("settings.budget.value", settings.budget.megabytes),
                    value: $store.settings.budget.megabytes,
                    in: 1...500
                )
            }

            Toggle(L.s("settings.srgb"), isOn: $store.settings.convertToSRGB)
        } header: {
            Text(L.s("settings.section.size"))
        } footer: {
            Text(settings.budget.isEnabled ? L.s("settings.budget.footer") : L.s("settings.srgb.footer"))
        }
    }

    private var metadataSection: some View {
        @Bindable var store = store

        return Section {
            Toggle(L.s("settings.metadata.location"), isOn: $store.settings.metadata.keepLocation)
            Toggle(L.s("settings.metadata.dateTime"), isOn: $store.settings.metadata.keepDateTime)
            Toggle(L.s("settings.metadata.camera"), isOn: $store.settings.metadata.keepCameraInfo)
        } header: {
            Text(L.s("settings.section.metadata"))
        } footer: {
            Text(
                settings.metadata.keepLocation
                    ? L.s("settings.metadata.footer.withLocation")
                    : L.s("settings.metadata.footer.noLocation")
            )
        }
    }

    private var nameSection: some View {
        @Bindable var store = store

        return Section {
            TextField(L.s("settings.name.placeholder"), text: $store.settings.namePrefix)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
        } header: {
            Text(L.s("settings.section.name"))
        } footer: {
            Text(namePreview).monospaced()
        }
    }

    private var packagingSection: some View {
        @Bindable var store = store

        return Section {
            Toggle(L.s("settings.zip"), isOn: $store.settings.packaging.makeZip)
            if settings.packaging.makeZip {
                Toggle(L.s("settings.zip.split"), isOn: $store.settings.packaging.splitIntoParts)
                if settings.packaging.splitIntoParts {
                    Stepper(
                        L.f("settings.zip.partSize", settings.packaging.partMegabytes),
                        value: $store.settings.packaging.partMegabytes,
                        in: 1...500
                    )
                }
            }
        } header: {
            Text(L.s("settings.section.packaging"))
        } footer: {
            // ZIP nie zmniejsza paczki ze zdjęciami — one już są skompresowane.
            // Mówimy to wprost, bo inaczej użytkownik włącza pakowanie, licząc na
            // mniejszy rozmiar, i czuje się oszukany.
            Text(L.s("settings.zip.footer"))
        }
    }

    // MARK: - Pasek akcji

    private var actionBar: some View {
        VStack(spacing: 10) {
            HStack {
                Text(L.f("settings.summary.count", photos.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                estimateLabel
            }

            Button {
                request = JobRequest(photos: photos, settings: settings)
            } label: {
                Text(L.s("settings.process"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(photos.isEmpty)
        }
        .padding()
        .background(.bar)
    }

    @ViewBuilder
    private var estimateLabel: some View {
        if estimate.isEstimating {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(L.s("settings.estimate.working"))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } else if let value = estimate.estimate {
            VStack(alignment: .trailing, spacing: 1) {
                // Tylda jest tu celowa: rozmiar JPEG zależy od treści zdjęcia,
                // więc przy mieszanym zaznaczeniu potrafi się rozjechać.
                Text(L.f("settings.estimate.value", ByteFormatting.string(value.bytes)))
                    .font(.subheadline.weight(.semibold))
                // Gdy zdjęcia siedzą w iCloud, nie mamy czego zmierzyć i liczba pochodzi
                // z modelu. Użytkownik ma prawo wiedzieć, że to grubsze przybliżenie
                // niż zwykle — zamiast domyślać się, czemu liczba nie trzyma się wyniku.
                if !value.isMeasured {
                    Text(L.s("settings.estimate.rough"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Pomocnicze

    private var namePreview: String {
        let names = FileNamer.names(for: photos, prefix: settings.namePrefix, format: settings.format)
        guard let first = names.first else { return "" }
        guard names.count > 1, let last = names.last else { return first }
        return names.count == 2 ? "\(first), \(last)" : "\(first), … , \(last)"
    }

    private enum LongEdgeChoice: Hashable {
        case preset(Int)
        case original
        case custom
    }

    private var longEdgeBinding: Binding<LongEdgeChoice> {
        Binding(
            get: {
                switch settings.targetSize {
                case .original: .original
                case .longEdge(let value):
                    TargetSize.presetValues.contains(value) ? .preset(value) : .custom
                }
            },
            set: { choice in
                switch choice {
                case .original:
                    store.settings.targetSize = .original
                case .preset(let value):
                    store.settings.targetSize = .longEdge(value)
                case .custom:
                    let current = settings.targetSize.pixels ?? 2000
                    customLongEdge = String(current)
                    store.settings.targetSize = .longEdge(current)
                }
            }
        )
    }

    private func refreshEstimate() {
        estimate.schedule(photos: photos, settings: settings)
    }
}

/// Zamówienie przetwarzania — komplet tego, co potrzebne do uruchomienia przebiegu.
struct JobRequest: Identifiable, Hashable {
    let id = UUID()
    let photos: [any SourcePhoto]
    let settings: ConversionSettings

    static func == (lhs: JobRequest, rhs: JobRequest) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
