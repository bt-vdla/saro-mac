import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import SaroKit

// MARK: Music (music.test.ts)

private func pick(_ s: String) -> (MusicInfo.Source, String, String, String) {
    let i = Music.resolve(URL(string: s)!)
    return (i.source, i.title, i.artist, i.album)
}

@Test func spotifyHasNoSlugSoItGetsAKindLabel() {
    #expect(pick("https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC?si=abc") == (.spotify, "Track on Spotify", "", ""))
    #expect(pick("https://open.spotify.com/intl-de/album/1DFixLWuPkv3KT3TnV35m3").1 == "Album on Spotify")
    #expect(pick("https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M").1 == "Playlist on Spotify")
    #expect(pick("https://spotify.link/aBcD123").1 == "Music on Spotify")
}

@Test func appleMusicTitlesComeFromTheSlug() {
    #expect(pick("https://music.apple.com/us/album/blinding-lights/1499378108?i=1499378615") == (.apple, "Blinding Lights", "", ""))
    let album = pick("https://music.apple.com/gb/album/a-night-at-the-opera/1440650428")
    #expect(album.1 == "A Night at the Opera" && album.3 == "A Night at the Opera")
    #expect(pick("https://music.apple.com/us/song/shape-of-you/1193701392").1 == "Shape of You")
    #expect(pick("https://music.apple.com/us/playlist/todays-hits/pl.f4d106fed2bd41149aaacabb233eb5eb").1 == "Todays Hits")
    #expect(pick("https://music.apple.com/us/artist/the-weeknd/479756766").2 == "The Weeknd")
}

@Test func youTubeAndYouTubeMusic() {
    #expect(pick("https://www.youtube.com/watch?v=dQw4w9WgXcQ") == (.youtube, "Video on YouTube", "", ""))
    #expect(pick("https://youtu.be/dQw4w9WgXcQ?si=x").0 == .youtube)
    #expect(pick("https://m.youtube.com/shorts/abc123").1 == "Video on YouTube")
    #expect(pick("https://www.youtube.com/playlist?list=PL123").1 == "Playlist on YouTube")
    #expect(pick("https://music.youtube.com/watch?v=abc&list=RD1") == (.ytmusic, "Track on YouTube Music", "", ""))
    #expect(pick("https://music.youtube.com/playlist?list=OLAK5uy").1 == "Playlist on YouTube Music")
}

@Test func jioSaavnSongsAlbumsArtistsAndUserPlaylists() {
    #expect(pick("https://www.jiosaavn.com/song/kesariya/OgsgbhJZYWY") == (.jiosaavn, "Kesariya", "", ""))
    #expect(pick("https://www.jiosaavn.com/song/tum-hi-ho/EToxUyFpcwQ").1 == "Tum Hi Ho")
    #expect(pick("https://www.jiosaavn.com/album/brahmastra/xyz123").3 == "Brahmastra")
    #expect(pick("https://www.jiosaavn.com/artist/arijit-singh-songs/LlRWpHzy3Hk_").2 == "Arijit Singh")
    #expect(pick("https://www.jiosaavn.com/s/playlist/2279d8e1a6c1b7c7a5a57cd8db0d9a96/late_night_drive/abc").1 == "Late Night Drive")
}

@Test func soundCloudAndTidal() {
    let sc = pick("https://soundcloud.com/some-artist/midnight-city-remix")
    #expect(sc.1 == "Midnight City Remix" && sc.2 == "Some Artist")
    #expect(pick("https://tidal.com/browse/track/12345").1 == "Track on Tidal")
}

@Test func unknownAndLookalikeHostsAndBadInput() {
    #expect(pick("https://example.com/song/whatever") == (.unknown, "Music link", "", ""))
    #expect(pick("https://notspotify.com/track/1").0 == .unknown)
    #expect(Music.link("not a url") == nil)
    #expect(Music.link("") == nil)
    #expect(Music.link("ftp://open.spotify.com/track/1") == nil)
    #expect(Music.link(" https://open.spotify.com/track/1 \n") != nil)
}

@Test func pasteRecognisesOnlyTheWebsServices() {
    for s in ["https://open.spotify.com/track/1", "https://music.apple.com/us/song/x/1", "https://youtu.be/x", "https://soundcloud.com/a/b",
              "https://www.jiosaavn.com/song/x/1", "https://music.youtube.com/watch?v=1"] {
        #expect(Music.isMusicLink(s), "\(s)")
    }
    for s in ["https://tidal.com/browse/track/1", "https://example.com/x", "Listened to https://open.spotify.com/track/1 today", "hello"] {
        #expect(!Music.isMusicLink(s), "\(s)")
    }
}

@Test func artworkIsStablePerLinkAndOffline() {
    let a = URL(string: "https://open.spotify.com/track/1")!, b = URL(string: "https://open.spotify.com/track/2")!
    #expect(Music.artwork(a) == Music.artwork(a))
    #expect(Music.artwork(a).top != Music.artwork(b).top)
    #expect(Music.artwork(a).bottom == 0x1DB954)
    #expect(Music.artworkSeed(URL(string: "https://youtu.be/x?si=1")!) == "youtube:/x?si=1")
    #expect(Music.hash("abc") == 440_920_331) // db.ts hashString("abc")
    #expect(Music.hsl(0, 1, 0.5) == 0xFF0000)
}

