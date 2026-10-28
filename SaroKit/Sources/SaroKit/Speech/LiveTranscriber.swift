import AVFoundation
import CoreGraphics
import Foundation
import Speech

/// A word on screen while recording. Never stored or quoted (FR-CAP-05): the file transcript is the one of record.
public struct LiveWord: Sendable, Hashable {
    public var text: String
    /// Settled; a volatile word may still be revised.
    public var final: Bool

    public init(text: String, final: Bool) {
        self.text = text
        self.final = final
    }
}

/// Live captions (FR-CAP-05): SpeechAnalyzer's volatile results over the capture session's own audio buffers, on this
/// Mac, in the caption language (B-12). `append` is called on the capture queue; everything else from anywhere.
public final class LiveTranscriber: @unchecked Sendable {
    private let lock = NSLock()
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzer: SpeechAnalyzer?
    private var format: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var feeding = true

    public init() {}

    /// Starts listening; the stream yields every word so far (settled, then volatile) on each result, and ends at `stop`.
    /// Throws when no caption language is supported or its speech model can't be installed.
    public func start(locale preferred: String? = nil) async throws -> AsyncStream<[LiveWord]> {
        guard let locale = await Transcriber.locale(preferred: preferred ?? Transcriber.preferredLocale.withLock { $0 })
        else { throw TranscriberError.notReady(reason: "no supported locale") }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
        try await Transcriber.installAssets(for: transcriber)
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        let (inputs, input) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.start(inputSequence: inputs)
        lock.withLock { (self.input, self.analyzer, self.format, self.converter) = (input, analyzer, format, nil) }
        let results = transcriber.results
        return AsyncStream { out in
            let task = Task {
                var settled: [String] = []
                do {
                    for try await r in results {
                        let words = Self.split(String(r.text.characters))
                        if r.isFinal { settled += words }
                        out.yield(settled.map { LiveWord(text: $0, final: true) } + (r.isFinal ? [] : words.map { LiveWord(text: $0, final: false) }))
                    }
                } catch {}
                out.finish()
            }
            out.onTermination = { _ in task.cancel() }
        }
    }

    /// Paused, buffers are dropped: nothing said while paused is heard (FR-CAP-05).
    public func setFeeding(_ on: Bool) { lock.withLock { feeding = on } }

    /// A capture buffer, converted to the analyzer's format.
    public func append(_ sample: CMSampleBuffer) {
        guard let desc = CMSampleBufferGetFormatDescription(sample) else { return }
        let source = AVAudioFormat(cmAudioFormatDescription: desc)
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
        guard frames > 0, let pcm = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: frames) else { return }
        pcm.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList) == noErr
        else { return }
        append(pcm)
    }

    public func append(_ pcm: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard feeding, let input else { return }
        guard let format, pcm.format != format else { input.yield(AnalyzerInput(buffer: pcm)); return }
        if converter?.inputFormat != pcm.format { converter = AVAudioConverter(from: pcm.format, to: format) }
        guard let converter else { return }
        let capacity = AVAudioFrameCount((Double(pcm.frameLength) * format.sampleRate / pcm.format.sampleRate).rounded(.up)) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
        var given = false
        let status = converter.convert(to: out, error: nil) { _, state in
            if given { state.pointee = .noDataNow; return nil }
            given = true
            state.pointee = .haveData
            return pcm
        }
        if status != .error, out.frameLength > 0 { input.yield(AnalyzerInput(buffer: out)) }
    }

    /// Ends the input; the stream finishes once the last words settle.
    public func stop() async {
        let (input, analyzer) = lock.withLock {
            defer { (self.input, self.analyzer, self.converter) = (nil, nil, nil) }
            return (self.input, self.analyzer)
        }
        input?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
    }

    static func split(_ text: String) -> [String] { text.split(whereSeparator: \.isWhitespace).map(String.init) }
}

/// Live caption lines that never re-wrap (VideoReflectionScreen.tsx): a word keeps the line it first landed on, and a
/// new word starts a line only when it doesn't fit on the last. A revised volatile word stays where it was.
public struct CaptionLines: Sendable, Hashable {
    /// The index of each line's first word.
    public private(set) var starts: [Int] = [0]
    public private(set) var count = 0

    public init() {}

    public mutating func update(_ words: [String], maxWidth: CGFloat, width: (String) -> CGFloat) {
        if words.count < count {
            starts.removeAll { $0 >= words.count && $0 > 0 }
            if starts.isEmpty { starts = [0] }
        }
        count = words.count
        // Re-flow only the last line, so the lines above stay as they were read.
        let last = starts.removeLast()
        var line = last
        starts.append(last)
        var used: CGFloat = 0
        for i in line..<words.count {
            let w = width(words[i]) + (i == line ? 0 : width(" "))
            if i > line, used + w > maxWidth {
                starts.append(i)
                line = i
                used = width(words[i])
            } else {
                used += w
            }
        }
    }

    /// Word ranges of the lines, oldest first.
    public var lines: [Range<Int>] {
        guard count > 0 else { return [] }
        return starts.indices.map { i in starts[i]..<(i + 1 < starts.count ? starts[i + 1] : count) }.filter { !$0.isEmpty }
    }

    /// Back to no words, for the next part.
    public mutating func reset() { (starts, count) = ([0], 0) }
}
