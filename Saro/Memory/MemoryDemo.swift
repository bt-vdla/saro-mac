#if DOGFOOD
import Foundation
import SaroKit

/// Three weeks of synthetic history for snapshots (SR-28: never real words), so What Saro knows has something to show.
/// ponytail: rows are written straight from the heuristic twin, skipping the gate and the queue, because a snapshot run
/// can't wait for a model call per entry; the real path (Pipeline.learn) is covered by MemoryTests.
enum MemoryDemo {
    static let history: [(daysAgo: Double, text: String)] = [
        (20, "Dinner with my sister Maya was lovely. We talked about Dad and the garden for hours."),
        (18, "Long day at work. The launch slipped again and the standup ran over. I need to ask for a day off."),
        (16, "Walked in the park with Maya after work. The sky was pink and I felt calm for the first time in a while."),
        (14, "Anxious about the launch and awake at 3am. Ravi texted me at midnight about the deck."),
        (12, "Coffee with Ravi in Pune. He said the move is going well. I want to visit him again in the spring."),
        (10, "Anxious all morning before the review. Then it went fine, and work felt lighter."),
        (8, "Read a book on the train to Mumbai. I want to read more and scroll less."),
        (6, "Maya called about Dad's birthday. Tomorrow I will book the restaurant."),
        (4, "So anxious about money this week. Rent is due and the budget is tight."),
        (2, "Long run along the river, then a quiet evening. I'm grateful for slow Sundays."),
        (1, "Lunch with Ravi and Maya. We laughed about the launch and planned a trip to Goa."),
    ]

    static func seed(_ model: AppModel) async {
        let ledger = model.ledger
        for h in history {
            let e = Entry(kind: .reflection, body: h.text, capturedAt: .now.addingTimeInterval(-h.daysAgo * 86_400 - 3 * 3600),
                          processingStatus: ProcessingStatus.done)
            try? await ledger.insertEntry(e)
            var rows = MemoryRules.observe(entryId: e.id, field: "body", text: h.text, localDay: e.localDay)
            for i in rows.indices { rows[i].createdAt = e.capturedAt }
            var run = AIRun(feature: Ledger.memoryFeature, executor: "heuristic", status: "demo")
            run.extractorVersion = MemoryRules.extractorVersion
            run.inputHash = sha256(h.text)
            try? await ledger.insertObservations(rows, run: run, inputs: [AIRunInput(entryId: e.id, field: "body", text: h.text)])
        }
        var starter = StarterContext(version: (try? await ledger.newStarterVersion()) ?? 1)
        starter.answers = [1: "Sam", 3: "Late, usually around 9:30pm.", 4: "I want to be kinder to myself", 5: "Gentle, please."]
        starter.picks = [Pick(kind: .name, text: "Sam", value: "Sam", start: 0, end: 3, q: 1),
                         Pick(kind: .time, text: "9:30pm", value: "21:30", start: 21, end: 27, q: 3),
                         Pick(kind: .goal, text: "I want to be kinder to myself", value: "I want to be kinder to myself", start: 0, end: 29, q: 4),
                         Pick(kind: .tone, text: "Gentle", value: "gentle", start: 0, end: 6, q: 5)]
        try? await ledger.saveStarter(starter)
        try? await ledger.addUserMemory(MemoryObservation(entryId: nil, source: .user, kind: .line, key: "user:demo", label: "I work best in the mornings.",
                                                    localDay: LocalDay.today()))
        await model.memory.load()
        await model.reload()
    }
}
#endif