@Test func humanizeSlugDecodesAndTitleCases() {
    #expect(Music.humanizeSlug("caf%C3%A9-del-mar") == "Café Del Mar")
    #expect(Music.humanizeSlug("the_sound_of_silence") == "The Sound of Silence")
    #expect(Music.humanizeSlug("bad%E0escape") == "Bad%E0escape")
}

// MARK: Follow-ups (ai.ts followUp, observations)

@Test func followUpQuotesTheirOwnPhraseByTheme() throws {
    let text = "The deadline at work keeps moving and my manager wants the launch by Friday."
    let q = FollowUps.followUp(text, verb: "said", exclude: [], seed: 0)
    let phrase = try #require(Heuristics.extractPhrase(text, focus: Heuristics.analyzeText(text).focus))
    #expect(q.contains("“\(phrase)”"))
    #expect(text.contains(phrase))
    #expect(FollowUps.templates[.work]!.map { $0.replacingOccurrences(of: "{p}", with: phrase).replacingOccurrences(of: "{verb}", with: "said") }.contains(q))
    #expect(FollowUps.followUp(text, verb: "said", exclude: [], seed: 0) == q)
}

@Test func followUpNeverRepeatsAnEarlierQuestion() {
    let text = "Walked by the river after work and the sky was pink."
    var asked: [String] = []
    for _ in 0..<6 { asked.append(FollowUps.followUp(text, verb: "said", exclude: asked, seed: 7)) }
    #expect(Set(asked.prefix(4)).count == 4)
}

@Test func followUpWithoutAPhraseAsksAnOpenQuestion() {
    #expect(FollowUps.phraseless.contains(FollowUps.followUp("", verb: "said", exclude: [], seed: 3)))
    #expect(FollowUps.phraseless.contains(FollowUps.followUp("um", verb: "said", exclude: [], seed: 3)))
}

@Test func writtenFollowUpSaysWrote() {
    let q = FollowUps.followUp("I keep thinking about the painting I started.", verb: "wrote", exclude: [], seed: 0)
    #expect(!q.contains("{"))
    #expect(!q.contains("You said"))
}

@Test func observationsOnlyStateWhatWasSaid() {
    let lines = FollowUps.observations("Work was long. More work after dinner, then Maya called and I felt calm, not anxious.")
    #expect(lines.first == "You came back to work twice there.")
    #expect(lines.contains("You mentioned Maya."))
    #expect(lines.contains("You used the word “calm”."))
    #expect(lines.last == "That was 16 words.")
    #expect(FollowUps.observations("tired") == ["You touched on sleep.", "That was 1 word."])
    #expect(FollowUps.observations("Not anxious at all") == ["That was 4 words."])
}

@Test func twinSkipsObservationsAlreadyShown() {
    let text = "Maya and Ravi came over. Work was fine."
    let all = FollowUps.observations(text)
    let f = FollowUps.twin(text, verb: "said", exclude: [], excludeObservations: Array(all.dropLast()), seed: 1)
    #expect(f.observation == all.last)
    #expect(FollowUps.twin(text, verb: "said", exclude: [], excludeObservations: all, seed: 1).observation == nil)
    #expect(f.generator == "heuristic")
}

// MARK: SaroAI.followUp on the ladder

private let partText = "Long day at work. Shipped the onboarding flow. Had chai with Ravi and talked about his move to Pune."

