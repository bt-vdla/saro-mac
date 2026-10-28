import AppKit
import SaroKit
import SwiftUI

/// 08 Your data (DataSection.tsx, NFR-02, FR-SET-05): what the privacy promise means here, what the journal weighs,
/// taking it with you (everything, or a year as a book), what Saro read, the lock, and erasing.
struct DataSection: View {
    @Environment(AppModel.self) private var model
    @AppStorage("videoQuality") private var videoQuality = "720p"
    @State private var save = Autosave()
    @State private var storage: StorageSummary?
    @State private var storageFailed = false

    var body: some View {
        SettingsCard(label: "Your data", title: "Visibly yours", autosave: save) {
            promise
            RowRule()
            storageRow
            SettingsRow("Recording quality", caption: videoQuality == "1080p" ? "1080p moments take about twice the room." : "720p keeps a year of moments small.") {
                Picker("Recording quality", selection: $videoQuality) {
                    Text("720p HEVC").tag("720p")
                    Text("1080p HEVC").tag("1080p")
                }
                .labelsHidden().fixedSize()
                .onChange(of: videoQuality) { save.saved() }
            }
            RowRule()
            ExportRow()
            RowRule()
            BookRow()
            RowRule()
            ReadLog()
            RowRule()
            lock
            RowRule()
            EraseRow()
        }
        .task { await loadStorage() }
    }

    // MARK: What this means

