import XCTest

final class ConfigLogicTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func settings(protection: Protection = Protection()) -> AppSettings {
        var s = AppSettings()
        s.onboarded = true
        s.onboardedAt = now.addingTimeInterval(-10 * 86_400)
        var lock = LockSet()
        lock.id = "a"
        lock.appCount = 4
        lock.mode = .allDay
        s.lockSets = [lock]
        s.protection = protection
        return s
    }

    func testStricterChangesApplyNow() {
        let s = settings()
        var p = s.config
        p.rules.wordsToType = 100
        p.rules.unlockMinutes = 15
        p.lockSets[0].appCount = 6
        var extra = LockSet()
        extra.appCount = 2
        p.lockSets.append(extra)
        XCTAssertFalse(ConfigLogic.isEasier(current: s.config, proposed: p))
        XCTAssertEqual(ConfigLogic.evaluate(settings: s, proposed: p, readingDone: false, now: now, passcodeOK: false, cooldownDone: false), .applied)
    }

    func testEasierChangesAreSpotted() {
        let s = settings()
        func easier(_ edit: (inout LockConfig) -> Void) -> Bool {
            var p = s.config
            edit(&p)
            return ConfigLogic.isEasier(current: s.config, proposed: p)
        }
        XCTAssertTrue(easier { $0.rules.wordsToType = 20 })
        XCTAssertTrue(easier { $0.rules.emergencyPasses = 9 })
        XCTAssertTrue(easier { $0.lockSets.removeAll() })
        XCTAssertTrue(easier { $0.lockSets[0].enabled = false })
        XCTAssertTrue(easier { $0.lockSets[0].appCount = 1 })
        XCTAssertTrue(easier { $0.lockSets[0].days.remove(1) })
        XCTAssertTrue(easier { $0.lockSets[0].mode = .scheduled })
        XCTAssertTrue(easier { $0.lockSets[0].mode = .untilRead })
        XCTAssertTrue(easier { $0.schedule.morning = TimeOfDay(hour: 9, minute: 0) })
        XCTAssertTrue(easier { $0.protection.delayHours = 0 })
        XCTAssertFalse(easier { $0.schedule.morning = TimeOfDay(hour: 4, minute: 0) })
    }

    func testScheduledWindowShrinkingIsEasier() {
        var s = settings()
        s.lockSets[0].mode = .scheduled
        s.lockSets[0].start = TimeOfDay(hour: 21, minute: 0)
        s.lockSets[0].end = TimeOfDay(hour: 7, minute: 0)
        var shorter = s.config
        shorter.lockSets[0].end = TimeOfDay(hour: 6, minute: 0)
        XCTAssertTrue(ConfigLogic.isEasier(current: s.config, proposed: shorter))
        var longer = s.config
        longer.lockSets[0].start = TimeOfDay(hour: 20, minute: 0)
        XCTAssertFalse(ConfigLogic.isEasier(current: s.config, proposed: longer))
        var strict = s.config
        strict.lockSets[0].allowEarning = false
        XCTAssertFalse(ConfigLogic.isEasier(current: s.config, proposed: strict))
        s.lockSets[0].allowEarning = false
        var relaxed = s.config
        relaxed.lockSets[0].allowEarning = true
        XCTAssertTrue(ConfigLogic.isEasier(current: s.config, proposed: relaxed))
    }

    func testProtectionOrder() {
        var prot = Protection()
        let code = Passcode.make("1234")
        prot.passcodeHash = code.hash
        prot.passcodeSalt = code.salt
        prot.cooldownMinutes = 5
        prot.delayHours = 24
        prot.onlyAfterReading = true
        let s = settings(protection: prot)
        var p = s.config
        p.rules.wordsToType = 20

        if case .blocked = ConfigLogic.evaluate(settings: s, proposed: p, readingDone: false, now: now, passcodeOK: false, cooldownDone: false) {} else { XCTFail("reading gate") }
        XCTAssertEqual(ConfigLogic.evaluate(settings: s, proposed: p, readingDone: true, now: now, passcodeOK: false, cooldownDone: false), .needsPasscode)
        XCTAssertEqual(ConfigLogic.evaluate(settings: s, proposed: p, readingDone: true, now: now, passcodeOK: true, cooldownDone: false), .needsCooldown(5))
        XCTAssertEqual(ConfigLogic.evaluate(settings: s, proposed: p, readingDone: true, now: now, passcodeOK: true, cooldownDone: true), .pending(now.addingTimeInterval(86_400)))
    }

    func testCommitmentBlocksEverythingEasier() {
        var prot = Protection()
        prot.commitUntil = now.addingTimeInterval(3 * 86_400)
        let s = settings(protection: prot)
        var p = s.config
        p.protection.commitUntil = nil
        if case .blocked = ConfigLogic.evaluate(settings: s, proposed: p, readingDone: true, now: now, passcodeOK: true, cooldownDone: true) {} else { XCTFail("commitment") }
        var stricter = s.config
        stricter.rules.questionsPerCheck = 8
        XCTAssertEqual(ConfigLogic.evaluate(settings: s, proposed: stricter, readingDone: true, now: now, passcodeOK: false, cooldownDone: false), .applied)
    }

    func testSetupDaySkipsWaits() {
        var s = settings()
        s.onboardedAt = now.addingTimeInterval(-3600)
        s.protection.cooldownMinutes = 15
        var p = s.config
        p.rules.wordsToType = 20
        XCTAssertEqual(ConfigLogic.evaluate(settings: s, proposed: p, readingDone: false, now: now, passcodeOK: false, cooldownDone: false), .applied)
    }

    func testPasscode() {
        let made = Passcode.make("482913")
        var p = Protection()
        p.passcodeHash = made.hash
        p.passcodeSalt = made.salt
        XCTAssertTrue(Passcode.verify("482913", p))
        XCTAssertFalse(Passcode.verify("000000", p))
        XCTAssertTrue(Passcode.isValid("1234"))
        XCTAssertFalse(Passcode.isValid("12a4"))
        XCTAssertFalse(Passcode.isValid("123"))
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
        let json = #"{"onboarded":true,"rules":{"wordsToType":80},"lockSets":[{"name":"Old","appCount":2}],"unknownKey":5}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertTrue(s.onboarded)
        XCTAssertEqual(s.rules.wordsToType, 80)
        XCTAssertEqual(s.rules.questionsPerCheck, 5)
        XCTAssertEqual(s.lockSets.first?.name, "Old")
        XCTAssertEqual(s.lockSets.first?.mode, .allDay)
        XCTAssertEqual(s.protection.delayHours, 24)
    }
}

