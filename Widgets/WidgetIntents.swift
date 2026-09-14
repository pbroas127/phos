import AppIntents
import WidgetKit

// MARK: Choices people make when they configure a widget

enum WidgetLook: String, AppEnum {
    case system, paper, ink, gold

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Look")
    static let caseDisplayRepresentations: [WidgetLook: DisplayRepresentation] = [
        .system: "Match the phone", .paper: "Paper", .ink: "Ink", .gold: "Gold on ink"
    ]
}

enum VerseSource: String, AppEnum {
    case daily, chapter

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Verse")
    static let caseDisplayRepresentations: [VerseSource: DisplayRepresentation] = [
        .daily: "Verse of the day", .chapter: "Key verse of today's chapter"
    ]
}

enum VerseType: String, AppEnum {
    case serif, rounded, mono

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Lettering")
    static let caseDisplayRepresentations: [VerseType: DisplayRepresentation] = [
        .serif: "Serif", .rounded: "Rounded", .mono: "Typewriter"
    ]
}

enum StreakStyle: String, AppEnum {
    case number, dots, ring

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Style")
    static let caseDisplayRepresentations: [StreakStyle: DisplayRepresentation] = [
        .number: "Big number", .dots: "Week dots", .ring: "Week ring"
    ]
}

enum GlanceInfo: String, AppEnum {
    case chapter, streak, verse, locks, plan, trophy

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Show")
    static let caseDisplayRepresentations: [GlanceInfo: DisplayRepresentation] = [
        .chapter: "Today's chapter", .streak: "Streak", .verse: "Verse", .locks: "Locked apps",
        .plan: "Plan progress", .trophy: "Next trophy"
    ]
}

enum TrophyPick: String, AppEnum {
    case closest, pinned, latest

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Trophies")
    static let caseDisplayRepresentations: [TrophyPick: DisplayRepresentation] = [
        .closest: "Closest to earning", .pinned: "Pinned first", .latest: "Last earned"
    ]
}

/// A lock group, so a widget can follow just one of them.
struct LockChoice: AppEntity {
    let id: String
    var name: String { id }

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Lock")
    static let defaultQuery = LockQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    struct LockQuery: EntityQuery {
        func entities(for ids: [String]) async throws -> [LockChoice] { ids.map { LockChoice(id: $0) } }
        func suggestedEntities() async throws -> [LockChoice] { SharedStore.shared.widgetData.locks.map { LockChoice(id: $0.name) } }
        func defaultResult() async -> LockChoice? { nil }
    }
}

// MARK: Configuration intents

struct TodayConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Today"
    static let description = IntentDescription("Choose what the widget shows around today's chapter.")

    @Parameter(title: "Look", default: .system) var look: WidgetLook
    @Parameter(title: "Show streak", default: true) var showStreak: Bool
    @Parameter(title: "Show chapter title", default: true) var showTitle: Bool
    @Parameter(title: "Show plan progress", default: true) var showPlan: Bool
    @Parameter(title: "Show locked apps", default: true) var showLocks: Bool
}

struct VerseConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Verse"
    static let description = IntentDescription("A verse to carry through the day. Tap the arrow for another.")

    @Parameter(title: "Look", default: .system) var look: WidgetLook
    @Parameter(title: "Verse", default: .daily) var source: VerseSource
    @Parameter(title: "Lettering", default: .serif) var type: VerseType
    @Parameter(title: "Shuffle button", default: true) var shuffle: Bool
}

struct MemoryConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Memory verse"
    static let description = IntentDescription("Only the reference shows. Say the verse, then tap to check.")

    @Parameter(title: "Look", default: .system) var look: WidgetLook
    @Parameter(title: "Verse", default: .daily) var source: VerseSource
}

struct StreakConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Streak"
    static let description = IntentDescription("Your reading streak and the last seven days.")

    @Parameter(title: "Look", default: .system) var look: WidgetLook
    @Parameter(title: "Style", default: .number) var style: StreakStyle
    @Parameter(title: "Show longest streak", default: true) var showLongest: Bool
    @Parameter(title: "Show chapters read", default: false) var showTotal: Bool
}

struct PlanConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Plan"
    static let description = IntentDescription("Where you are in your reading plan and what comes next.")

    @Parameter(title: "Look", default: .system) var look: WidgetLook
    @Parameter(title: "Show coming chapters", default: true) var showUpcoming: Bool
    @Parameter(title: "Show chapter titles", default: true) var showTitles: Bool
}

struct LocksConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Locks"
    static let description = IntentDescription("Which apps are locked and how many unlocks are left.")

    @Parameter(title: "Look", default: .system) var look: WidgetLook
    @Parameter(title: "Lock") var lock: LockChoice?
    @Parameter(title: "Show unlock dots", default: true) var showDots: Bool
}

struct TrophyConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Trophies"
    static let description = IntentDescription("The trophies you are closest to. Tap the arrows to see the next one.")

    @Parameter(title: "Look", default: .system) var look: WidgetLook
    @Parameter(title: "Trophies", default: .closest) var pick: TrophyPick
    @Parameter(title: "Show progress bar", default: true) var showProgress: Bool
}

struct GlanceConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Wick glance"
    static let description = IntentDescription("One thing from Wick on your Lock Screen.")

    @Parameter(title: "Show", default: .chapter) var info: GlanceInfo
}

// MARK: Buttons inside widgets

struct ShuffleVerseIntent: AppIntent {
    static let title: LocalizedStringResource = "Another verse"
    static let description = IntentDescription("Shows a different verse in the widget.")

    func perform() async throws -> some IntentResult {
        WidgetData.verseOffset += 1
        return .result()
    }
}

struct ToggleMemoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Reveal or hide the memory verse"

    func perform() async throws -> some IntentResult {
        WidgetData.memoryRevealed.toggle()
        return .result()
    }
}

struct NextTrophyIntent: AppIntent {
    static let title: LocalizedStringResource = "Next trophy"

    @Parameter(title: "Step", default: 1) var step: Int

    init() {}
    init(step: Int) { self.step = step }

    func perform() async throws -> some IntentResult {
        WidgetData.trophyOffset += step
        return .result()
    }
}
