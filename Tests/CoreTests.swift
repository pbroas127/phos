import XCTest

final class RuleLogicTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testStricterChangesApplyNow() {
        let current = Rules()
        var proposed = current
        proposed.wordsToType = 100
        proposed.unlockMinutes = 15
        let r = RuleLogic.propose(current: current, proposed: proposed, now: now)
        XCTAssertEqual(r.effective.wordsToType, 100)
        XCTAssertEqual(r.effective.unlockMinutes, 15)
        XCTAssertNil(r.pending)
    }

    func testEasierChangesWaitADay() {
        let current = Rules()
        var proposed = current
        proposed.wordsToType = 20
        proposed.unlockMinutes = Rules.restOfDay
        let r = RuleLogic.propose(current: current, proposed: proposed, now: now)
        XCTAssertEqual(r.effective.wordsToType, 60)
        XCTAssertEqual(r.effective.unlockMinutes, 30)
        XCTAssertEqual(r.pending?.rules.unlockMinutes, Rules.restOfDay)
        XCTAssertEqual(r.pending?.effectiveAt, now.addingTimeInterval(86_400))
        let early = RuleLogic.resolve(current: r.effective, pending: r.pending, now: now.addingTimeInterval(3600))
        XCTAssertEqual(early.rules.wordsToType, 60)
        let later = RuleLogic.resolve(current: r.effective, pending: r.pending, now: now.addingTimeInterval(90_000))
        XCTAssertEqual(later.rules.wordsToType, 20)
        XCTAssertNil(later.pending)
    }

    func testMixedChangeSplits() {
        let current = Rules()
        var proposed = current
        proposed.questionsPerCheck = 8
        proposed.emergencyPasses = 10
        let r = RuleLogic.propose(current: current, proposed: proposed, now: now)
        XCTAssertEqual(r.effective.questionsPerCheck, 8)
        XCTAssertEqual(r.effective.emergencyPasses, 3)
        XCTAssertEqual(r.pending?.rules.emergencyPasses, 10)
    }

    func testTurningOffDelayIsEasier() {
        var proposed = Rules()
        proposed.delayEasierChanges = false
        let r = RuleLogic.propose(current: Rules(), proposed: proposed, now: now)
        XCTAssertTrue(r.effective.delayEasierChanges)
        XCTAssertNotNil(r.pending)
    }

    func testNoDelayAppliesEverything() {
        var current = Rules()
        current.delayEasierChanges = false
        var proposed = current
        proposed.wordsToType = 20
        let r = RuleLogic.propose(current: current, proposed: proposed, now: now)
        XCTAssertEqual(r.effective.wordsToType, 20)
        XCTAssertNil(r.pending)
    }

    func testNormalizeClampsPassToQuestions() {
        var r = Rules()
        r.questionsPerCheck = 2
        r.correctToPass = 5
        r.wordsToType = 5000
        r.unlockMinutes = 33
        let n = r.normalized()
        XCTAssertEqual(n.correctToPass, 2)
        XCTAssertEqual(n.wordsToType, 300)
        XCTAssertEqual(n.unlockMinutes, 30)
    }

    func testTolerantDecoding() throws {
        let json = #"{"onboarded":true,"rules":{"wordsToType":80},"unknownKey":5}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertTrue(s.onboarded)
        XCTAssertEqual(s.rules.wordsToType, 80)
        XCTAssertEqual(s.rules.questionsPerCheck, 5)
        XCTAssertEqual(s.planID, "john")
    }
}

