import OdbitkaKit
import Photos
import PhotosUI
import SwiftUI

/// Ekran startowy: siatka biblioteki zdjęć.
///
/// Aplikacja otwiera się prosto tutaj — bez ekranu głównego, bez kafli, bez presetów.
/// Najkrótsza możliwa droga od uruchomienia do roboty.
struct LibraryView: View {
    @Environment(PhotoLibraryModel.self) private var library
    @State private var showsAppSettings = false

    private let spacing: CGFloat = 2

    var body: some View {
        @Bindable var library = library

        NavigationStack {
            Group {
                switch library.access {
                case .denied:
                    AccessDeniedView()
                case .undetermined:
                    ProgressView()
                case .authorized, .limited:
                    content
                }
            }
            .navigationTitle(L.s("library.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(isPresented: $showsAppSettings) {
                AppSettingsView()
            }
            .safeAreaInset(edge: .bottom) {
                if !library.selection.isEmpty {
                    SelectionBar()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            if library.access == .limited {
                LimitedAccessBar()
            }

            if library.isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if library.visibleAssets.isEmpty {
                EmptyLibraryView()
            } else {
                grid
            }
        }
    }

    private var grid: some View {
        GeometryReader { proxy in
            let columns = 4
            let side = (proxy.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)

            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns),
                    spacing: spacing
                ) {
                    ForEach(library.visibleAssets, id: \.localIdentifier) { asset in
                        PhotoCell(
                            asset: asset,
                            side: side,
                            isSelected: library.selection.contains(asset.localIdentifier)
                        )
                        .onTapGesture { library.toggle(asset) }
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showsAppSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel(L.s("library.appSettings"))
        }
        ToolbarItem(placement: .topBarTrailing) {
            if library.selection.isEmpty {
                Button(L.s("library.selectAll")) { library.selectAllVisible() }
                    .disabled(library.visibleAssets.isEmpty)
            } else {
                Button(L.s("library.deselect")) { library.clearSelection() }
            }
        }
    }
}

private struct PhotoCell: View {
    let asset: PHAsset
    let side: CGFloat
    let isSelected: Bool

    var body: some View {
        ThumbnailView(asset: asset, side: side)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isSelected ? Color.accentColor : Color.black.opacity(0.35))
                    .padding(5)
                    .shadow(radius: 2)
            }
            .overlay {
                if isSelected {
                    Rectangle().strokeBorder(Color.accentColor, lineWidth: 3)
                }
            }
    }
}

/// Pasek u dołu z podsumowaniem zaznaczenia.
private struct SelectionBar: View {
    @Environment(PhotoLibraryModel.self) private var library

    var body: some View {
        VStack(spacing: 10) {
            Text(
                L.f(
                    "library.selection.summary",
                    library.selection.count,
                    ByteFormatting.string(library.selectionByteCount)
                )
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            NavigationLink {
                SettingsView(photos: library.selectedPhotos())
            } label: {
                Text(L.s("library.next"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .background(.bar)
    }
}

private struct LimitedAccessBar: View {
    var body: some View {
        HStack {
            Image(systemName: "photo.badge.exclamationmark")
            Text(L.s("library.limited.message"))
                .font(.footnote)
            Spacer()
            Button(L.s("library.limited.action")) {
                PhotoAccessPresenter.presentLimitedPicker()
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }
}

private struct EmptyLibraryView: View {
    var body: some View {
        ContentUnavailableView {
            Label(L.s("library.empty.title"), systemImage: "photo.on.rectangle.angled")
        } description: {
            Text(L.s("library.empty.message"))
        }
    }
}

private struct AccessDeniedView: View {
    var body: some View {
        ContentUnavailableView {
            Label(L.s("library.denied.title"), systemImage: "lock")
        } description: {
            Text(L.s("library.denied.message"))
        } actions: {
            Button(L.s("library.denied.action")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// Otwiera systemowy edytor zaznaczenia w trybie ograniczonego dostępu.
enum PhotoAccessPresenter {
    @MainActor
    static func presentLimitedPicker() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController
        else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
    }
}