@Test func modelFollowUpPassesTheDriftCheckAndLogsAContentFreeRun() async {
    let ai = SaroAI(stub: { _ in #"{"observation": "You talked about Ravi.", "question": "What did the chai with Ravi give you?"}"# })
    let (f, run) = await ai.followUp(text: partText, verb: "said", exclude: [], seed: 1, localDay: "2026-10-28")
    #expect(f.question == "What did the chai with Ravi give you?")
    #expect(f.observation == "You talked about Ravi.")
    #expect(f.generator == "on_device")
    #expect(f.runId == run.id)
    #expect(run.feature == "reflect_deeper" && run.ladderRung == Rung.permissiveJSON.rawValue && run.status == "ok")
    #expect(run.inputHash == nil && run.localDay == "2026-10-28")
}

@Test func inventedNounsFallToTheTwin() async {
    let ai = SaroAI(stub: { _ in #"{"observation": null, "question": "How is your sister Priya in London?"}"# })
    let (f, run) = await ai.followUp(text: partText, verb: "said", exclude: [], seed: 1, localDay: nil)
    #expect(f.generator == "heuristic")
    #expect(f == FollowUps.twin(partText, verb: "said", exclude: [], excludeObservations: [], seed: 1).with(runId: run.id))
    #expect(run.executor == "heuristic" && run.modelCalls == 4)
}

@Test func anEarlierQuestionIsNeverAskedAgain() async {
    let asked = "What did the chai with Ravi give you?"
    let ai = SaroAI(stub: { _ in #"{"observation": null, "question": "What did the chai with Ravi give you?"}"# })
    let (f, _) = await ai.followUp(text: partText, verb: "said", exclude: [asked], seed: 1, localDay: nil)
    #expect(f.question != asked)
}

@Test func aSlowModelLosesTheRaceToTheTwin() async {
    let ai = SaroAI(stub: { _ in
        try await Task.sleep(for: .seconds(5))
        return #"{"observation": null, "question": "What did the chai with Ravi give you?"}"#
    })
    let start = ContinuousClock.now
    let (f, run) = await ai.followUp(text: partText, verb: "said", exclude: [], seed: 1, localDay: nil, budget: .milliseconds(200))
    #expect(ContinuousClock.now - start < .seconds(2))
    #expect(f.generator == "heuristic" && run.status == "timeout")
}

@Test func anOutputGateHitFallsToTheTwin() async {
    let ai = SaroAI(stub: { _ in #"{"observation": null, "question": "Is there no point anymore, now that you want to die?"}"# })
    let (f, run) = await ai.followUp(text: partText, verb: "wrote", exclude: [], seed: 1, localDay: nil)
    #expect(run.status == "output_gate" && run.feature == "reflect_further")
    #expect(f.generator == "heuristic")
    #expect(!SafetyGate.phraseHit(f.question))
}

@Test func withoutTheModelTheTwinAnswersAtOnce() async {
    let ai = SaroAI(stub: { _ in "" }, status: .unavailable(reason: "off"))
    let (f, run) = await ai.followUp(text: partText, verb: "said", exclude: [], seed: 2, localDay: nil)
    #expect(f.generator == "heuristic" && run.modelCalls == 0 && run.status == "unavailable")
}

@Test(.liveModel) func liveFollowUpIsGrounded() async {
    let ai = SaroAI()
    guard ai.status == .available else { return }
    let (f, run) = await ai.followUp(text: partText, verb: "said", exclude: [], seed: 1, localDay: nil, budget: .seconds(20))
    print("live follow-up:", f.observation ?? "-", f.question, run.ladderRung ?? "", run.latencyMs ?? 0)
    #expect(f.question.hasSuffix("?"))
}

extension FollowUp {
    func with(runId: String) -> FollowUp {
        var f = self
        f.runId = runId
        return f
    }
}

// MARK: Live caption lines

@Test func captionWordsKeepTheirLine() {
    var lines = CaptionLines()
    let width: (String) -> CGFloat = { CGFloat($0.count) }
    lines.update(["one", "two", "three"], maxWidth: 9, width: width)
    #expect(lines.lines == [0..<2, 2..<3])
    // "two" revised longer: it stays on the first line, which isn't re-flowed.
    lines.update(["one", "twoooo", "three", "four"], maxWidth: 9, width: width)
    #expect(lines.lines == [0..<2, 2..<3, 3..<4])
    lines.update(["one", "twoooo", "three"], maxWidth: 9, width: width)
    #expect(lines.lines == [0..<2, 2..<3])
    lines.reset()
    #expect(lines.lines.isEmpty)
}

@Test func liveTranscriberHearsSyntheticSpeech() async throws {
    guard let locale = await installedSpeechLocale(), locale.language.languageCode == "en" else { return }
    let url = tempAudioURL("aiff")
    defer { try? FileManager.default.removeItem(at: url) }
    let say = Process()
    say.executableURL = URL(filePath: "/usr/bin/say")
    say.arguments = ["-o", url.path, "I walked to the market this morning and the sky was grey."]
    try say.run()
    say.waitUntilExit()

    let live = LiveTranscriber()
    let words = try await live.start(locale: locale.identifier)
    let collector = Task {
        var last: [LiveWord] = []
        for await w in words { last = w }
        return last
    }
    let file = try AVAudioFile(forReading: url)
    while file.framePosition < file.length {
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096))
        try file.read(into: buffer)
        live.append(buffer)
    }
    await live.stop()
    let heard = await collector.value
    print("live words:", heard.map(\.text).joined(separator: " "))
    #expect(heard.map(\.text).joined(separator: " ").lowercased().contains("market"))
    #expect(heard.allSatisfy { $0.final })
}

/// A capture-queue audio buffer: the PCM in a CMSampleBuffer, as AVCaptureAudioDataOutput delivers it.
private func sampleBuffer(_ pcm: AVAudioPCMBuffer, at frame: Int64) throws -> CMSampleBuffer {
    let rate = CMTimeScale(pcm.format.sampleRate)
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: rate), presentationTimeStamp: CMTime(value: frame, timescale: rate),
                                    decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    try #require(CMSampleBufferCreate(allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil,
                                      formatDescription: pcm.format.formatDescription, sampleCount: CMItemCount(pcm.frameLength),
                                      sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil,
                                      sampleBufferOut: &sample) == noErr)
    let s = try #require(sample)
    try #require(CMSampleBufferSetDataBufferFromAudioBufferList(s, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0,
                                                                 bufferList: pcm.audioBufferList) == noErr)
    return s
}

/// The capture queue hands the transcriber CMSampleBuffers, not PCM buffers: 16-bit interleaved here, at 48 kHz, so the
/// conversion to the analyzer's format runs too.
@Test func liveTranscriberHearsCaptureSampleBuffers() async throws {
    let url = tempAudioURL("aiff")
    defer { try? FileManager.default.removeItem(at: url) }
    let say = Process()
    say.executableURL = URL(filePath: "/usr/bin/say")
    say.arguments = ["-o", url.path, "I walked to the market this morning and the sky was grey."]
    try say.run()
    say.waitUntilExit()
    let file = try AVAudioFile(forReading: url)
    let mic = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 1, interleaved: true))
    let converter = try #require(AVAudioConverter(from: file.processingFormat, to: mic))
    var samples: [CMSampleBuffer] = []
    var frame: Int64 = 0
    while file.framePosition < file.length {
        let chunk = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1024))
        try file.read(into: chunk)
        let out = try #require(AVAudioPCMBuffer(pcmFormat: mic, frameCapacity: 1024 * 48000 / AVAudioFrameCount(file.processingFormat.sampleRate) + 16))
        var given = false
        _ = converter.convert(to: out, error: nil) { _, state in
            if given { state.pointee = .noDataNow; return nil }
            given = true
            state.pointee = .haveData
            return chunk
        }
        guard out.frameLength > 0 else { continue }
        samples.append(try sampleBuffer(out, at: frame))
        frame += Int64(out.frameLength)
    }
    #expect(!samples.isEmpty)
    for s in samples {
        let pcm = try #require(LiveTranscriber.pcm(s))
        #expect(Int(pcm.frameLength) == CMSampleBufferGetNumSamples(s))
        #expect(pcm.format.sampleRate == 48000 && pcm.format.channelCount == 1 && pcm.format.commonFormat == .pcmFormatInt16)
    }

    guard let locale = await installedSpeechLocale(), locale.language.languageCode == "en" else { return }
    let live = LiveTranscriber()
    let words = try await live.start(locale: locale.identifier)
    let collector = Task {
        var last: [LiveWord] = []
        for await w in words { last = w }
        return last
    }
    for s in samples { live.append(s) }
    await live.stop()
    let heard = await collector.value.map(\.text).joined(separator: " ").lowercased()
    #expect(heard.contains("market"), "\(heard)")
}

