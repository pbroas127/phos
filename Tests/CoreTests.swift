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
        d.readMode = .speak
        d.aloudCursor = 12
        XCTAssertEqual(d.resumeStep, .read)
        d.readMode = .paper
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
        XCTAssertEqual(ReadingPlans.bookPlans.count, 66)
        XCTAssertEqual(ReadingPlans.plan("bible").chapters.count, 1189)
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

    func testEveryChapterHasATitle() throws {
        let data = try Data(contentsOf: XCTUnwrap(url("chapter_titles")))
        let titles = try JSONDecoder().decode([String: String].self, from: data)
        let bible = try Bible(data: Data(contentsOf: XCTUnwrap(url("bible"))))
        var count = 0
        for book in bible.books {
            for n in 1...book.chapters.count {
                let title = titles["\(book.id).\(n)"]
                XCTAssertNotNil(title, "\(book.id).\(n)")
                XCTAssertFalse(title?.contains("-") ?? false)
                count += 1
            }
        }
        XCTAssertEqual(count, 1189)
    }

    func testEveryPlanChapterHasQuestionsAndText() throws {
        let bundle = Bundle(for: BundledContentTests.self)
        let files = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { !["bible.json", "chapter_titles.json"].contains($0.lastPathComponent) }
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

final class ReadAlongTests: XCTestCase {
    let verses = [
        "Now there was a man of the Pharisees named Nicodemus, a ruler of the Jews.",
        "The same came to him by night, and said to him, Rabbi, we know that you are a teacher come from God.",
        "Jesus answered him, Most certainly, I tell you, unless one is born anew, he can't see God's Kingdom."
    ]

    func testCleanReadingFinishes() {
        var r = ReadAlong(verses: verses)
        r.update(transcript: verses.joined(separator: " "))
        XCTAssertTrue(r.finished)
        XCTAssertEqual(r.coverage, 1, accuracy: 0.001)
    }

    func testMisheardNameAndSkippedWordsKeepMoving() {
        var r = ReadAlong(verses: [verses[0]])
        r.update(transcript: "now there was a man of the pharisee named nick a deemus a ruler of jews")
        XCTAssertTrue(r.finished)
        XCTAssertGreaterThan(r.coverage, 0.8)
    }

    func testPartialResultsDoNotRunAhead() {
        var r = ReadAlong(verses: verses)
        r.update(transcript: "now there was")
        XCTAssertEqual(r.cursor, 3)
        r.update(transcript: "now there was a man")
        XCTAssertEqual(r.cursor, 5)
        r.update(transcript: "now there was a man")
        XCTAssertEqual(r.cursor, 5)
    }

    func testSegmentsContinueWhereTheLastEnded() {
        var r = ReadAlong(verses: verses)
        r.update(transcript: verses[0])
        r.beginSegment()
        r.update(transcript: verses[1])
        XCTAssertEqual(r.currentVerse, 3)
        XCTAssertGreaterThan(r.coverage, 0.6)
    }

    func testJumpingAheadAVerseReanchors() {
        var r = ReadAlong(verses: verses)
        r.update(transcript: "now there was a man of the pharisees jesus answered him most certainly I tell you")
        XCTAssertEqual(r.currentVerse, 3)
        XCTAssertNotNil(r.firstMissed)
    }

    func testRecognizerStartingOverKeepsProgress() {
        var r = ReadAlong(verses: verses)
        r.update(transcript: "now there was a man of the pharisees named nicodemus")
        XCTAssertEqual(r.cursor, 10)
        // After a pause the recognizer may send only the new words.
        r.update(transcript: "a ruler of the jews")
        XCTAssertEqual(r.cursor, 15)
        XCTAssertTrue(r.heardAll.contains(0))
        XCTAssertEqual(r.heardAll.count, 15)
    }

    func testShortWordsDoNotPullAhead() {
        var r = ReadAlong(verses: ["A man went to the city and the king was in the palace of the land"])
        r.update(transcript: "a man went")
        r.update(transcript: "a man went and")
        XCTAssertEqual(r.cursor, 3)
    }

    func testRestoreBringsBackProgress() {
        var r = ReadAlong(verses: verses)
        r.restore(heard: [0, 1, 2, 3], cursor: 4)
        r.update(transcript: "man of the")
        XCTAssertEqual(r.cursor, 7)
        XCTAssertEqual(r.heardAll.count, 7)
    }

    func testNumbersMatchSpokenWords() {
        XCTAssertEqual(ReadAlong.key("12"), ReadAlong.key("twelve"))
        XCTAssertTrue(ReadAlong.close("pharisee", "pharisees"))
        XCTAssertFalse(ReadAlong.close("man", "god"))
    }
}

final class AchievementTests: XCTestCase {
    func record(_ day: String, _ book: String, _ chapter: Int, score: Int = 5, reflection: String = "") -> DayRecord {
        DayRecord(dayKey: day, ref: ChapterRef(book: book, chapter: chapter), title: "", readMode: .paper, reflectMode: .typed,
                  reflection: reflection, score: score, total: 5, completedAt: DayKey.date(from: day)!.addingTimeInterval(12 * 3600),
                  readingSeconds: 300, fromPlan: true)
    }

    func stats(_ records: [DayRecord], usage: [String: Int] = [:], watched: Set<String> = [], today: String = "2026-04-20") -> AchievementStats {
        AchievementStats(records: records, passUses: [], usage: usage, watchedDays: watched, todayKey: today)
    }

    func find(_ id: String) -> Achievement { Achievements.all.first { $0.id == id }! }

    func testIdsAreUniqueAndEveryTrophyHasArt() {
        XCTAssertEqual(Set(Achievements.all.map(\.id)).count, Achievements.all.count)
        XCTAssertEqual(Set(Achievements.all.map(\.art)).count, Achievements.all.count)
        XCTAssertGreaterThan(Achievements.all.count, 100)
    }

    func testEaster() {
        XCTAssertEqual(AchievementStats.easter(2026), "2026-04-05")
        XCTAssertEqual(AchievementStats.easter(2027), "2027-03-28")
    }

    func testJourneyNeedsTheWindow() {
        let signs = find("journey.mountain")
        let spread = stats([record("2026-04-01", "MAT", 5), record("2026-04-02", "MAT", 6), record("2026-04-09", "MAT", 7)])
        XCTAssertEqual(signs.progress(spread), 2)
        XCTAssertFalse(signs.done(spread))
        let tight = stats([record("2026-04-01", "MAT", 5), record("2026-04-02", "MAT", 6), record("2026-04-03", "MAT", 7)])
        XCTAssertTrue(signs.done(tight))
    }

    func testEasterReadingAndStreaks() {
        let s = stats([record("2026-04-04", "JHN", 19), record("2026-04-05", "JHN", 20), record("2026-04-06", "JHN", 21)])
        XCTAssertTrue(find("holy.easter").done(s))
        XCTAssertTrue(find("streak.3").done(s))
        XCTAssertFalse(find("holy.friday").done(s))
    }

    func testScreenTimeCountsOnlyFinishedWatchedDays() {
        let watched: Set<String> = ["2026-04-17", "2026-04-18", "2026-04-19", "2026-04-20"]
        let s = stats([], usage: ["2026-04-18": 60, "2026-04-19": 15], watched: watched)
        XCTAssertEqual(s.daysUnder(60).count, 2) // the 17th had no usage, the 19th stayed under an hour, today is not finished
        XCTAssertEqual(s.daysUnder(15).count, 1)
    }

    func testPerfectWeekAndBooks() {
        let week = (1...7).map { record(String(format: "2026-04-%02d", $0), "PHP", min($0, 4)) }
        let s = stats(week)
        XCTAssertTrue(find("quiz.week").done(s))
        XCTAssertEqual(s.booksDone(["PHP"]), 1)
        XCTAssertFalse(find("quiz.scribe").done(s))
    }
}

final class ReminderTests: XCTestCase {
    func input(readToday: Bool, streak: Int, last: String?) -> Reminders.Input {
        Reminders.Input(todayKey: "2026-09-14", readToday: readToday, streak: streak, lastReadKey: last, totalChapters: 40,
                        chapter: "John 4", title: "Living Water at the Well", plan: "John", planLeft: 17, lockedApps: 3,
                        nextTrophy: (name: "Month of Light", left: 2), weekday: 2)
    }

    func testReadTodaySkipsTonightAndKeepsTomorrowsStreak() {
        let plan = Reminders.plan(input(readToday: true, streak: 12, last: "2026-09-14"))
        XCTAssertNil(plan.first { $0.offset == 0 })
        let tomorrow = plan.first { $0.offset == 1 }!.context
        XCTAssertEqual(tomorrow.streak, 12)
        XCTAssertEqual(tomorrow.next, 13)
        let dayAfter = plan.first { $0.offset == 2 }!.context
        XCTAssertEqual(dayAfter.kind, .freshStart)
        XCTAssertEqual(plan.last!.context.kind, .lastNudge)
    }

    func testNotReadTodayKeepsStreakTonight() {
        let plan = Reminders.plan(input(readToday: false, streak: 6, last: "2026-09-13"))
        let tonight = plan.first { $0.offset == 0 }!.context
        XCTAssertEqual(tonight.kind, .milestone) // day 7 is a milestone
        XCTAssertEqual(tonight.next, 7)
        XCTAssertEqual(plan.first { $0.offset == 3 }!.context.kind, .comeBack)
        XCTAssertEqual(plan.first { $0.offset == 3 }!.context.days, 4)
    }

    func testNeverStarted() {
        let plan = Reminders.plan(input(readToday: false, streak: 0, last: nil))
        XCTAssertTrue(plan.allSatisfy { $0.context.kind == .neverStarted })
    }

    func testEveryTemplateFillsAndHasNoDashes() {
        var c = Reminders.Context(kind: .keepStreak)
        c.streak = 1; c.next = 2; c.days = 3; c.chapter = "John 4"; c.title = "Living Water"; c.plan = "John"
        c.left = 1; c.apps = 1; c.trophy = "Month of Light"; c.total = 1; c.trophyLeft = 2
        for tone in ReminderTone.allCases {
            c.tone = tone
            for kind in Reminders.Kind.allCases {
                let list = Reminders.templates(tone)[kind] ?? []
                XCTAssertFalse(list.isEmpty, kind.rawValue)
                for t in list {
                    for text in [Reminders.fill(t.title, c), Reminders.fill(t.body, c)] {
                        XCTAssertFalse(text.contains("{"), text)
                        XCTAssertFalse(text.contains("-") || text.contains("\u{2014}") || text.contains("\u{2013}"), text)
                        XCTAssertFalse(text.contains("1 days") || text.contains("1 chapters") || text.contains("1 apps") || text.contains("1 app are"), text)
                    }
                }
            }
        }
    }

    func testGentleHasNoEmojiOrStreakPressure() {
        let pressure = ["at risk", "break the chain", "misses you", "Say less", "seen things", "o'clock"]
        for (_, list) in Reminders.templates(.gentle) {
            for t in list {
                for text in [t.title, t.body] {
                    XCTAssertFalse(text.unicodeScalars.contains { $0.properties.isEmojiPresentation }, text)
                    for word in pressure { XCTAssertFalse(text.localizedCaseInsensitiveContains(word), text) }
                }
            }
        }
        for (_, list) in Reminders.templates(.playful) {
            for t in list {
                for word in pressure { XCTAssertFalse((t.title + t.body).localizedCaseInsensitiveContains(word), t.title) }
            }
        }
    }

    func testMorningReminderNeverSaysTonight() {
        for tone in ReminderTone.allCases {
            for kind in Reminders.Kind.allCases {
                for t in Reminders.candidates(kind, tone: tone, hour: 6) {
                    let text = (t.title + " " + t.body).lowercased()
                    XCTAssertFalse(text.contains("tonight") || text.contains("before bed") || text.contains("big night"), t.title)
                }
                for t in Reminders.candidates(kind, tone: tone, hour: 20) {
                    XCTAssertFalse((t.title + " " + t.body).lowercased().contains("morning"), t.title)
                }
            }
        }
    }

    func testTrophyLeftAndDeadlineFill() {
        var c = Reminders.Context(kind: .trophyClose)
        c.trophy = "Month of Light"; c.left = 18; c.trophyLeft = 2; c.chapter = "John 4"; c.apps = 1
        c.resetsAtMidnight = false
        XCTAssertEqual(Reminders.fill("Just {trophyLeft} more", c), "Just 2 more")
        XCTAssertEqual(Reminders.fill("{appsWaiting} on you", c), "1 app is waiting on you")
        XCTAssertEqual(Reminders.fill("Read {deadline}", c), "Read before your day resets")
        let planned = Reminders.plan(input(readToday: false, streak: 6, last: "2026-09-13"))
        XCTAssertEqual(planned.first!.context.trophyLeft, 2)
    }
}

final class ReviewTests: XCTestCase {
    func q(_ chapter: String, _ n: Int) -> Question {
        Question(t: .tf, d: n % 3 + 1, v: 1, q: "Q\(n)", answerBool: true, id: "\(chapter).\(n)")
    }

    func testReviewSpreadsAcrossChaptersAndRotates() {
        var g = SeededGenerator(seed: 7)
        let banks = [("A", (0..<6).map { q("A", $0) }), ("B", (0..<6).map { q("B", $0) })]
        let first = QuizEngine.review(banks: banks, total: 4, asked: [:], using: &g)
        XCTAssertEqual(first.items.count, 4)
        XCTAssertEqual(first.items.filter { $0.id.hasPrefix("A.") }.count, 2)
        let second = QuizEngine.review(banks: banks, total: 4, asked: first.asked, using: &g)
        XCTAssertTrue(Set(second.items.map(\.id)).isDisjoint(with: Set(first.items.map(\.id))))
        let third = QuizEngine.review(banks: banks, total: 4, asked: second.asked, using: &g)
        XCTAssertEqual(third.items.count, 4)
        // Every question has now been used once, so the next review starts over instead of coming up short.
        let fourth = QuizEngine.review(banks: banks, total: 4, asked: third.asked, using: &g)
        XCTAssertEqual(fourth.items.count, 4)
    }

    func testReviewTrophiesCountChaptersBooksAndPerfectExams() {
        let read = (1...4).map { DayRecord(dayKey: "2026-09-0\($0)", ref: ChapterRef(book: "PHM", chapter: 1), title: "Philemon 1",
                                          readMode: .paper, reflectMode: .typed, reflection: "", score: 3, total: 3,
                                          completedAt: Date(), readingSeconds: 60, fromPlan: true) }
        let reviews = [ReviewRecord(scope: "PHM.1", chapterIDs: ["PHM.1"], score: 4, total: 5, completedAt: Date()),
                       ReviewRecord(scope: "PHM", chapterIDs: ["PHM.1"], score: 10, total: 10, completedAt: Date()),
                       ReviewRecord(scope: "JHN", chapterIDs: ["JHN.1", "JHN.2"], score: 10, total: 10, completedAt: Date())]
        let s = AchievementStats(records: read, passUses: [], usage: [:], watchedDays: [], todayKey: "2026-09-04", reviews: reviews)
        XCTAssertEqual(s.reviewedChapters.count, 3)
        XCTAssertEqual(s.perfectBookReviews, 1)
        XCTAssertEqual(s.booksFullyReviewed, 1)
    }
}

final class LockScheduleTests: XCTestCase {
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
        l.id = "night"
        l.name = "Night"
        l.policy = policy
        l.appCount = 3
        return l
    }

    func testReadingOpensALimitedLockWithoutUsingAnUnlock() {
        var limited = lock(.limited)
        limited.limit = 1
        let noon = date(12, 12)
        var today = TodayState(dayKey: "2026-09-12")
        today.readingDone = true
        today.unlocks[limited.id] = LockLogic.opened(LockDay(), until: noon.addingTimeInterval(600), spendsUnlock: false)
        XCTAssertEqual(today.day(limited.id).count, 0)
        XCTAssertEqual(LockLogic.state(limited, today: today, now: noon, calendar: cal), .open)
        // After the reading's unlock ends, the one daily unlock is still there.
        XCTAssertEqual(LockLogic.state(limited, today: today, now: noon.addingTimeInterval(700), calendar: cal), .needsTap)
        today.unlocks[limited.id] = LockLogic.opened(today.day(limited.id), until: noon.addingTimeInterval(1400), spendsUnlock: true)
        XCTAssertEqual(today.day(limited.id).count, 1)
        XCTAssertEqual(LockLogic.state(limited, today: today, now: noon.addingTimeInterval(1500), calendar: cal), .usedUp)
    }

    func testStrictLocksSayWhenTheyOpenAgain() {
        var strict = lock(.strict)
        XCTAssertNil(LockLogic.reopens(strict, now: date(11, 12), calendar: cal))
        XCTAssertNil(LockLogic.reopenPhrase(strict, now: date(11, 12), calendar: cal))
        // Sept 11 2026 is a Friday. A weekday lock opens again tomorrow, Saturday.
        strict.days = [2, 3, 4, 5, 6]
        XCTAssertEqual(LockLogic.reopens(strict, now: date(11, 12), calendar: cal), date(12, 0))
        XCTAssertEqual(LockLogic.reopenPhrase(strict, now: date(11, 12), calendar: cal), "tomorrow")
        // Wednesday Sept 9, every day but Sunday: opens again Sunday.
        strict.days = [2, 3, 4, 5, 6, 7]
        XCTAssertEqual(LockLogic.reopens(strict, now: date(9, 12), calendar: cal), date(13, 0))
        XCTAssertEqual(LockLogic.reopenPhrase(strict, now: date(9, 12), calendar: cal), "Sunday")
        strict.allDay = false
        strict.start = TimeOfDay(hour: 22, minute: 0)
        strict.end = TimeOfDay(hour: 6, minute: 0)
        XCTAssertEqual(LockLogic.reopens(strict, now: date(9, 23), calendar: cal), date(10, 6))
        XCTAssertTrue(LockLogic.reopenPhrase(strict, now: date(9, 23), calendar: cal)?.hasPrefix("at ") == true)
    }

    func testOpenOnlyHoursLockTheRestOfTheDay() {
        var evenings = lock(.questionEach)
        evenings.allDay = false
        evenings.openWindow = true
        // Open 6 PM to 9 PM is stored as locked 9 PM to 6 PM.
        evenings.start = TimeOfDay(hour: 21, minute: 0)
        evenings.end = TimeOfDay(hour: 18, minute: 0)
        XCTAssertTrue(LockLogic.isActive(evenings, now: date(12, 12), calendar: cal))
        XCTAssertFalse(LockLogic.isActive(evenings, now: date(12, 19), calendar: cal))
        XCTAssertTrue(LockLogic.isActive(evenings, now: date(12, 22), calendar: cal))
        XCTAssertTrue(LockLogic.isActive(evenings, now: date(13, 3), calendar: cal))
        XCTAssertTrue(evenings.hoursLabel.hasPrefix("Open "))
        XCTAssertEqual(1440 - evenings.windowMinutes, 180)
    }

    func testOvernightLockKeepsItsUnlocksAcrossMidnight() {
        var night = lock(.limited)
        night.limit = 3
        night.rewardSeconds = LockSet.untilEnd
        night.allDay = false
        night.start = TimeOfDay(hour: 21, minute: 0)
        night.end = TimeOfDay(hour: 7, minute: 0)

        // Read and unlocked at 9:30 PM on Saturday Sept 12, until the lock ends at 7 AM.
        let unlockedAt = date(12, 21, 30)
        let end = LockLogic.rewardEnd(night, now: unlockedAt, calendar: cal)
        XCTAssertEqual(end, date(13, 7))
        var evening = TodayState(dayKey: "2026-09-12")
        evening.readingDone = true
        evening.unlocks[night.id] = LockLogic.opened(LockDay(), until: end, spendsUnlock: true)

        // Past midnight the app has a fresh day, but the lock still belongs to the evening it started.
        let fresh = TodayState(dayKey: "2026-09-13")
        let halfPastMidnight = date(13, 0, 30)
        XCTAssertTrue(LockLogic.usesPreviousDay(night, today: fresh, yesterday: evening, now: halfPastMidnight, calendar: cal))
        XCTAssertEqual(LockLogic.state(night, today: fresh, yesterday: evening, now: halfPastMidnight, calendar: cal), .open)
        XCTAssertEqual(LockLogic.state(night, today: fresh, yesterday: nil, now: halfPastMidnight, calendar: cal), .needsReading)

        // The count carries too: 3 used in the evening means none left after midnight.
        var used = evening
        var day = LockDay()
        day.count = 3
        used.unlocks[night.id] = day
        XCTAssertEqual(LockLogic.state(night, today: fresh, yesterday: used, now: halfPastMidnight, calendar: cal), .usedUp)

        // Once the window ends, the new day is used.
        XCTAssertFalse(LockLogic.usesPreviousDay(night, today: fresh, yesterday: used, now: date(13, 12), calendar: cal))
        XCTAssertEqual(LockLogic.state(night, today: fresh, yesterday: used, now: date(13, 22), calendar: cal), .needsReading)
    }

    func testPasscodeWaitsAfterWrongTries() {
        XCTAssertEqual(Passcode.wait(afterFailures: 4), 0)
        XCTAssertEqual(Passcode.wait(afterFailures: 5), 60)
        XCTAssertEqual(Passcode.wait(afterFailures: 9), 0)
        XCTAssertEqual(Passcode.wait(afterFailures: 10), 900)
        XCTAssertEqual(Passcode.wait(afterFailures: 15), 900)
    }

    func testShortUnlocksMigrateToFiveMinutes() throws {
        var old = LockSet()
        old.rewardSeconds = 30
        let data = try JSONEncoder().encode(old)
        XCTAssertEqual(try JSONDecoder().decode(LockSet.self, from: data).rewardSeconds, 300)
        XCTAssertFalse(LockSet.rewardChoices.contains(30))
    }
}

final class TrustedClockTests: XCTestCase {
    func testChangingTheClockDoesNotMoveTime() {
        let anchor: TimeInterval = 1_800_000_000
        let wall = Date(timeIntervalSince1970: anchor + 600)
        // Ten minutes really passed: the wall clock is trusted.
        XCTAssertEqual(TrustedClock.resolve(wall: wall, mono: 600, anchorWall: anchor, anchorMono: 0), wall)
        // The clock jumped three hours ahead while only ten minutes passed: the real ten minutes win.
        let jumped = Date(timeIntervalSince1970: anchor + 600 + 3 * 3600)
        XCTAssertEqual(TrustedClock.resolve(wall: jumped, mono: 600, anchorWall: anchor, anchorMono: 0), wall)
        // Set back an hour: still the real time.
        let back = Date(timeIntervalSince1970: anchor + 600 - 3600)
        XCTAssertEqual(TrustedClock.resolve(wall: back, mono: 600, anchorWall: anchor, anchorMono: 0), wall)
        // After a restart the monotonic clock starts over, so the wall clock is trusted again.
        XCTAssertEqual(TrustedClock.resolve(wall: jumped, mono: 5, anchorWall: anchor, anchorMono: 600), jumped)
    }
}
