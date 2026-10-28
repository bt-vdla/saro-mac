/// What Saro promises about privacy, word for word. Every claim is true of this build and its proof can be checked on
/// this Mac (PrivacyPromise.tsx, rewritten for a journal with no account and no server).
enum PrivacyCopy {
    /// NFR-02: the welcome screen and 'What this means', exactly. Any PCC or BYOK route changes these in the same release.
    static let nfr02 = [
        "Saro has no account, no server and no way online. This version is built without permission to use the internet.",
        "Saro reads your words with Apple Intelligence, here on this Mac. Saro never sends what you record or write to us, to Apple or to anyone else.",
        "Your journal is yours. Export it, or erase it, whenever you like.",
    ]

    struct Promise: Identifiable, Hashable {
        let id: String
        let title: String
        let body: [String]
        /// What keeps the promise, quoted so anyone can check.
        let proofs: [String]
        let `where`: String
    }

    // ponytail: 'then it's removed for good' joins `delete` with shell's 30-day purge, and an Erase line with settings' eraseAll.
    static let promises = [
        Promise(id: "private", title: "Your journal never leaves this Mac.",
                body: [
                    "Saro is built without the network entitlement, so macOS won’t let it connect to anything. There’s no account and no server.",
                    "Your entries, recordings and photos are files in Saro’s own container on this Mac, and Apple Intelligence reads them here, on device.",
                    "If you turn on Writing Tools, Apple may use Private Cloud Compute for the text you select. It’s off unless you choose it.",
                    "Backups you make of this Mac, like Time Machine, include your journal, as they include your other files.",
                ],
                proofs: ["com.apple.security.network.client: not in Saro’s entitlements", "codesign -d --entitlements - Saro.app"],
                where: "Settings → Your data."),
        Promise(id: "delete", title: "Delete anything, any time.",
                body: [
                    "A deleted entry goes to Trash, where you can restore it.",
                    "When Saro deletes something, its database overwrites it rather than leaving it in the file.",
                ],
                proofs: ["PRAGMA secure_delete=ON", "UPDATE entry SET trashed_at=…"],
                where: "Settings → Your data."),
        Promise(id: "export", title: "Take everything with you.",
                body: ["File → Export Everything… writes one folder: every row of your journal as JSON, with every recording and photo beside it."],
                proofs: ["File → Export Everything…", "Saro-<day>.saroexport/saro.json + Media/"],
                where: "Settings → Your data."),
    ]
}