// MARK: Discarding a take

@Test func discardTakeLeavesNothingOfTheTakeAndKeepsTheRest() async throws {
    let l = try tempLedger()
    let kept = Entry(kind: .moment, sessionId: "s", turnNumber: 1)
    var take = Entry(kind: .moment, sessionId: "s", turnNumber: 2)
    let asset = MediaAsset(fileName: "2026-10-28/s/part-2.mov", kind: .video, origin: "recorded", state: "ready")
    take.mediaId = asset.id
    let file = l.url(for: asset)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("x".utf8).write(to: file)
    let poster = l.mediaURL.appending(path: "2026-10-28/\(asset.id).poster.jpg")
    try Data("p".utf8).write(to: poster)
    try await l.insertEntry(kept)
    try await l.insertMedia(asset)
    try await l.setPoster(mediaId: asset.id, file: "2026-10-28/\(asset.id).poster.jpg")
    try await l.insertEntry(take)
    try await l.setTranscript(mediaId: asset.id, words: [TranscriptWord(text: "hi", startMs: 0, durMs: 100, confidence: 1)], extractorVersion: "t")
    try await l.insertVerdict(SafetyVerdictRow(entryId: take.id, textSha256: "h", safetyVersion: SafetyGate.version, layer: 2, verdict: "clear",
                                               reasonCode: "clear"))
    try await l.setLayouts([CardLayout(entryId: take.id, x: 0, y: 0, z: 1, stackId: "s")])
    try await l.insertTurn(ReflectionTurn(kind: .prompt, question: "What stands out?", generator: "curated", entryId: take.id, sessionId: "s", turnNumber: 2))
    var run = AIRun(feature: "entry_reading", executor: "heuristic", status: "ok")
    run.localDay = take.localDay
    try await l.insertRun(run, inputs: [AIRunInput(entryId: take.id, field: "transcript", text: "hi")])
    try await l.insertAnnotation(EntryAnnotation(entryId: take.id, aiRunId: run.id, generator: "heuristic"))

    try await l.discardTake(entryIds: [take.id])
    #expect(try await l.entry(take.id) == nil)
    #expect(try await l.media(asset.id) == nil)
    #expect(try await l.transcript(mediaId: asset.id).isEmpty)
    #expect(try await l.turns(entryId: take.id).isEmpty)
    #expect(try await l.verdicts(day: take.localDay)[take.id] == nil)
    #expect(!FileManager.default.fileExists(atPath: file.path))
    #expect(!FileManager.default.fileExists(atPath: poster.path))
    #expect(try await l.entry(kept.id) != nil)
}

// MARK: Import

@Test func importKindsAndTheDropGrid() {
    #expect(Import.kind(of: .jpeg) == .still && Import.kind(of: .mpeg4Audio) == .voice && Import.kind(of: .quickTimeMovie) == .moment)
    #expect(Import.kind(of: .pdf) == nil)
    #expect(Import.kind(of: URL(filePath: "/tmp/a.m4a")) == .voice)
    #expect(Import.grid(count: 1, around: CGPoint(x: 10, y: 20)) == [CGPoint(x: 10, y: 20)])
    let four = Import.grid(count: 4, around: .zero)
    #expect(four == [CGPoint(x: -222, y: -162), CGPoint(x: 222, y: -162), CGPoint(x: -222, y: 162), CGPoint(x: 222, y: 162)])
    #expect(Import.grid(count: 5, around: .zero).count == 5)
}

// MARK: A hold takes the follow-ups asked from it

