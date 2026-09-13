import XCTest

final class LockLogicTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        return c
    }()

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    func lock(_ policy: UnlockPolicy) -> LockSet {
        var l = LockSet()
        l.id = policy.rawValue
        l.name = "Test"
        l.policy = policy
        l.appCount = 3
        return l
    }

    func testWindowAcrossMidnight() {
        var night = lock(.strict)
        night.allDay = false
        night.start = TimeOfDay(hour: 22, minute: 0)
        night.end = TimeOfDay(hour: 6, minute: 0)
        XCTAssertTrue(LockLogic.isActive(night, now: date(12, 23), calendar: cal))
        XCTAssertTrue(LockLogic.isActive(night, now: date(13, 2), calendar: cal))
        XCTAssertFalse(LockLogic.isActive(night, now: date(13, 12), calendar: cal))
        // Sept 12 2026 is a Saturday (7). Friday nights only: Saturday 2 AM belongs to Friday.
        night.days = [6]
        XCTAssertTrue(LockLogic.isActive(night, now: date(12, 2), calendar: cal))
        XCTAssertFalse(LockLogic.isActive(night, now: date(12, 23), calendar: cal))
    }

    func testPolicies() {
        let noon = date(12, 12)
        var today = TodayState(dayKey: "2026-09-12")
        for p in [UnlockPolicy.readOnce, .questionEach, .limited] {
            XCTAssertEqual(LockLogic.state(lock(p), today: today, now: noon, calendar: cal), .needsReading)
        }
        XCTAssertEqual(LockLogic.state(lock(.strict), today: today, now: noon, calendar: cal), .strict)

        today.readingDone = true
        XCTAssertEqual(LockLogic.state(lock(.readOnce), today: today, now: noon, calendar: cal), .needsTap)
        XCTAssertEqual(LockLogic.state(lock(.questionEach), today: today, now: noon, calendar: cal), .needsQuestion)
        XCTAssertEqual(LockLogic.state(lock(.limited), today: today, now: noon, calendar: cal), .needsTap)

        var limited = lock(.limited)
        limited.limit = 2
        var day = LockDay()
        day.count = 2
        today.unlocks[limited.id] = day
        XCTAssertEqual(LockLogic.state(limited, today: today, now: noon, calendar: cal), .usedUp)
        limited.limitNeedsQuestion = true
        limited.limit = 5
        XCTAssertEqual(LockLogic.state(limited, today: today, now: noon, calendar: cal), .needsQuestion)

        var open = LockDay()
        open.until = noon.addingTimeInterval(600)
        today.unlocks["questionEach"] = open
        XCTAssertEqual(LockLogic.state(lock(.questionEach), today: today, now: noon, calendar: cal), .open)

        today.unlocks["strict"] = open
        XCTAssertEqual(LockLogic.state(lock(.strict), today: today, now: noon, calendar: cal), .strict)
        var pass = LockDay()
        pass.passUntil = noon.addingTimeInterval(600)
        today.unlocks["strict"] = pass
        XCTAssertEqual(LockLogic.state(lock(.strict), today: today, now: noon, calendar: cal), .open)
    }

    func testInactiveCases() {
        let noon = date(12, 12)
        let today = TodayState(dayKey: "2026-09-12")
        var sundays = lock(.questionEach)
        sundays.days = [1]
        XCTAssertEqual(LockLogic.state(sundays, today: today, now: noon, calendar: cal), .inactive)
        var empty = lock(.questionEach)
        empty.appCount = 0
        XCTAssertEqual(LockLogic.state(empty, today: today, now: noon, calendar: cal), .inactive)
        var off = lock(.questionEach)
        off.enabled = false
        XCTAssertEqual(LockLogic.state(off, today: today, now: noon, calendar: cal), .inactive)
    }

    func testRewardEnds() {
        let noon = date(12, 12)
        var l = lock(.questionEach)
        l.rewardSeconds = 30
        XCTAssertEqual(LockLogic.rewardEnd(l, now: noon, calendar: cal), noon.addingTimeInterval(30))
        l.rewardSeconds = LockSet.untilEnd
        XCTAssertEqual(LockLogic.rewardEnd(l, now: noon, calendar: cal), date(13, 0))
        l.allDay = false
        l.start = TimeOfDay(hour: 9, minute: 0)
        l.end = TimeOfDay(hour: 15, minute: 0)
        XCTAssertEqual(LockLogic.rewardEnd(l, now: noon, calendar: cal), date(12, 15))
    }

    func testStrictestReadingCheck() {
        var a = lock(.questionEach)
        a.reading.questions = 3
        a.reading.pass = 2
        a.reading.words = 100
        var b = lock(.readOnce)
        b.reading.questions = 8
        b.reading.pass = 6
        let today = TodayState(dayKey: "2026-09-12")
        let check = LockLogic.readingCheck(today: today, locks: [a, b], now: date(12, 12), calendar: cal)
        XCTAssertEqual(check.questions, 8)
        XCTAssertEqual(check.pass, 6)
        XCTAssertEqual(check.words, 100)
    }

    func testReasons() {
        var today = TodayState(dayKey: "2026-09-12")
        let noon = date(12, 12)
        XCTAssertEqual(LockLogic.reason(today: today, locks: [lock(.questionEach)], now: noon, calendar: cal), .reading)
        today.readingDone = true
        XCTAssertEqual(LockLogic.reason(today: today, locks: [lock(.questionEach)], now: noon, calendar: cal), .recall)
        XCTAssertEqual(LockLogic.reason(today: today, locks: [lock(.readOnce)], now: noon, calendar: cal), .tap)
        XCTAssertEqual(LockLogic.reason(today: today, locks: [lock(.strict)], now: noon, calendar: cal), .strict)
        XCTAssertEqual(LockLogic.reason(today: today, locks: [], now: noon, calendar: cal), .none)
    }
}

