import Foundation
import FoundationModels
import Speech

/// Whether Apple Intelligence and the speech model can run on this Mac, each with one honest line (FR-ONB-05).
/// Saro works either way: without the model it reflects the person's own words back, labelled In your words.
public enum Readiness {
    public enum ModelState: Sendable, Hashable {
        case ready, deviceNotEligible, notEnabled, notReady

        init(_ availability: SystemLanguageModel.Availability) {
            switch availability {
            case .available: self = .ready
            case .unavailable(.deviceNotEligible): self = .deviceNotEligible
            case .unavailable(.appleIntelligenceNotEnabled): self = .notEnabled
            case .unavailable: self = .notReady
            }
        }

        public var isReady: Bool { self == .ready }

        public var line: String {
            switch self {
            case .ready: "Apple Intelligence is on. Saro reads your words with it, here on this Mac."
            case .deviceNotEligible: "This Mac can’t run Apple Intelligence. Saro still works, and reflects your own words back, labelled In your words."
            case .notEnabled: "Apple Intelligence is off on this Mac, turned off by you or by whoever manages this Mac. Until it’s on, Saro reflects your own words back, labelled In your words."
            case .notReady: "Apple Intelligence is still getting ready on this Mac. Saro reflects your own words back for now, and reads your entries once it’s ready."
            }
        }

        /// Apple Intelligence & Siri in System Settings, for the one state the person can change there.
        public var settingsURL: URL? {
            self == .notEnabled ? URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") : nil
        }
    }

    public static func model() -> ModelState { ModelState(SystemLanguageModel.default.availability) }

    public enum SpeechState: Sendable, Hashable {
        case installed
        /// A fraction from 0 to 1 while Saro is watching the download, else nil.
        case downloading(Double?)
        case needsDownload
        case failed
        case unsupported

        init(_ status: AssetInventory.Status) {
            switch status {
            case .installed: self = .installed
            case .downloading: self = .downloading(nil)
            case .supported: self = .needsDownload
            default: self = .unsupported
            }
        }

        public var line: String {
            switch self {
            case .installed: "Speech is ready. Recordings are transcribed here on this Mac."
            case .downloading(let f):
                "macOS is downloading speech for this Mac\(f.map { " (\(Int(($0 * 100).rounded()))%)" } ?? ""). Recordings made meanwhile are kept and transcribed once it’s done."
            case .needsDownload: "Speech needs a one-time download, which macOS fetches for Saro. Recordings are kept until it’s done."
            case .failed: "The speech download didn’t finish. Saro tries again the next time you record, and keeps your recordings meanwhile."
            case .unsupported: "Speech isn’t available for this language on this Mac. Recordings are kept, without a transcript."
            }
        }
    }

    /// Speech for `locale`, or, with none, for the language Saro transcribes in (Transcriber.locale()).
    public static func speech(locale: Locale? = nil) async -> SpeechState {
        guard let module = await module(locale) else { return .unsupported }
        return SpeechState(await AssetInventory.status(forModules: [module]))
    }

    /// Downloads the speech model if it isn't installed, reporting progress from 0 to 1. Never blocks capture: a recording
    /// made meanwhile is kept and transcribed later.
    public static func downloadSpeech(locale: Locale? = nil, progress: @escaping @Sendable (Double) -> Void = { _ in }) async -> SpeechState {
        guard let module = await module(locale) else { return .unsupported }
        do {
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else { return .installed }
            // ponytail: polls the fraction every 250 ms; observe the Progress if a smoother bar matters.
            let watch = Task {
                while !Task.isCancelled {
                    progress(request.progress.fractionCompleted)
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            defer { watch.cancel() }
            try await request.downloadAndInstall()
            progress(1)
            return .installed
        } catch {
            return .failed
        }
    }

    /// The transcriber Saro would run, as Transcriber builds it, so its assets are the ones checked.
    private static func module(_ locale: Locale?) async -> SpeechTranscriber? {
        let resolved: Locale?
        if let locale { resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale) } else { resolved = await Transcriber.locale() }
        guard let resolved else { return nil }
        return SpeechTranscriber(locale: resolved, transcriptionOptions: [], reportingOptions: [],
                                 attributeOptions: [.audioTimeRange, .transcriptionConfidence])
    }
}