@Test func aHeldEntryTakesItsFollowUpsWithIt() async throws {
    let l = try tempLedger()
    let source = Entry(kind: .reflection, body: "Walked by the river.")
    let next = Entry(kind: .moment, sessionId: "s", turnNumber: 2)
    try await l.insertEntry(source)
    try await l.insertEntry(next)
    let run = AIRun(feature: "reflect_further", executor: "heuristic", status: "ok")
    try await l.insertRun(run, inputs: [AIRunInput(entryId: source.id, field: "body", text: source.body ?? "")])
    let asked = ReflectionTurn(kind: .prompt, question: "What did the river give you?", generator: "heuristic", entryId: next.id, aiRunId: run.id)
    let answered = ReflectionTurn(kind: .reflectFurther, question: "What else is true?", generator: "heuristic", entryId: source.id, aiRunId: run.id)
    try await l.insertTurn(asked)
    try await l.insertTurn(answered)
    try await l.setTurnAnswer(id: answered.id, answer: "The quiet.", verdict: "clear")

    try await l.dropFollowUps(heldFrom: source.id)
    #expect(try await l.turns(entryId: next.id).count == 1, "nothing held yet")

    try await l.insertVerdict(SafetyVerdictRow(entryId: source.id, textSha256: "h", safetyVersion: SafetyGate.version, layer: 1,
                                               verdict: "safety_hold", reasonCode: "phrase_hit"))
    try await l.dropFollowUps(heldFrom: source.id)
    #expect(try await l.turns(entryId: next.id).isEmpty)
    let kept = try await l.turns(entryId: source.id)
    #expect(kept.map(\.question) == [""] && kept.map(\.answer) == ["The quiet."])
}

// MARK: Edited is an edit, not a re-check

@Test func editedIsOnlyAChangeOfWords() async throws {
    let l = try tempLedger()
    let page = Entry(kind: .reflection, body: "Walked by the river.")
    try await l.insertEntry(page)
    let check = { (hash: String) in
        SafetyVerdictRow(entryId: page.id, textSha256: hash, safetyVersion: SafetyGate.version, layer: 2, verdict: "clear", reasonCode: "clear")
    }
    #expect(try await l.editedAt(entryId: page.id) == nil)
    try await l.insertVerdict(check("a"))
    try await l.insertVerdict(check("a"))
    #expect(try await l.editedAt(entryId: page.id) == nil, "a re-check of the same words")
    try await l.insertVerdict(check("b"))
    #expect(try await l.editedAt(entryId: page.id) != nil)
}

// MARK: A song is gated by its own words, never read

@Test func aSongIsNeverGatedOrRead() async throws {
    let l = try tempLedger()
    let song = Entry(kind: .music, body: "https://soundcloud.com/some-artist/midnight-city-remix", processingStatus: ProcessingStatus.done)
    try await l.insertEntry(song)
    let p = Pipeline(ledger: l, ai: SaroAI(stub: { _ in "NONE" }))
    await p.process(entryId: song.id) {}
    #expect(try await l.verdicts(day: song.localDay)[song.id] == nil)
    #expect(try await l.annotations(day: song.localDay)[song.id] == nil)
    #expect(await p.dayStatus(song.localDay) == .empty)
}

@Test func aSongsTitleAndArtistAreGatedAndTheDayKeepsReading() async throws {
    let l = try tempLedger()
    let page = Entry(kind: .reflection, body: "Walked home the long way by the river after work.")
    let song = Entry(kind: .music, body: "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC", localDay: page.localDay,
                     processingStatus: ProcessingStatus.done)
    try await l.insertEntry(page)
    try await l.insertEntry(song)
    let p = Pipeline(ledger: l, ai: SaroAI(stub: { _ in "NONE" }))
    await p.process(entryId: page.id) {}
    await p.process(entryId: song.id) {}
    #expect(await p.dayStatus(page.localDay) == .ready)
    #expect(await p.narrativeEntries(page.localDay).contains { $0.kind == .music && $0.label == nil })

    // Edit details: a title and an artist are the person's words, gated and never read; the link stays as it was.
    try await l.updateEntryText(id: song.id, body: song.body, titleUser: "Midnight Walk", captionUser: "Some Artist")
    #expect(try await l.entry(song.id)?.processingStatus == ProcessingStatus.pending)
    await p.process(entryId: song.id) {}
    #expect(try await l.entry(song.id)?.processingStatus == ProcessingStatus.done)
    #expect(try await l.verdicts(day: page.localDay)[song.id]?.verdict == "clear")
    #expect(try await l.annotations(day: page.localDay)[song.id] == nil)
    #expect(await p.dayStatus(page.localDay) == .ready)
    let told = try #require(await p.narrativeEntries(page.localDay).first { $0.kind == .music })
    #expect(DayNarrative.lastInferred(told).message == "You added \"Midnight Walk\".")

    // A held title holds the day, like any of the person's words.
    try await l.updateEntryText(id: song.id, body: song.body, titleUser: "No point anymore", captionUser: "Some Artist")
    await p.process(entryId: song.id) {}
    #expect(await p.dayStatus(page.localDay) == .held)

    // A titled song alone is nothing to read.
    let alone = Entry(kind: .music, titleUser: "Midnight Walk", body: song.body, localDay: LocalDay.adding(-1, to: page.localDay))
    try await l.insertEntry(alone)
    await p.process(entryId: alone.id) {}
    #expect(try await l.verdicts(day: alone.localDay)[alone.id]?.verdict == "clear")
    #expect(await p.dayStatus(alone.localDay) == .empty)

    // Cleared again, nothing is left to gate or hold.
    try await l.updateEntryText(id: song.id, body: song.body, titleUser: nil, captionUser: nil)
    #expect(try await l.entry(song.id)?.processingStatus == ProcessingStatus.done)
    #expect(await p.dayStatus(page.localDay) == .ready)
}