    private var promise: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What this means").font(Typo.ui(14.5, .medium)).foregroundStyle(Tok.ink)
            ForEach(PrivacyCopy.nfr02, id: \.self) { line in
                Text(line).font(Typo.serif(16.5)).foregroundStyle(Tok.ink).fixedSize(horizontal: false, vertical: true)
            }
            if PrefsStore.shared.writingTools {
                Label("Writing Tools is on: Apple may use Private Cloud Compute, or ChatGPT if you’ve turned it on, for text you select.", systemImage: "exclamationmark.circle")
                    .font(Typo.ui(12)).foregroundStyle(Tok.warning)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Proof you can check").monoCaps(10.5).foregroundStyle(Tok.ink3)
                ForEach(PrivacyCopy.promises.flatMap(\.proofs), id: \.self) { proof in
                    Text(proof).font(Typo.mono(11)).foregroundStyle(Tok.ink2).textSelection(.enabled)
                }
            }
            .padding(.top, 4)
        }
        .padding(.bottom, 16)
    }

    // MARK: Storage

    private var storageRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Storage").font(Typo.ui(14.5, .medium)).foregroundStyle(Tok.ink)
                Spacer()
                if let storage { Text(bytes(storage.totalBytes)).font(Typo.mono(12)).monospacedDigit().foregroundStyle(Tok.ink2) }
            }
            Text("On this Mac, inside Saro’s private container.").font(Typo.ui(12)).foregroundStyle(Tok.ink3)
            if storageFailed {
                HStack(spacing: 4) {
                    Text("Couldn’t add up your storage right now.")
                    Button("Retry") { Task { await loadStorage() } }.buttonStyle(.settingsLink)
                }
                .font(Typo.ui(12)).foregroundStyle(Tok.ink2)
            } else if let storage {
                let shown = storage.kinds.filter { $0.count > 0 || $0.bytes > 0 }
                if shown.isEmpty {
                    Text("Nothing stored yet.").font(Typo.ui(14)).foregroundStyle(Tok.ink2)
                } else {
                    StorageBar(kinds: shown, total: storage.totalBytes)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 32), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                        ForEach(shown, id: \.kind) { k in
                            HStack(spacing: 8) {
                                Circle().fill(k.kind.tint).frame(width: 8, height: 8)
                                Text(Self.plural(k.kind)).font(Typo.ui(13)).foregroundStyle(Tok.ink2)
                                Text("\(k.count)").font(Typo.ui(13)).monospacedDigit().foregroundStyle(Tok.ink3)
                                Spacer()
                                Text(bytes(k.bytes)).font(Typo.mono(11)).monospacedDigit().foregroundStyle(Tok.ink3)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    if storage.trashBytes > 0 {
                        Text("Includes \(bytes(storage.trashBytes)) in Trash.").font(Typo.ui(12)).foregroundStyle(Tok.ink3)
                    }
                }
                VStack(spacing: 4) {
                    line("Journal database", storage.databaseBytes)
                    line("Backups", storage.backupsBytes, empty: "None yet")
                }
                .padding(.top, 4)
                if !storage.largest.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Space saver · the largest").monoCaps(10.5).foregroundStyle(Tok.ink3)
                        ForEach(storage.largest.prefix(3), id: \.entryId) { item in
                            Button { model.open(DeepLink.entry(item.entryId).url) } label: {
                                HStack {
                                    Image(systemName: item.kind.symbol).foregroundStyle(item.kind.tint).frame(width: 16)
                                    Text("\(item.kind.noun) · \(AILog.shortDay(item.day))").foregroundStyle(Tok.ink2)
                                    Spacer()
                                    Text(bytes(item.bytes)).font(Typo.mono(11)).monospacedDigit().foregroundStyle(Tok.ink3)
                                }
                                .font(Typo.ui(13)).contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens the entry")
                        }
                    }
                    .padding(.top, 6)
                }
            } else {
                Capsule().fill(Tok.ink.opacity(0.06)).frame(height: 8).accessibilityLabel("Adding up your storage…")
            }
        }
        .padding(.vertical, 16)
    }

    private func line(_ label: String, _ n: Int64, empty: String? = nil) -> some View {
        HStack {
            Text(label).font(Typo.ui(13)).foregroundStyle(Tok.ink2)
            Spacer()
            Text(n == 0 && empty != nil ? empty! : bytes(n)).font(Typo.mono(11)).monospacedDigit().foregroundStyle(Tok.ink3)
        }
    }

    private func loadStorage() async {
        storageFailed = false
        do { storage = try await model.ledger.storageSummary() } catch { storageFailed = true }
    }

    static func plural(_ kind: EntryKind) -> String {
        switch kind {
        case .moment: "Moments"
        case .voice: "Voice notes"
        case .still: "Stills"
        case .reflection: "Reflections"
        case .music: "Music"
        }
    }

    // MARK: Lock

    private var lock: some View {
        let prefs = PrefsStore.shared
        return VStack(alignment: .leading, spacing: 0) {
            SettingsRow("Lock with Touch ID", caption: "Saro asks for your fingerprint or password when you come back, and locks when your Mac sleeps. It's a lock on the window, not encryption.") {
                Toggle("Lock with Touch ID", isOn: Binding(get: { prefs.lockEnabled }, set: { prefs.lockEnabled = $0; save.saved() }))
                    .toggleStyle(.sage).labelsHidden()
            }
            if prefs.lockEnabled {
                SettingsRow("After you’ve been away") {
                    Picker("After you’ve been away", selection: Binding(get: { prefs.lockAfter }, set: { prefs.lockAfter = $0; save.saved() })) {
                        Text("Immediately").tag(Prefs.LockAfter.immediately)
                        Text("5 minutes").tag(Prefs.LockAfter.fiveMinutes)
                        Text("1 hour").tag(Prefs.LockAfter.hour)
                        Text("Never").tag(Prefs.LockAfter.never)
                    }
                    .labelsHidden().fixedSize()
                }
            }
            SettingsRow("Hide from screen sharing", caption: "Hides Saro from most screen sharing. Test it with your app.") {
                Toggle("Hide from screen sharing", isOn: Binding(get: { prefs.hideFromScreenShare }, set: { prefs.hideFromScreenShare = $0; save.saved() }))
                    .toggleStyle(.sage).labelsHidden()
            }
        }
        .animation(Motion.fade, value: prefs.lockEnabled)
    }
}

private func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

/// One segmented bar by kind, each segment at least 3 pt so a small kind still shows.
private struct StorageBar: View {
    let kinds: [StorageSummary.Kind]
    let total: Int64

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(kinds, id: \.kind) { k in
                    Rectangle().fill(k.kind.tint)
                        .frame(width: max(k.bytes > 0 ? 3 : 0, geo.size.width * CGFloat(k.bytes) / CGFloat(max(total, 1))))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 8)
        .background(Tok.ink.opacity(0.06))
        .clipShape(.capsule)
        .accessibilityElement()
        .accessibilityLabel("Storage by type: " + kinds.map { "\(DataSection.plural($0.kind)) \(bytes($0.bytes))" }.joined(separator: ", "))
    }
}

