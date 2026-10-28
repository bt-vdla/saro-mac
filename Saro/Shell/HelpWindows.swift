import AppKit
import SaroKit
import SwiftUI

/// About Saro: the logo, the version and the commit it was built from, and where it lives.
struct AboutView: View {
    @Environment(\.openWindow) private var openWindow

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
    static var commit: String { Bundle.main.object(forInfoDictionaryKey: "SaroGitCommit") as? String ?? "unknown" }

    var body: some View {
        VStack(spacing: 0) {
            Image("Logo").resizable().scaledToFit().frame(width: 88, height: 88).accessibilityHidden(true)
            Text("Saro").font(Typo.serif(30, .medium)).foregroundStyle(Tok.ink).padding(.top, 14)
            Text("Version \(Self.version) (\(Self.build)) · \(Self.commit)")
                .font(Typo.mono(11)).foregroundStyle(Tok.ink3).textSelection(.enabled).padding(.top, 6)
            Text("Made to stay on this Mac.").font(Typo.serif(16, italic: true)).foregroundStyle(Tok.voice).padding(.top, 18)
            Text("Your journal, its recordings and everything Saro reads from them stay in one folder on this Mac. Nothing is sent anywhere.")
                .font(Typo.ui(12)).foregroundStyle(Tok.ink2).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Button("Acknowledgements") { openWindow(id: "acknowledgements") }
                .buttonStyle(.link).font(Typo.ui(12, .medium)).padding(.top, 18)
            Text(Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "")
                .font(Typo.ui(11)).foregroundStyle(Tok.ink3).padding(.top, 6)
        }
        .padding(.horizontal, 36).padding(.top, 36).padding(.bottom, 28)
        .frame(width: 360)
        .background { LitGround().ignoresSafeArea() }
        .background(Tok.bg)
        .accessibilityElement(children: .contain)
    }
}

extension KeyboardShortcut {
    /// A menu item's keys from Shortcut's one table, which the palette and Keyboard Shortcuts read too.
    init?(_ s: Shortcut) {
        guard let c = s.chord else { return nil }
        let key: KeyEquivalent = switch c.key {
        case "delete": .delete
        case "return": .return
        case "escape": .escape
        default: KeyEquivalent(Character(c.key))
        }
        let pairs: [(Shortcut.Chord.Modifier, EventModifiers)] = [(.command, .command), (.shift, .shift), (.option, .option), (.control, .control)]
        self.init(key, modifiers: EventModifiers(pairs.filter { c.modifiers.contains($0.0) }.map(\.1)))
    }
}

/// Keyboard Shortcuts (⌘/): every shortcut, grouped Capture, Days, Canvas, Search and Windows, from Shortcut.all, the
/// table the menus and the palette take their keys from, so it can't drift from what Saro answers to.
struct ShortcutsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Keyboard shortcuts").font(Typo.serif(26, .medium)).foregroundStyle(Tok.ink)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 28, alignment: .top), GridItem(.flexible(), alignment: .top)],
                          alignment: .leading, spacing: 24) {
                    ForEach(Shortcut.Group.allCases, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(group.rawValue).monoCaps(10.5, tracking: 0.12).foregroundStyle(Tok.ink3).padding(.bottom, 8)
                            ForEach(Shortcut.all.filter { $0.group == group }) { s in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(s.title).font(Typo.ui(13)).foregroundStyle(Tok.ink)
                                    if let scope = s.scope {
                                        Text("in \(scope)").font(Typo.ui(11)).foregroundStyle(Tok.ink3)
                                    }
                                    Spacer(minLength: 12)
                                    Text(s.keys).font(Typo.mono(12)).foregroundStyle(Tok.sageDark)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Tok.surface.opacity(0.6), in: .rect(cornerRadius: 5))
                                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Tok.line))
                                }
                                .padding(.vertical, 6)
                                .accessibilityElement(children: .combine)
                                Rectangle().fill(Tok.line.opacity(0.6)).frame(height: 1)
                            }
                        }
                    }
                }
            }
            .padding(32)
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 480, idealHeight: 620)
        .background(Tok.paper.opacity(0.6))
        .background(.frosted(.regularMaterial, solid: Tok.paper))
        .onExitCommand { NSApp.keyWindow?.performClose(nil) }
    }
}