final class LockLogicTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        return c
    }()

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    func lock(_ mode: LockMode) -> LockSet {
        var l = LockSet()
        l.mode = mode
        l.appCount = 3
        return l
    }

    func testWindowAcrossMidnight() {
        var night = lock(.scheduled)
        night.start = TimeOfDay(hour: 22, minute: 0)
        night.end = TimeOfDay(hour: 6, minute: 0)
        XCTAssertTrue(LockLogic.inWindow(night, now: date(12, 23), calendar: cal))
        XCTAssertTrue(LockLogic.inWindow(night, now: date(13, 2), calendar: cal))
        XCTAssertFalse(LockLogic.inWindow(night, now: date(13, 12), calendar: cal))
        // Sept 12 2026 is a Saturday (7). Friday night only: Saturday 2 AM belongs to Friday.
        night.days = [6]
        XCTAssertTrue(LockLogic.inWindow(night, now: date(12, 2), calendar: cal))
        XCTAssertFalse(LockLogic.inWindow(night, now: date(12, 23), calendar: cal))
    }

    func testModes() {
        let noon = date(12, 12)
        var today = TodayState(dayKey: "2026-09-12")
        XCTAssertEqual(LockLogic.state(lock(.untilRead), today: today, now: noon, calendar: cal), .gate)
        XCTAssertEqual(LockLogic.state(lock(.allDay), today: today, now: noon, calendar: cal), .gate)
        today.readingDone = true
        XCTAssertEqual(LockLogic.state(lock(.untilRead), today: today, now: noon, calendar: cal), .open)
        XCTAssertEqual(LockLogic.state(lock(.allDay), today: today, now: noon, calendar: cal), .gate)
        today.middayPending = true
        XCTAssertEqual(LockLogic.state(lock(.untilRead), today: today, now: noon, calendar: cal), .gate)
        today.unlockedUntil = noon.addingTimeInterval(600)
        XCTAssertEqual(LockLogic.state(lock(.allDay), today: today, now: noon, calendar: cal), .open)

        var strict = lock(.scheduled)
        strict.start = TimeOfDay(hour: 11, minute: 0)
        strict.end = TimeOfDay(hour: 13, minute: 0)
        strict.allowEarning = false
        XCTAssertEqual(LockLogic.state(strict, today: today, now: noon, calendar: cal), .strict)
        today.passUntil = noon.addingTimeInterval(600)
        XCTAssertEqual(LockLogic.state(strict, today: today, now: noon, calendar: cal), .open)

        var off = lock(.allDay)
        off.days = [1]
        XCTAssertEqual(LockLogic.state(off, today: TodayState(dayKey: "2026-09-12"), now: noon, calendar: cal), .open)
        var empty = lock(.allDay)
        empty.appCount = 0
        XCTAssertEqual(LockLogic.state(empty, today: TodayState(dayKey: "2026-09-12"), now: noon, calendar: cal), .open)
    }

    func testReasons() {
        var s = AppSettings()
        s.lockSets = [lock(.allDay)]
        var today = TodayState(dayKey: "2026-09-12")
        let noon = date(12, 12)
        XCTAssertEqual(LockLogic.reason(today: today, settings: s, now: noon, calendar: cal), .reading)
        today.readingDone = true
        XCTAssertEqual(LockLogic.reason(today: today, settings: s, now: noon, calendar: cal), .recall)
        today.middayPending = true
        XCTAssertEqual(LockLogic.reason(today: today, settings: s, now: noon, calendar: cal), .midday)
        today.unlockedUntil = noon.addingTimeInterval(60)
        XCTAssertEqual(LockLogic.reason(today: today, settings: s, now: noon, calendar: cal), .none)
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

    func testMiddayTimes() {
        var s = Schedule()
        s.midday = TimeOfDay(hour: 12, minute: 0)
        XCTAssertEqual(s.middayTimes(count: 1).map(\.hour), [12])
        XCTAssertEqual(s.middayTimes(count: 3).map(\.hour), [12, 15, 18])
        XCTAssertEqual(s.middayTimes(count: 6).map(\.hour), [12, 14, 16, 18, 20, 22])
        XCTAssertEqual(s.middayTimes(count: 0).count, 0)
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
