import PixportKit
import SwiftUI

/// Wysyłka porcjami.
///
/// Część komunikatorów (m.in. Signal i Viber) przyjmuje naraz najwyżej dziesięć
/// elementów. Nie da się tego wykryć: systemowy arkusz nie mówi nam, którą aplikację
/// użytkownik wybierze, a `completionHandler` informuje wyłącznie o tym, że arkusz
/// się zamknął — nie o tym, czy wiadomość poszła.
///
/// Dlatego porcjami steruje **użytkownik**, a nie automat. Widzi listę, wysyła po jednej,
/// odhacza wysłane i może powtórzyć tę, która się nie udała. Automatyczny łańcuch
/// wyskakujących arkuszy wyglądałby sprawniej dokładnie do pierwszego anulowania.
struct BatchShareView: View {
    let files: [ProcessedFile]

    @Environment(\.dismiss) private var dismiss
    @State private var batchSize = 10
    @State private var sentBatches: Set<Int> = []
    @State private var sharedBatch: Int?

    private var batches: [[ProcessedFile]] {
        stride(from: 0, to: files.count, by: batchSize).map {
            Array(files[$0..<min($0 + batchSize, files.count)])
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(L.s("batch.size"), selection: $batchSize) {
                        Text("5").tag(5)
                        Text("10").tag(10)
                        Text("20").tag(20)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: batchSize) { _, _ in sentBatches.removeAll() }
                } footer: {
                    Text(L.s("batch.footer"))
                }

                Section {
                    ForEach(Array(batches.enumerated()), id: \.offset) { index, batch in
                        Button {
                            sharedBatch = index
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L.f("batch.title", index + 1))
                                        .foregroundStyle(.primary)
                                    Text(L.f(
                                        "batch.range",
                                        index * batchSize + 1,
                                        index * batchSize + batch.count,
                                        ByteFormatting.string(batch.reduce(Int64(0)) { $0 + $1.byteCount })
                                    ))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if sentBatches.contains(index) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                } header: {
                    Text(L.f("batch.header", batches.count))
                }
            }
            .navigationTitle(L.s("batch.navTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.s("common.done")) { dismiss() }
                }
            }
            .sheet(item: Binding(
                get: { sharedBatch.map { BatchSelection(index: $0) } },
                set: { sharedBatch = $0?.index }
            )) { selection in
                ShareSheet(urls: batches[selection.index].map(\.url)) { completed in
                    // „Zamknięto bez anulowania" to wszystko, co wiemy — dlatego ptaszek
                    // jest szary i oznacza „wysłano", a nie „dostarczono".
                    if completed { sentBatches.insert(selection.index) }
                }
            }
        }
    }

    private struct BatchSelection: Identifiable {
        let index: Int
        var id: Int { index }
    }
}
