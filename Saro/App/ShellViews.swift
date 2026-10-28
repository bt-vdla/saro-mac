import AppKit
import SaroKit
import SwiftUI

/// Trash (DR-15): soft-deleted entries, restorable one by one. ponytail: no purge yet; the 30-day purge comes with backups.
struct TrashView: View {
    @Environment(AppModel.self) private var model
    @State private var items: [Entry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Trash").font(Typo.serif(26, .medium)).padding(.horizontal, 28).padding(.top, 24)
            Text("Entries you deleted stay here and can be restored. Their recordings are kept.")
                .font(Typo.ui(13)).foregroundStyle(Tok.ink3).padding(.horizontal, 28).padding(.bottom, 12)
            if items.isEmpty {
                ContentUnavailableView("Trash is empty", systemImage: "trash")
            } else {
                List(items) { e in
                    HStack(spacing: 12) {
                        Image(systemName: e.kind.symbol).foregroundStyle(e.kind.tint).frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.titleUser ?? e.body?.split(separator: "\n").first.map(String.init) ?? e.kind.noun)
                                .font(Typo.ui(13, .medium)).lineLimit(1)
                            Text("\(DayFormat.sidebar(e.localDay).uppercased()) · DELETED \(e.trashedAt?.formatted(date: .abbreviated, time: .shortened).uppercased() ?? "")")
                                .font(Typo.mono(9.5)).foregroundStyle(Tok.ink3)
                        }
                        Spacer()
                        Button("Restore") {
                            Task {
                                await model.restore(ids: [e.id])
                                await load()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tok.bg)
        .task { await load() }
        .onAppear { model.screen = .trash }
    }

    private func load() async { items = (try? await model.ledger.trashed()) ?? [] }
}