// MARK: A checkpoint's question is kept without the live words it quoted

@Test func checkpointQuestionsAreKeptWithoutTheirQuote() {
    let phrase = "the long walk home"
    let all = FollowUps.templates.values.flatMap { $0 }.map { $0.replacingOccurrences(of: "{p}", with: phrase).replacingOccurrences(of: "{verb}", with: "said") }
    for q in all {
        let kept = FollowUps.unquoted(q, seed: 1)
        #expect(!kept.contains("long walk") && !kept.contains("“") && !kept.contains("”"), "\(q)")
        #expect(kept.hasSuffix("?") && kept.first?.isUppercase == true, "\(kept)")
    }
    #expect(FollowUps.unquoted("You said “\(phrase)”. What’s underneath that?", seed: 0) == "What’s underneath that?")
    // Any quote is the person's words: one left mid-sentence takes its question with it.
    #expect(FollowUps.phraseless.contains(FollowUps.unquoted("Thinking about “\(phrase)”, what would ‘enough’ look like here?", seed: 0)))
    #expect(FollowUps.unquoted("Thinking about “\(phrase)”, what’s the next step?", seed: 0) == "What’s the next step?")
    // Other quote marks, as a model writing for another locale might use them; apostrophes stay.
    for quoted in ["‘\(phrase)’", "'\(phrase)'", "« \(phrase) »", "„\(phrase)“", "「\(phrase)」"] {
        #expect(FollowUps.unquoted("You said \(quoted). What’s underneath that?", seed: 0) == "What’s underneath that?", "\(quoted)")
        #expect(FollowUps.phraseless.contains(FollowUps.unquoted("What did \(quoted) feel like?", seed: 2)), "\(quoted)")
    }
    #expect(FollowUps.unquoted("What's the part of the walk you'd keep?", seed: 0) == "What's the part of the walk you'd keep?")
    #expect(FollowUps.unquoted("What’s the part of the walk you’d keep?", seed: 0) == "What’s the part of the walk you’d keep?")
    // The quote inside the question, or one left open: an open question in its place.
    #expect(FollowUps.phraseless.contains(FollowUps.unquoted("What did \"\(phrase)\" feel like?", seed: 2)))
    #expect(FollowUps.phraseless.contains(FollowUps.unquoted("What did “\(phrase) feel like?", seed: 2)))
    #expect(FollowUps.unquoted("What made the walk feel long?", seed: 0) == "What made the walk feel long?")
}

// MARK: A typed title is gated with the words, never read or quoted (SR-01, SR-17)

@Test func aPagesTitleIsGatedWithItsWordsAndNeverQuoted() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: stillAI())
    let body = "Walked home the long way by the river after work. The water was high and loud."
    let page = Entry(kind: .reflection, body: body)
    try await l.insertEntry(page)
    await p.process(entryId: page.id) {}
    #expect(await p.dayStatus(page.localDay) == .ready)
    let reads = try await rowCount(l, "ai_run", "feature='entry_reading'")

    // A title-only edit is an edit: gated with the words, which aren't read again.
    try await l.updateEntryText(id: page.id, body: body, titleUser: "The river path", captionUser: nil)
    #expect(try await l.entry(page.id)?.processingStatus == ProcessingStatus.pending)
    await p.process(entryId: page.id) {}
    let titled = try #require(try await l.entry(page.id))
    #expect(try await l.verdicts(day: page.localDay)[page.id]?.textSha256 == sha256(body + "\nThe river path"))
    #expect(await p.gatedText(of: titled) == body + "\nThe river path")
    #expect(try await rowCount(l, "ai_run", "feature='entry_reading'") == reads)
    #expect(try await l.hasAnnotation(entryId: page.id, inputHash: try #require(await p.wordsHash(of: titled))))
    #expect(await p.dayStatus(page.localDay) == .ready)
    let day = try #require(await p.readDay(page.localDay))
    #expect(!day.quotes.isEmpty && day.quotes.allSatisfy { $0.field == "body" && $0.utf16To <= body.utf16.count })
    try await expectVerbatim(day, l)

    // A held title holds the day: no reading, letter or mood, and nothing generated is kept (SR-13, SR-15).
    try await l.updateEntryText(id: page.id, body: body, titleUser: "No point anymore", captionUser: nil)
    await p.process(entryId: page.id) {}
    #expect(try await l.verdicts(day: page.localDay)[page.id]?.verdict == "safety_hold")
    #expect(await p.dayStatus(page.localDay) == .held)
    #expect(await p.readDay(page.localDay) == nil)
    #expect(await p.dayMood(page.localDay) == nil)
    #expect(try await l.annotations(day: page.localDay)[page.id] == nil)

    // Retitled, the words are read again, and the day with them.
    try await l.updateEntryText(id: page.id, body: body, titleUser: "The river path", captionUser: nil)
    await p.process(entryId: page.id) {}
    #expect(await p.dayStatus(page.localDay) == .ready)
    #expect(await p.readDay(page.localDay) != nil)
}

