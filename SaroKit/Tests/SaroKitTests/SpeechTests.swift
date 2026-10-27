import AVFoundation
import Foundation
import Speech
import Testing
@testable import SaroKit

func word(_ text: String, _ startMs: Int, _ durMs: Int = 300) -> TranscriptWord {
    TranscriptWord(text: text, startMs: startMs, durMs: durMs, confidence: 0.9)
}

@Test func sentencesSplitOnPunctuationAndGaps() {
    let words = [word("Hello", 0), word("there.", 300), word("Long", 700), word("pause", 1000),
                 word("then", 2600), word("more?", 2900), word("\"Done!\"", 3300), word("tail", 3700)]
    let sentences = Transcriber.sentences(from: words)
    #expect(sentences.map(\.text) == ["Hello there.", "Long pause", "then more?", "\"Done!\"", "tail"])
    #expect(sentences.map(\.startMs) == [0, 700, 2600, 3300, 3700])
    #expect(Transcriber.sentences(from: []).isEmpty)
}

/// Live only when the speech asset for the chosen locale is already on disk (no download in tests).
func installedSpeechLocale() async -> Locale? {
    guard let locale = await Transcriber.locale() else { return nil }
    return await SpeechTranscriber.installedLocales.contains { $0.identifier == locale.identifier } ? locale : nil
}

func tempAudioURL(_ ext: String) -> URL {
    FileManager.default.temporaryDirectory.appending(path: "saro-speech-\(UUID().uuidString).\(ext)")
}

@Test func liveTranscribesSyntheticSpeech() async throws {
    guard let locale = await installedSpeechLocale(), locale.language.languageCode == "en" else { return }
    let url = tempAudioURL("aiff")
    defer { try? FileManager.default.removeItem(at: url) }
    let say = Process()
    say.executableURL = URL(filePath: "/usr/bin/say")
    say.arguments = ["-o", url.path, "I walked to the market this morning. It was quiet and the sky was grey."]
    try say.run()
    say.waitUntilExit()

    let result = try await Transcriber.transcribe(url: url)
    print("live transcript:", result.text, result.meanConfidence ?? -1, result.extractorVersion)
    #expect(result.text.lowercased().contains("market"))
    #expect(result.words.count >= 8)
    #expect(zip(result.words, result.words.dropFirst()).allSatisfy { $0.startMs <= $1.startMs })
    #expect(result.extractorVersion == "speech-analyzer-1:\(result.locale)")
    #expect(Transcriber.sentences(from: result.words).count >= 2)
}

@Test func liveSilenceIsEmptyNotAnError() async throws {
    guard await installedSpeechLocale() != nil else { return }
    let url = tempAudioURL("caf")
    defer { try? FileManager.default.removeItem(at: url) }
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_000))
    buffer.frameLength = 32_000
    try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)

    let result = try await Transcriber.transcribe(url: url)
    #expect(result.words.isEmpty)
    #expect(result.meanConfidence == nil)
}