final class ProtectionTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func lock(_ kind: ProtectionKind) -> LockSet {
        var l = LockSet()
        l.name = "Social"
        l.protection.kind = kind
        return l
    }

    func testAccess() {
        XCTAssertEqual(ProtectionLogic.access(lock(.none), readingDone: false, now: now), .open)
        var pass = lock(.passcode)
        XCTAssertEqual(ProtectionLogic.access(pass, readingDone: false, now: now), .open)
        let made = Passcode.make("1234")
        pass.protection.passcodeHash = made.hash
        pass.protection.passcodeSalt = made.salt
        XCTAssertEqual(ProtectionLogic.access(pass, readingDone: false, now: now), .needsPasscode)
        var timer = lock(.countdown)
        timer.protection.countdownMinutes = 15
        XCTAssertEqual(ProtectionLogic.access(timer, readingDone: false, now: now), .needsCountdown(15))
        XCTAssertEqual(ProtectionLogic.access(lock(.delay), readingDone: false, now: now), .delayed(24))
        var commit = lock(.commitment)
        commit.protection.commitUntil = now.addingTimeInterval(3600)
        if case .blocked = ProtectionLogic.access(commit, readingDone: true, now: now) {} else { XCTFail("commitment") }
        commit.protection.commitUntil = now.addingTimeInterval(-60)
        XCTAssertEqual(ProtectionLogic.access(commit, readingDone: true, now: now), .open)
        if case .blocked = ProtectionLogic.access(lock(.afterReading), readingDone: false, now: now) {} else { XCTFail("reading") }
        XCTAssertEqual(ProtectionLogic.access(lock(.afterReading), readingDone: true, now: now), .open)
    }

    func testPasscode() {
        let made = Passcode.make("482913")
        var p = LockProtection()
        p.passcodeHash = made.hash
        p.passcodeSalt = made.salt
        XCTAssertTrue(Passcode.verify("482913", p))
        XCTAssertFalse(Passcode.verify("000000", p))
        XCTAssertTrue(Passcode.isValid("1234"))
        XCTAssertFalse(Passcode.isValid("12a4"))
        XCTAssertFalse(Passcode.isValid("123"))
    }

    func testLegacySettingsMigrate() throws {
        let json = #"{"onboarded":true,"schedule":{"morning":{"hour":5,"minute":0}},"rules":{"wordsToType":80,"questionsPerCheck":6,"correctToPass":4,"unlockMinutes":45,"emergencyPasses":2},"lockSets":[{"id":"a","name":"Old","appCount":2,"mode":"allDay"},{"id":"b","name":"Night","appCount":1,"mode":"scheduled","allowEarning":false},{"id":"c","name":"Read","appCount":1,"mode":"untilRead"}]}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(s.schedule.morning.hour, 0)
        XCTAssertEqual(s.lockSets.count, 3)
        XCTAssertEqual(s.lockSets[0].policy, .questionEach)
        XCTAssertEqual(s.lockSets[0].rewardSeconds, 45 * 60)
        XCTAssertEqual(s.lockSets[0].reading.words, 80)
        XCTAssertEqual(s.lockSets[0].reading.pass, 4)
        XCTAssertEqual(s.lockSets[0].emergencyPasses, 2)
        XCTAssertEqual(s.lockSets[1].policy, .strict)
        XCTAssertFalse(s.lockSets[1].allDay)
        XCTAssertEqual(s.lockSets[2].policy, .readOnce)
        XCTAssertEqual(s.lockSets[2].rewardSeconds, LockSet.untilEnd)
        let again = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(again, s)
    }

    func testPassesResetMonthly() {
        var s = AppSettings()
        var l = LockSet()
        l.id = "x"
        l.emergencyPasses = 3
        let now = Date()
        s.passUses = [PassUse(date: now, minutes: 15, lockID: "x"), PassUse(date: now.addingTimeInterval(-40 * 86_400), minutes: 15, lockID: "x"),
                      PassUse(date: now, minutes: 15, lockID: "other")]
        XCTAssertEqual(s.passesLeft(l, now: now), 2)
    }
}