final class DayAndStreakTests: XCTestCase {
    func testDayStartsAtMorningTime() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Chicago")!
        let morning = TimeOfDay(hour: 5, minute: 0)
        let early = cal.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 3))!
        let later = cal.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 6))!
        XCTAssertEqual(DayKey.key(for: early, morning: morning, calendar: cal), "2026-09-11")
        XCTAssertEqual(DayKey.key(for: later, morning: morning, calendar: cal), "2026-09-12")
    }

    func testKeyArithmetic() {
        XCTAssertEqual(DayKey.adding(-1, to: "2026-03-01"), "2026-02-28")
        XCTAssertEqual(DayKey.adding(1, to: "2026-12-31"), "2027-01-01")
    }

    func testStreakCountsFromYesterdayWhenTodayNotDone() {
        let done: Set<String> = ["2026-09-09", "2026-09-10", "2026-09-11"]
        XCTAssertEqual(Streaks.current(doneKeys: done, todayKey: "2026-09-12"), 3)
        XCTAssertEqual(Streaks.current(doneKeys: done.union(["2026-09-12"]), todayKey: "2026-09-12"), 4)
        XCTAssertEqual(Streaks.current(doneKeys: ["2026-09-08"], todayKey: "2026-09-12"), 0)
        XCTAssertEqual(Streaks.longest(doneKeys: done.union(["2026-09-01", "2026-09-02"])), 3)
    }

    func testMiddayTimes() {
        var s = Schedule()
        s.midday = TimeOfDay(hour: 12, minute: 0)
        XCTAssertEqual(s.middayTimes(count: 1).map(\.hour), [12])
        XCTAssertEqual(s.middayTimes(count: 3).map(\.hour), [12, 15, 18])
        XCTAssertEqual(s.middayTimes(count: 6).map(\.hour), [12, 14, 16, 18, 20, 22])
        XCTAssertEqual(s.middayTimes(count: 0).count, 0)
    }

    func testLockReasons() {
        let now = Date()
        var t = TodayState(dayKey: "2026-09-12")
        XCTAssertEqual(t.lockReason(at: now), .reading)
        t.readingDone = true
        XCTAssertEqual(t.lockReason(at: now), .recall)
        t.middayPending = true
        XCTAssertEqual(t.lockReason(at: now), .midday)
        t.eveningLocked = true
        XCTAssertEqual(t.lockReason(at: now), .evening)
        t.unlockedUntil = now.addingTimeInterval(60)
        XCTAssertEqual(t.lockReason(at: now), .none)
    }

    func testPassesResetMonthly() {
        var s = AppSettings()
        let now = Date()
        s.passUses = [PassUse(date: now, minutes: 20), PassUse(date: now.addingTimeInterval(-40 * 86_400), minutes: 20)]
        XCTAssertEqual(s.passesLeft(now: now), 2)
    }
}

final class TextCheckTests: XCTestCase {
    let john3 = "Now there was a man of the Pharisees named Nicodemus, a ruler of the Jews. He came to Jesus by night and said to him, Rabbi, we know that you are a teacher who has come from God. Jesus answered him, Most certainly I tell you, unless one is born anew, he can't see God's Kingdom. For God so loved the world, that he gave his only born Son, that whoever believes in him should not perish, but have eternal life. As Moses lifted up the serpent in the wilderness, even so must the Son of Man be lifted up. John also was baptizing in Enon near Salim, because there was much water there."

    func testWordCounting() {
        XCTAssertEqual(TextChecks.wordCount("Jesus didn’t shame him, not once."), 6)
        XCTAssertEqual(TextChecks.wordCount("  "), 0)
        XCTAssertEqual(TextChecks.distinctCount("the the the light"), 2)
    }

    func testRelevantReflectionPasses() {
        let r = "Nicodemus came at night because he was afraid of the other Pharisees. Jesus told him he must be born anew, and that God loved the world enough to give his Son so we would not perish."
        XCTAssertTrue(TextChecks.isRelevant(reflection: r, chapterText: john3))
    }

    func testOffTopicReflectionFails() {
        let r = "I set my fantasy football lineup this morning and started two running backs because the matchup looked good, then I checked scores and ate breakfast while watching highlights before class started today."
        XCTAssertFalse(TextChecks.isRelevant(reflection: r, chapterText: john3))
    }

    func testStemming() {
        XCTAssertEqual(TextChecks.stem("believes"), TextChecks.stem("believe"))
        XCTAssertEqual(TextChecks.stem("loved"), TextChecks.stem("love"))
    }

    func testRedLetterSegments() {
        let s = TextChecks.segments("Jesus answered him, {“Most certainly I tell you.”} Then he left.")
        XCTAssertEqual(s.count, 3)
        XCTAssertFalse(s[0].red)
        XCTAssertTrue(s[1].red)
        XCTAssertEqual(TextChecks.plain("{red} text"), "red text")
    }

    func testRecite() {
        let target = "For God so loved the world, that he gave his only born Son"
        XCTAssertEqual(TextChecks.reciteMatch(spoken: "for god so loved the world that he gave his only born son", target: target).matched, 13)
        XCTAssertLessThan(TextChecks.reciteMatch(spoken: "god loved people", target: target).matched, 4)
    }

    func testQuote() {
        XCTAssertEqual(TextChecks.quote("He came at night. Then more."), "He came at night.")
    }
}

