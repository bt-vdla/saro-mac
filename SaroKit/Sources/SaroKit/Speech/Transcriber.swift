import AVFoundation
import Foundation
import Speech

public struct TranscriptResult: Sendable, Hashable {
    public var words: [TranscriptWord]
    public var text: String
    public var meanConfidence: Double?
    public var locale: String
    public var extractorVersion: String
}

/// The caller shows "Transcript not ready" and keeps the recording.
public enum TranscriberError: Error, Sendable, Equatable {
    case notReady(reason: String)
}

/// The transcript of record for a saved recording (SpeechAnalyzer + SpeechTranscriber, on-device).
public enum Transcriber {
    public static func transcribe(url: URL) async throws -> TranscriptResult {
        guard let locale = await locale() else { throw TranscriberError.notReady(reason: "no supported locale") }
        let version = "speech-analyzer-1:\(locale.identifier)"
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [],
                                            attributeOptions: [.audioTimeRange, .transcriptionConfidence])
        try await installAssets(for: transcriber)

        let asset = AVURLAsset(url: url)
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
            return TranscriptResult(words: [], text: "", meanConfidence: nil, locale: locale.identifier, extractorVersion: version)
        }
        let results = transcriber.results
        let collector = Task {
            var words: [TranscriptWord] = []
            var text: [String] = []
            for try await result in results {
                words += Self.words(in: result.text)
                text.append(String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return (words, text.filter { !$0.isEmpty }.joined(separator: " "))
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        do {
            let provider = try await AssetInputSequenceProvider.provider(from: asset, compatibleWith: [transcriber])
            if try await analyzer.analyzeSequence(provider.analyzerInputs) != nil {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            await analyzer.cancelAndFinishNow()
            collector.cancel()
            throw error
        }
        let (words, text) = try await collector.value
        let confidences = words.compactMap(\.confidence)
        return TranscriptResult(words: words, text: text,
                                meanConfidence: confidences.isEmpty ? nil : confidences.reduce(0, +) / Double(confidences.count),
                                locale: locale.identifier, extractorVersion: version)
    }

    /// Groups words for tap-a-sentence-to-seek: a sentence ends after . ? ! or before a gap over 1.2 s.
    public static func sentences(from words: [TranscriptWord]) -> [(text: String, startMs: Int)] {
        var sentences: [(text: String, startMs: Int)] = []
        var current: [TranscriptWord] = []
        func flush() {
            if let first = current.first { sentences.append((current.map(\.text).joined(separator: " "), first.startMs)) }
            current = []
        }
        for word in words {
            if let last = current.last, word.startMs - (last.startMs + last.durMs) > 1200 { flush() }
            current.append(word)
            if let end = word.text.last(where: { !"\"'”’)".contains($0) }), ".?!".contains(end) { flush() }
        }
        flush()
        return sentences
    }

    /// `Locale.current` when the transcriber supports it, else en-US.
    static func locale() async -> Locale? {
        if let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) { return locale }
        return await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US"))
    }

    static func installAssets(for transcriber: SpeechTranscriber) async throws {
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed: return
        case .unsupported: throw TranscriberError.notReady(reason: "speech model unsupported")
        default:
            do {
                try await AssetInventory.assetInstallationRequest(supporting: [transcriber])?.downloadAndInstall()
            } catch {
                throw TranscriberError.notReady(reason: "speech model install failed")
            }
        }
    }

    /// One word per attributed run that carries an audio time range.
    static func words(in text: AttributedString) -> [TranscriptWord] {
        text.runs.compactMap { run in
            guard let range = run.audioTimeRange else { return nil }
            let word = String(text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { return nil }
            return TranscriptWord(text: word, startMs: Int((range.start.seconds * 1000).rounded()),
                                  durMs: Int((range.duration.seconds * 1000).rounded()), confidence: run.transcriptionConfidence)
        }
    }
}
