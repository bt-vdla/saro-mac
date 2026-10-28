import AppKit
import SaroKit
import SwiftUI

/// Trash (DR-15, FR-DAY-05): soft-deleted entries, restorable one by one or all at once, deleted for good one by one,
/// all at once, or by the launch sweep 30 days on. Deleting for good asks first.
struct TrashView: View {
    @Environment(AppModel.self) private var model
    @State private var items: [Entry] = []
    /// What a Delete or Empty Trash… is asking about.
    @State private var confirming: [String]?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Trash").font(Typo.serif(26, .medium))
                Spacer()
                if !items.isEmpty {
                    Button("Restore All") { Task { await restore(items.map(\.id)) } }
                    Button("Empty Trash…") { confirming = items.map(\.id) }
                }
            }
            .padding(.horizontal, 28).padding(.top, 24)
            Text("Entries you deleted wait here for 30 days, then they’re deleted for good with their recordings and photos.")
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
                        Button("Restore") { Task { await restore([e.id]) } }
                        Button("Delete…") { confirming = [e.id] }
                    }
                    .padding(.vertical, 4)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tok.bg)
        .confirmationDialog(confirming?.count == 1 ? "Delete this entry forever?" : "Delete all \(confirming?.count ?? 0) entries forever?",
                            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            presenting: confirming) { ids in
            Button("Delete Forever", role: .destructive) { Task { await deleteForGood(ids) } }
            Button("Keep", role: .cancel) {}
        } message: { _ in
            Text("This can’t be undone.")
        }
        .task { await load() }
        .onAppear { model.screen = .trash }
    }

    private func load() async { items = (try? await model.ledger.trashed()) ?? [] }

    private func restore(_ ids: [String]) async {
        await model.restore(ids: ids)
        await load()
    }

    private func deleteForGood(_ ids: [String]) async {
        do {
            let n = try await model.ledger.purge(ids)
            model.show(Toast(n == 1 ? "Deleted for good" : "Deleted \(n) for good"))
        } catch {
            model.show(Toast("Couldn’t delete: \(error.localizedDescription)", style: .error))
        }
        await load()
    }
}