final class QuizEngineTests: XCTestCase {
    func makeBank() -> [Question] {
        var qs: [Question] = []
        let kinds: [Question.Kind] = [.choice, .blank, .order, .tf]
        for i in 0..<10 {
            let kind = kinds[i % 4]
            var q = Question(t: kind, d: i % 3 + 1, v: i + 1, q: "Question \(i) ____", options: ["right", "a", "b", "c"],
                             answerText: "the right phrase", answerBool: true, wrong: ["x y", "y z", "z w"], items: ["one", "two", "three", "four"])
            q.id = "JHN.3.\(i)"
            qs.append(q)
        }
        return qs
    }

    func testPicksEveryDifficultyEasyFirst() {
        var g = SeededGenerator(seed: 1)
        let items = QuizEngine.pick(from: makeBank(), count: 5, avoiding: [], using: &g)
        XCTAssertEqual(items.count, 5)
        XCTAssertEqual(Set(items.map(\.question.d)), [1, 2, 3])
        XCTAssertEqual(items.map(\.question.d), items.map(\.question.d).sorted())
        XCTAssertEqual(Set(items.map(\.id)).count, 5)
    }

    func testAvoidsAskedQuestions() {
        var g = SeededGenerator(seed: 2)
        let bank = makeBank()
        let asked = Set(bank.prefix(5).map(\.id))
        let items = QuizEngine.pick(from: bank, count: 5, avoiding: asked, using: &g)
        XCTAssertTrue(items.allSatisfy { !asked.contains($0.id) })
    }

    func testRecyclesWhenBankRunsOut() {
        var g = SeededGenerator(seed: 3)
        let bank = makeBank()
        let items = QuizEngine.pick(from: bank, count: 5, avoiding: Set(bank.map(\.id)), using: &g)
        XCTAssertEqual(items.count, 5)
    }

    func testAnswerChecking() {
        var g = SeededGenerator(seed: 4)
        let bank = makeBank()
        let choice = QuizEngine.item(for: bank[0], using: &g)
        XCTAssertTrue(choice.isCorrect(choice: "right"))
        XCTAssertFalse(choice.isCorrect(choice: "a"))
        let blank = QuizEngine.item(for: bank[1], using: &g)
        XCTAssertEqual(blank.choices.count, 4)
        XCTAssertTrue(blank.isCorrect(choice: "the right phrase"))
        let order = QuizEngine.item(for: bank[2], using: &g)
        XCTAssertNotEqual(order.choices, ["one", "two", "three", "four"])
        XCTAssertTrue(order.isCorrect(order: ["one", "two", "three", "four"]))
        let tf = QuizEngine.item(for: bank[3], using: &g)
        XCTAssertTrue(tf.isCorrect(bool: true))
    }

    func testWaits() {
        XCTAssertEqual(QuizEngine.waitAfterMiss(missCount: 1), 0)
        XCTAssertEqual(QuizEngine.waitAfterMiss(missCount: 2), 120)
        XCTAssertEqual(QuizEngine.waitAfterMiss(missCount: 5), 300)
    }
}

/// Loads the real bundled Bible and question bank.
final class BundledContentTests: XCTestCase {
    func url(_ name: String) -> URL? {
        Bundle(for: BundledContentTests.self).url(forResource: name, withExtension: "json")
    }

    func testEveryPlanChapterHasQuestionsAndText() throws {
        let bundle = Bundle(for: BundledContentTests.self)
        let files = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent != "bible.json" }
            .compactMap { try? Data(contentsOf: $0) }
        let bank = QuestionBank(files: files)
        let bibleURL = try XCTUnwrap(url("bible"))
        let bible = try Bible(data: Data(contentsOf: bibleURL))
        XCTAssertEqual(bible.books.count, 66)
        for plan in ReadingPlans.all {
            for ref in plan.chapters {
                let qs = bank.questions(for: ref)
                XCTAssertNotNil(qs, "missing questions for \(ref.id)")
                XCTAssertGreaterThanOrEqual(qs?.questions.count ?? 0, 5, ref.id)
                XCTAssertNotNil(bible.chapter(ref), "missing text for \(ref.id)")
                if let qs, let ch = bible.chapter(ref) {
                    XCTAssertLessThanOrEqual(qs.keyVerse, ch.verses.count, ref.id)
                    for q in qs.questions { XCTAssertLessThanOrEqual(q.v, ch.verses.count, q.id) }
                }
            }
        }
    }
}