/// Everything, as a folder you can read anywhere; and Import, which adds an export back.
private struct ExportRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let progress = DataProgress.shared
        VStack(alignment: .leading, spacing: 8) {
            Text("Take it with you").font(Typo.ui(14.5, .medium)).foregroundStyle(Tok.ink)
            Text("Everything as one folder: every row of your journal as JSON, this Mac’s settings, and every recording and photo beside them.")
                .font(Typo.ui(12)).foregroundStyle(Tok.ink3).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { Task { await model.exportEverything() } } label: {
                    Label(progress.exporting == nil ? "Export Everything…" : "Preparing…", systemImage: "square.and.arrow.up")
                }
                .disabled(progress.exporting != nil)
                Button { Task { await model.importJournal() } } label: {
                    Label(progress.importing == nil ? "Import…" : "Importing…", systemImage: "square.and.arrow.down")
                }
                .disabled(progress.importing != nil)
            }
            .buttonStyle(.settingsQuiet)
            if let f = progress.exporting ?? progress.importing {
                ProgressView(value: f).progressViewStyle(.linear).tint(Tok.sage).frame(maxWidth: 320)
                    .accessibilityLabel(progress.exporting != nil ? "Exporting" : "Importing")
            }
            Text("Import adds what an export holds that this journal doesn’t; nothing here is replaced.")
                .font(Typo.ui(12)).foregroundStyle(Tok.ink3)
        }
        .padding(.vertical, 16)
    }
}

/// Book of the year: your words and the letters you kept, one chapter a month, as HTML or PDF.
private struct BookRow: View {
    @Environment(AppModel.self) private var model
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var working = false
    @State private var failed: String?
    @State private var pdf = false

    private var years: [Int] {
        let now = Calendar.current.component(.year, from: .now)
        let found = Set(model.days.compactMap { Int($0.day.prefix(4)) })
        return Array(found.union([now])).sorted(by: >)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Book of \(String(year))").font(Typo.ui(14.5, .medium)).foregroundStyle(Tok.ink)
            Text("A year as a book you can read: your words and the letters you kept, one chapter a month. Saro’s own titles and held days’ letters never appear.")
                .font(Typo.ui(12)).foregroundStyle(Tok.ink3).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if years.count > 1 {
                    Picker("Year", selection: $year) { ForEach(years, id: \.self) { Text(String($0)).tag($0) } }
                        .labelsHidden().fixedSize()
                }
                Button { bind(pdf: false) } label: { Label(working ? "Binding…" : "Save as HTML…", systemImage: "book") }
                Button { bind(pdf: true) } label: { Text("Save as PDF…") }
            }
            .buttonStyle(.settingsQuiet)
            .disabled(working)
            if let failed {
                HStack(spacing: 4) {
                    Text("Couldn’t bind your book. \(failed)")
                    Button("Retry") { bind(pdf: pdf) }.buttonStyle(.settingsLink(Tok.danger))
                }
                .font(Typo.ui(12)).foregroundStyle(Tok.danger)
            }
        }
        .padding(.vertical, 16)
    }

    private func bind(pdf: Bool) {
        working = true
        failed = nil
        self.pdf = pdf
        Task {
            defer { working = false }
            do {
                if try await model.exportBook(year: year, pdf: pdf) { model.show(Toast("Book of \(year) saved")) }
            } catch {
                failed = error.localizedDescription
            }
        }
    }
}