@Test func aTitleAloneIsGatedButLeavesNothingToRead() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: stillAI())
    let page = Entry(kind: .reflection, body: "Walked home the long way by the river after work.")
    let bare = Entry(kind: .reflection, titleUser: "No point anymore", body: "", localDay: page.localDay)
    try await l.insertEntry(page)
    try await l.insertEntry(bare)
    await p.process(entryId: page.id) {}
    await p.process(entryId: bare.id) {}
    #expect(await p.dayStatus(page.localDay) == .held)

    try await l.updateEntryText(id: bare.id, body: "", titleUser: "Tuesday", captionUser: nil)
    #expect(try await l.entry(bare.id)?.processingStatus == ProcessingStatus.pending)
    await p.process(entryId: bare.id) {}
    #expect(try await l.verdicts(day: page.localDay)[bare.id]?.verdict == "clear")
    #expect(try await l.annotations(day: page.localDay)[bare.id] == nil)
    #expect(await p.dayStatus(page.localDay) == .ready)
    #expect(try #require(await p.readDay(page.localDay)).entryIds == [page.id])

    try await l.updateEntryText(id: bare.id, body: "", titleUser: nil, captionUser: nil)
    #expect(try await l.entry(bare.id)?.processingStatus == ProcessingStatus.done)
    #expect(await p.dayStatus(page.localDay) == .ready)
}

@Test func aStillsTitleIsGatedWithItsDescriptionWhichStaysItsReading() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: stillAI())
    let s = try await stillEntry(l)
    await p.process(entryId: s.id) {}
    #expect(await p.dayStatus(s.localDay) == .ready)

    try await l.updateEntryText(id: s.id, body: nil, titleUser: "Sunday in the park", captionUser: nil)
    #expect(try await l.entry(s.id)?.processingStatus == ProcessingStatus.pending)
    await p.process(entryId: s.id) {}
    let e = try #require(try await l.entry(s.id))
    let c = try #require(try await l.stillCaption(entryId: s.id))
    #expect(try await l.verdicts(day: s.localDay)[s.id]?.textSha256 == sha256(c.gatedText! + "\nSunday in the park"))
    #expect(try await rowCount(l, "ai_run", "feature='still_caption'") == 1)
    #expect(try await l.hasAnnotation(entryId: s.id, inputHash: try #require(await p.wordsHash(of: e))))
    #expect(try #require(await p.readDay(s.localDay)).entryIds == [s.id])

    // A held title holds the still and its day, and the description goes with the hold (SR-15).
    try await l.updateEntryText(id: s.id, body: nil, titleUser: "No point anymore", captionUser: nil)
    await p.process(entryId: s.id) {}
    #expect(await p.dayStatus(s.localDay) == .held)
    #expect(await p.readDay(s.localDay) == nil)
    #expect(try await l.stillCaption(entryId: s.id)?.caption == nil)
}

@Test func aRecordingsTitleIsGatedWithItsTranscript() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: stillAI())
    let asset = MediaAsset(fileName: "2026-10-28/s/part-1.mov", kind: .video, origin: "recorded", state: "ready")
    let m = Entry(kind: .moment, mediaId: asset.id)
    try await l.insertMedia(asset)
    try await l.insertEntry(m)
    let said = "the long walk home by the river".split(separator: " ")
    try await l.setTranscript(mediaId: asset.id, words: said.enumerated().map { TranscriptWord(text: String($1), startMs: $0 * 300, durMs: 250, confidence: 0.9) },
                              extractorVersion: "t")
    await p.process(entryId: m.id) {}
    #expect(await p.dayStatus(m.localDay) == .ready)

    try await l.updateEntryText(id: m.id, body: nil, titleUser: "No point anymore", captionUser: nil)
    #expect(try await l.entry(m.id)?.processingStatus == ProcessingStatus.pending)
    await p.process(entryId: m.id) {}
    #expect(await p.dayStatus(m.localDay) == .held)

    // Cleared, a recording still has its words to gate.
    try await l.updateEntryText(id: m.id, body: nil, titleUser: nil, captionUser: nil)
    #expect(try await l.entry(m.id)?.processingStatus == ProcessingStatus.pending)
    await p.process(entryId: m.id) {}
    #expect(await p.dayStatus(m.localDay) == .ready)
}

@Test func aRecordingTitledBeforeTitlesWereGatedIsSweptUp() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: stillAI())
    let asset = MediaAsset(fileName: "2026-10-28/s/part-1.mov", kind: .video, origin: "recorded", state: "ready")
    let m = Entry(kind: .moment, titleUser: "No point anymore", mediaId: asset.id, processingStatus: ProcessingStatus.done)
    let untitled = Entry(kind: .reflection, body: "Walked home the long way by the river after work.", localDay: m.localDay)
    try await l.insertMedia(asset)
    try await l.insertEntry(m)
    try await l.insertEntry(untitled)
    try await l.setTranscript(mediaId: asset.id, words: [TranscriptWord(text: "River", startMs: 0, durMs: 300, confidence: 0.9)], extractorVersion: "t")
    // As an older build left it: the transcript gated, the title never.
    try await l.insertVerdict(SafetyVerdictRow(entryId: m.id, textSha256: sha256("River"), safetyVersion: SafetyGate.version, layer: 2,
                                               verdict: "clear", reasonCode: "clear"))
    await p.process(entryId: untitled.id) {}
    #expect(await p.ungatedTitles() == [m.id])
    await p.process(entryId: m.id) {}
    #expect(await p.ungatedTitles().isEmpty)
    #expect(await p.dayStatus(m.localDay) == .held)
}

