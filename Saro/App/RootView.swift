import SaroKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.profile == nil || LaunchProgress.shared.demo != nil {
                LaunchView()
            } else if model.showsOnboarding {
                // A new profile row (Erase, or an import into a blank journal) is a new pass, read from the ledger again.
                OnboardingView().id(model.profile?.createdAt).ignoresSafeArea(.container, edges: .top).overlay { ToastHost() }
            } else {
                NavigationSplitView(columnVisibility: Binding(get: { model.sidebarVisible ? .all : .detailOnly },
                                                              set: { model.sidebarVisible = $0 != .detailOnly })) {
                    Sidebar()
                        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
                } detail: {
                    Group {
                        switch model.pane {
                        case .day: DayView()
                        case .trash: TrashPanel(style: .pane)
                        case .decisions:
                            #if DOGFOOD
                            DecisionsView()
                            #else
                            EmptyView()
                            #endif
                        case .knows: WhatSaroKnowsView()
                        }
                    }
                    .overlayPreferenceValue(TrashFlightKey.self) { ToastHost(flying: $0) }
                }
            }
        }
        .background(Tok.bg)
        .tint(Tok.sage)
        #if DOGFOOD
        .devMode()
        .overlay(alignment: .top) {
            if model.isDemo, model.pane == .decisions || model.devNotesVisible { DemoBanner() }
        }
        #endif
        .searchPalette(isPresented: $model.searchOpen)
        .shellSheets()
        .lockable()
        // Nothing stays open over the lock: the palette, the safety card and Adjust Mood close with it.
        .onChange(of: Locker.shared.locked) { _, locked in
            guard locked else { return }
            model.searchOpen = false
            model.safetyCardRequested = false
            model.reflection.adjustingMood = false
        }
        // Outside the lock, so If You're Struggling opens even while Saro is locked: it shows nothing of the journal.
        .sheet(isPresented: $model.safetyCardRequested) { SafetyCardView() }
        .background(ScreenShare())
    }
}

#if DOGFOOD
/// -SaroDemo opens a fresh temporary journal each launch, so decisions and notes recorded in it never reach an export.
private struct DemoBanner: View {
    var body: some View {
        Label("Demo journal: decisions and notes recorded here are gone after this launch.", systemImage: "exclamationmark.triangle")
            .font(Typo.ui(12, .medium))
            .foregroundStyle(Tok.warning)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .saroSurface(radius: 999)
            .padding(.top, 10)
    }
}
#endif

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section("Days") {
                if !model.days.contains(where: { $0.day == LocalDay.today() }) {
                    dayRow(LocalDay.today(), count: 0)
                }
                ForEach(model.days, id: \.day) { dayRow($0.day, count: $0.count) }
            }
            Section {
                row("What Saro knows", systemImage: "point.3.connected.trianglepath.dotted", selected: model.pane == .knows) { model.pane = .knows }
                row("Trash", systemImage: "trash", selected: model.pane == .trash) { model.pane = .trash }
                row("Decisions", systemImage: "checklist", selected: model.pane == .decisions) { model.pane = .decisions }
            }
        }
        .listStyle(.sidebar)
    }

    private func dayRow(_ day: String, count: Int) -> some View {
        row(DayFormat.sidebar(day), systemImage: day == LocalDay.today() ? "sun.max" : "calendar",
            selected: model.pane == .day && model.day == day, trailing: count > 0 ? "\(count)" : nil) { model.go(to: day) }
    }

    private func row(_ title: String, systemImage: String, selected: Bool, trailing: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label {
                    Text(title).font(Typo.ui(13, selected ? .medium : .regular)).foregroundStyle(Tok.ink)
                } icon: {
                    Image(systemName: systemImage).foregroundStyle(selected ? Tok.sageTeal : Tok.ink3)
                }
                Spacer()
                if let trailing { Text(trailing).font(Typo.mono(10)).foregroundStyle(Tok.ink3) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(selected ? Tok.sage.opacity(0.12) : Color.clear)
    }
}

enum DayFormat {
    static func sidebar(_ day: String) -> String {
        if day == LocalDay.today() { return "Today" }
        if day == LocalDay.adding(-1, to: LocalDay.today()) { return "Yesterday" }
        return LocalDay.date(day)?.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) ?? day
    }

    static func title(_ day: String) -> String {
        LocalDay.date(day)?.formatted(.dateTime.weekday(.wide).day().month(.wide)) ?? day
    }
}
