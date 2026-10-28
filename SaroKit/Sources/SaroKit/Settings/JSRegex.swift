import Foundation

/// The web's regex calls (`test`, `match`, `replace`, `split`) over NSRegularExpression, which shares JavaScript's
/// ASCII `\b` and backtracking, so the ported parsers read text exactly as the web's do. Offsets are UTF-16, as in JS.
/// ponytail: compiles on every call; parsing runs on a keypress, so caching isn't worth the shared state.
extension String {
    /// The patterns are this module's own literals, so a bad one is a programmer error.
    private func regex(_ pattern: String, _ i: Bool) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: i ? [.caseInsensitive] : [])
    }

    private var whole: NSRange { NSRange(location: 0, length: utf16.count) }

    func jsTest(_ pattern: String, i: Bool = false) -> Bool {
        regex(pattern, i).firstMatch(in: self, range: whole) != nil
    }

    /// The first match's groups, `[0]` the whole match; nil for a group that didn't take part.
    func jsMatch(_ pattern: String, i: Bool = false) -> [String?]? {
        guard let m = regex(pattern, i).firstMatch(in: self, range: whole) else { return nil }
        return groups(m)
    }

    /// `replace` with a function: it gets the groups and the text before the match.
    func jsReplace(_ pattern: String, all: Bool = true, i: Bool = false, _ f: (_ groups: [String?], _ before: String) -> String) -> String {
        let ns = self as NSString
        let matches = regex(pattern, i).matches(in: self, range: whole)
        var out = ""
        var last = 0
        for m in all ? matches : Array(matches.prefix(1)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += f(groups(m), ns.substring(to: m.range.location))
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }

    /// `replace` with a template (`$1`).
    func jsReplace(_ pattern: String, all: Bool = true, i: Bool = false, with template: String) -> String {
        let re = regex(pattern, i)
        guard all else {
            guard let m = re.firstMatch(in: self, range: whole) else { return self }
            let ns = self as NSString
            return ns.substring(to: m.range.location) + re.replacementString(for: m, in: self, offset: 0, template: template)
                + ns.substring(from: m.range.location + m.range.length)
        }
        return re.stringByReplacingMatches(in: self, range: whole, withTemplate: template)
    }

    func jsSplit(_ pattern: String) -> [String] {
        let ns = self as NSString
        var out: [String] = []
        var last = 0
        for m in regex(pattern, false).matches(in: self, range: whole) {
            out.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        return out + [ns.substring(from: last)]
    }

    /// String.prototype.replace with a plain string: the first occurrence only.
    func jsReplaceFirst(_ needle: String, with replacement: String) -> String {
        guard let r = range(of: needle) else { return self }
        return replacingCharacters(in: r, with: replacement)
    }

    var jsTrim: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    private func groups(_ m: NSTextCheckingResult) -> [String?] {
        let ns = self as NSString
        return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? nil : ns.substring(with: m.range(at: $0)) }
    }
}