@Test func aSilentRecordingsTitleHoldsUntilItIsCleared() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: stillAI())
    let page = Entry(kind: .reflection, body: "Walked home the long way by the river after work.")
    let asset = MediaAsset(fileName: "2026-10-28/s/part-1.m4a", kind: .audio, origin: "recorded", state: "ready")
    let v = Entry(kind: .voice, titleUser: "No point anymore", localDay: page.localDay, mediaId: asset.id, processingStatus: ProcessingStatus.done)
    try await l.insertEntry(page)
    try await l.insertMedia(asset)
    try await l.insertEntry(v)
    await p.process(entryId: page.id) {}
    let gated = try #require(try await p.text(for: v))
    #expect(gated.text == "No point anymore" && gated.field == "title_user")
    try await l.insertVerdict(SafetyVerdictRow(entryId: v.id, textSha256: sha256(gated.text), safetyVersion: SafetyGate.version, layer: 1,
                                               verdict: "safety_hold", reasonCode: "phrase"))
    #expect(await p.dayStatus(page.localDay) == .held)

    try await l.updateEntryText(id: v.id, body: nil, titleUser: nil, captionUser: nil)
    let cleared = try #require(try await l.entry(v.id))
    #expect(try await p.text(for: cleared) == nil)
    #expect(await p.gatedText(of: cleared) == "")
    #expect(await p.dayStatus(page.localDay) == .ready)
}

// MARK: What Edit details takes is gated with the words

@Test func aPagesCaptionIsGatedWithItsWords() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: answers())
    let page = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(page)
    await p.process(entryId: page.id) {}
    #expect(await p.dayStatus(page.localDay) == .ready)

    // Edit details ▸ Caption, as the sheet saves it.
    try await l.updateEntryText(id: page.id, body: chai, titleUser: nil, captionUser: "No point anymore")
    #expect(try await l.entry(page.id)?.processingStatus == ProcessingStatus.pending)
    await p.process(entryId: page.id) {}
    #expect(await p.dayStatus(page.localDay) == .held)
    #expect(await p.readDay(page.localDay) == nil)

    // A caption that clears: the lens hashes it as the gate did, so the page's mood shows there.
    try await l.updateEntryText(id: page.id, body: chai, titleUser: nil, captionUser: "Tuesday tea")
    await p.process(entryId: page.id) {}
    #expect(await p.dayStatus(page.localDay) == .ready)
    #expect(try await l.lensEntries(from: page.localDay, to: page.localDay).first?.mood == .calm)
}

@Test func aVoiceNotesSummaryIsGatedWithItsWords() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: answers())
    let asset = MediaAsset(fileName: "2026-10-28/v/a.m4a", kind: .audio, origin: "recorded", state: "ready")
    let v = Entry(kind: .voice, mediaId: asset.id)
    try await l.insertMedia(asset)
    try await l.insertEntry(v)
    let said = chai.split(separator: " ").enumerated().map { TranscriptWord(text: String($1), startMs: $0 * 300, durMs: 300, confidence: 0.95) }
    try await l.setTranscript(mediaId: asset.id, words: said, extractorVersion: "t")
    await p.process(entryId: v.id) {}
    #expect(await p.dayStatus(v.localDay) == .ready)

    // Edit details ▸ Summary.
    try await l.updateSummary(id: v.id, "No point anymore")
    #expect(try await l.entry(v.id)?.processingStatus == ProcessingStatus.pending)
    await p.process(entryId: v.id) {}
    #expect(await p.dayStatus(v.localDay) == .held)
    #expect(await p.ungatedTitles().isEmpty)
}

@Test func aTitleOnARecordingThatCouldntBeSavedIsStillGated() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: answers())
    let page = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(page)
    await p.process(entryId: page.id) {}
    let asset = MediaAsset(fileName: "2026-10-28/s/part-1.mov", kind: .video, origin: "recorded", state: "missing")
    let m = Entry(kind: .moment, titleUser: "No point anymore", localDay: page.localDay, mediaId: asset.id)
    try await l.insertMedia(asset)
    try await l.insertEntry(m)
    #expect(await p.ungatedTitles() == [m.id])
    await p.process(entryId: m.id) {}
    #expect(try await l.entry(m.id)?.processingStatus == ProcessingStatus.failed)
    #expect(await p.ungatedTitles().isEmpty)
    #expect(await p.dayStatus(page.localDay) == .held)

    try await l.updateEntryText(id: m.id, body: nil, titleUser: "Tuesday", captionUser: nil)
    await p.process(entryId: m.id) {}
    #expect(await p.dayStatus(page.localDay) == .ready)
    // One that couldn't be transcribed still waits on its words, its title cleared or not.
    try await l.setProcessingStatus(id: m.id, ProcessingStatus.transcriptUnavailable)
    #expect(await p.dayStatus(page.localDay) == .awaitingCheck)
}
