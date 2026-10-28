import AppKit
import SaroKit
import SwiftUI

/// When the journal can't be opened (app/error.tsx): what happened, that the entries are safe, and what can be done here:
/// try again, show the journal's folder, put a daily snapshot back, or copy the error's code for a report. The raw error
/// waits behind a disclosure.
struct RecoveryView: View {
    let error: Error
    let retry: () -> Void
    @State private var snapshots = Ledger.snapshots()
    @State private var restoring: LedgerSnapshot?
    @State private var failed: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Saro couldn't open\nyour journal.").font(Typo.serif(34)).foregroundStyle(Tok.ink).lineSpacing(2)
            Text("Your entries are safe on this Mac.").font(Typo.ui(15)).foregroundStyle(Tok.ink2).padding(.top, 12)
            HStack(spacing: 8) {
                Button("Try again", action: retry).buttonStyle(SheetButton(primary: true)).keyboardShortcut(.defaultAction)
                Button("Show Journal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Ledger.defaultRoot])
                }
                .buttonStyle(SheetButton(primary: false))
                if !snapshots.isEmpty {
                    Menu("Restore from a Snapshot…") {
                        ForEach(snapshots) { s in
                            Button("\(DayFormat.title(s.day)) · \(ByteCountFormatter.string(fromByteCount: s.bytes, countStyle: .file))") { restoring = s }
                        }
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .font(Typo.ui(13, .medium))
                    .padding(.horizontal, 12)
                }
            }
            .padding(.top, 28)
            if let failed { Text(failed).font(Typo.ui(12)).foregroundStyle(Tok.danger).padding(.top, 12) }
            DisclosureGroup("Details") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(error.localizedDescription).font(Typo.mono(11, .regular)).foregroundStyle(Tok.ink2).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(copied ? "Copied" : "Copy Details") {
                        NSPasteboard.general.clearContents()
                        // The domain and code only, never the message, which can name a file.
                        NSPasteboard.general.setString("Saro \(AboutView.version) (\(AboutView.commit)): \(FailureCopy.code(error))", forType: .string)
                        copied = true
                    }
                    .buttonStyle(SheetButton(primary: false))
                }
                .padding(.top, 8)
            }
            .font(Typo.ui(12, .medium)).foregroundStyle(Tok.ink3)
            .padding(.top, 28)
        }
        .padding(48)
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { LitGround().ignoresSafeArea() }
        .background(Tok.bg)
        .confirmationDialog("Put back the journal as it was on \(restoring.map { DayFormat.title($0.day) } ?? "")?",
                            isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } })) {
            Button("Restore") { if let s = restoring { restore(s) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Entries saved after that day go aside, kept in Backups, not deleted. Recordings deleted since can't come back.")
        }
        .onAppear { AccessibilityNotification.Announcement("Saro couldn't open your journal. Your entries are safe on this Mac.").post() }
    }

    private func restore(_ s: LedgerSnapshot) {
        do {
            try Ledger.restore(snapshot: s.url)
            retry()
        } catch {
            failed = "That snapshot couldn't be put back. \(FailureCopy.remedy(for: error))"
        }
    }
}