final class ReadingDraftTests: XCTestCase {
    func testResumeSteps() {
        var d = ReadingDraft(dayKey: "2026-09-13", ref: ChapterRef(book: "JHN", chapter: 3))
        d.step = .read
        XCTAssertEqual(d.resumeStep, .mode)
        d.step = .reflect
        XCTAssertEqual(d.resumeStep, .reflect)
        d.step = .quiz
        XCTAssertEqual(d.resumeStep, .quiz)
        d.failed = true
        XCTAssertEqual(d.resumeStep, .quiz)
        d.step = .read
        XCTAssertEqual(d.resumeStep, .result)
        d.step = .result
        XCTAssertEqual(d.resumeStep, .result)
    }

    func testRoundTrip() throws {
        var d = ReadingDraft(dayKey: "2026-09-13", ref: ChapterRef(book: "MRK", chapter: 5))
        d.reflection = "Legion"
        d.prompts = ["a", "b", "c"]
        d.quizIDs = ["MRK.5.1", "MRK.5.2"]
        d.answered = 1
        let back = try JSONDecoder().decode(ReadingDraft.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back, d)
    }
}

final class PathLogicTests: XCTestCase {
    func testOnPathAdvances() {
        let a = PathLogic.after(planID: "book.MRK", index: 4, position: 4, count: 16)
        XCTAssertEqual(a.kind, .onPath)
        XCTAssertEqual(a.position, 5)
        XCTAssertNil(a.alternative)
        XCTAssertEqual(PathLogic.after(planID: "x", index: 15, position: 15, count: 16).kind, .finished)
    }

    func testRereadKeepsPlaceAndOffersContinue() {
        let a = PathLogic.after(planID: "book.MRK", index: 1, position: 5, count: 16)
        XCTAssertEqual(a.kind, .reread)
        XCTAssertEqual(a.position, 5)
        XCTAssertEqual(a.alternative, 2)
        XCTAssertNil(PathLogic.after(planID: "x", index: 4, position: 5, count: 16).alternative)
    }

    func testSkipAheadOffersGoingBack() {
        let a = PathLogic.after(planID: "book.MRK", index: 9, position: 5, count: 16)
        XCTAssertEqual(a.kind, .skippedAhead)
        XCTAssertEqual(a.position, 10)
        XCTAssertEqual(a.alternative, 5)
    }

    func testPlans() {
        XCTAssertEqual(ReadingPlans.canonical("mark"), "book.MRK")
        XCTAssertEqual(ReadingPlans.plan("john").id, "book.JHN")
        XCTAssertEqual(ReadingPlans.bookPlans.count, 30)
        XCTAssertEqual(ReadingPlans.plan("nt").chapters.count, 260)
        XCTAssertEqual(Set(ReadingPlans.all.map(\.id)).count, ReadingPlans.all.count)
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