/// What Saro read (FR-SET-05): every ai_run, by day, 20 at a time, never the words. A row opens what it read.
private struct ReadLog: View {
    @Environment(AppModel.self) private var model
    @State private var rows: [AILog.Row] = []
    @State private var total = 0
    @State private var loaded = false
    private static let page = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("What Saro read").font(Typo.ui(14.5, .medium)).foregroundStyle(Tok.ink)
                Spacer()
                Text("On this Mac").monoCaps(10.5).foregroundStyle(Tok.ink3)
            }
            Text("Which feature, when, what it read, and how much. Never the words themselves.").font(Typo.ui(12)).foregroundStyle(Tok.ink3)
            if loaded, rows.isEmpty {
                Text("Nothing yet. When Saro reads your words to write something, it’s listed here.").font(Typo.ui(14)).foregroundStyle(Tok.ink2)
            }
            ForEach(AILog.groupByDay(rows), id: \.day) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(AILog.shortDay(group.day)).monoCaps(10.5).foregroundStyle(Tok.ink3).accessibilityAddTraits(.isHeader)
                    ForEach(group.rows) { row in
                        Button { open(row) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(row.at.formatted(date: .omitted, time: .shortened)).font(Typo.mono(11)).monospacedDigit().foregroundStyle(Tok.ink3)
                                    .frame(width: 64, alignment: .leading)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(AILog.label(row.feature)).font(Typo.ui(13, .semibold)).foregroundStyle(Tok.ink)
                                    Text(AILog.describe(row)).font(Typo.ui(12)).foregroundStyle(Tok.ink3).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(row.entryIds.isEmpty)
                        .accessibilityHint(row.entryIds.isEmpty ? "" : "Opens what it read")
                    }
                }
                .padding(.top, 6)
            }
            if total > rows.count {
                Button { Task { await more() } } label: {
                    HStack(spacing: 6) {
                        Text("Show more")
                        Text("\(total - rows.count)").font(Typo.mono(11)).monospacedDigit().foregroundStyle(Tok.ink3)
                    }
                }
                .buttonStyle(.settingsQuiet)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 16)
        .task {
            total = (try? await model.ledger.aiRunCount()) ?? 0
            rows = (try? await model.ledger.aiLog(offset: 0, limit: Self.page)) ?? []
            loaded = true
        }
    }

    private func more() async {
        rows += (try? await model.ledger.aiLog(offset: rows.count, limit: Self.page)) ?? []
    }

    /// One entry opens itself; several open their day.
    private func open(_ row: AILog.Row) {
        if row.entryIds.count == 1, let id = row.entryIds.first { model.open(DeepLink.entry(id).url) }
        else if let day = row.localDay { model.open(DeepLink.day(day).url) }
    }
}

/// Erase everything on this Mac: typed DELETE, with Export first beside it.
private struct EraseRow: View {
    @Environment(AppModel.self) private var model
    @State private var open = false
    @State private var typed = ""
    @State private var working = false
    @State private var failed: String?
    @FocusState private var focused: Bool

    private var ready: Bool { typed.trimmingCharacters(in: .whitespaces) == "DELETE" && !working }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Erase everything on this Mac").font(Typo.ui(14.5, .medium)).foregroundStyle(Tok.ink)
            Text("Every entry, recording, photo, reading and letter, every backup, your reminders and these settings. It can’t be undone, so export first if you might want them.")
                .font(Typo.ui(12)).foregroundStyle(Tok.ink3).fixedSize(horizontal: false, vertical: true)
            if open {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Type DELETE to confirm").font(Typo.ui(12, .medium)).foregroundStyle(Tok.ink2)
                    HStack(spacing: 8) {
                        TextField("DELETE", text: $typed)
                            .textFieldStyle(.plain).font(Typo.mono(13)).autocorrectionDisabled()
                            .focused($focused)
                            .onSubmit { if ready { erase() } }
                            .padding(.horizontal, 12).frame(height: 32)
                            .background(Tok.surfaceAlt, in: .rect(cornerRadius: Radius.field))
                            .overlay(RoundedRectangle(cornerRadius: Radius.field).strokeBorder(focused ? Tok.danger : Tok.border))
                            .frame(maxWidth: 160)
                            .accessibilityLabel("Type DELETE to confirm")
                        Button(working ? "Erasing…" : "Erase Everything") { erase() }.buttonStyle(.settingsDanger).disabled(!ready)
                        Button("Export First…") { Task { await model.exportEverything() } }.buttonStyle(.settingsQuiet)
                        Button("Keep Everything") { close() }.buttonStyle(.settingsQuiet)
                    }
                    if let failed {
                        Text("Couldn’t finish erasing: \(failed)").font(Typo.ui(12)).foregroundStyle(Tok.danger)
                    }
                }
                .padding(14)
                .background(Tok.dangerBg, in: .rect(cornerRadius: Radius.field))
                .overlay(RoundedRectangle(cornerRadius: Radius.field).strokeBorder(Tok.dangerBorder))
                .onKeyPress(.escape) { close(); return .handled }
                .transition(.opacity)
            } else {
                Button("Erase Everything…") {
                    open = true
                    focused = true
                }
                .buttonStyle(.settingsDanger)
            }
        }
        .padding(.vertical, 16)
        .animation(Motion.fade, value: open)
    }

    private func close() {
        open = false
        typed = ""
        failed = nil
    }

    private func erase() {
        guard ready else { return }
        working = true
        Task {
            defer { working = false }
            do {
                try await model.eraseEverything()
                close()
                NSApp.keyWindow?.performClose(nil)
                WindowActions.openMain()
            } catch {
                failed = error.localizedDescription
            }
        }
    }
}
