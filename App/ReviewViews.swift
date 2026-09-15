import SwiftUI

/// A quiz on chapters already read. It never opens apps or touches the streak. It counts for trophies and the journal.
struct ReviewFlow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: ReviewRequest
    @State private var items: [QuizItem] = []
    @State private var outcome: ReviewOutcome?

    var body: some View {
        VStack(spacing: 0) {
            FlowHeader(title: request.title, subtitle: outcome == nil ? "Review" : "Result") { dismiss() }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
            if let outcome {
                ReviewResult(request: request, outcome: outcome, again: {
                    self.outcome = nil
                    items = model.reviewItems(request)
                }, done: { dismiss() })
            } else {
                QuizRunner(items: items, footnote: "Review only. This does not open your apps.", footnoteIcon: "arrow.counterclockwise") { score, missed in
                    model.completeReview(request, score: score, total: items.count)
                    withAnimation { outcome = ReviewOutcome(score: score, total: items.count, missed: missed) }
                }
                .id(items.map(\.id).joined())
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .preferredColorScheme(.light)
        .onAppear { if items.isEmpty { items = model.reviewItems(request) } }
    }
}

struct ReviewOutcome: Equatable {
    let score: Int
    let total: Int
    let missed: [Question]
}

struct ReviewResult: View {
    let request: ReviewRequest
    let outcome: ReviewOutcome
    var again: () -> Void
    var done: () -> Void

    private var line: String {
        if outcome.total == 0 { return "No questions for this yet." }
        if outcome.score == outcome.total { return "Perfect. You know \(request.title) well." }
        if outcome.score * 10 >= outcome.total * 8 { return "Strong. A quick reread would make it perfect." }
        return "Worth another look. Check the verses below and try again."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Review")
                    Text("\(outcome.score) of \(outcome.total) correct").font(Theme.serif(32)).foregroundStyle(Theme.ink)
                    Text(line).foregroundStyle(Theme.dim).wrapLines()
                }
                if !outcome.missed.isEmpty {
                    Eyebrow(text: "Verses to look at")
                    ForEach(outcome.missed) { q in
                        CardBox(fill: Theme.card) {
                            VStack(alignment: .leading, spacing: 8) {
                                if let ref = request.chapter(of: q) {
                                    if let chapter = Bible.shared.chapter(ref), q.v <= chapter.verses.count {
                                        RedLetterText(verse: chapter.verses[q.v - 1], number: q.v, size: 17)
                                    }
                                    Text(BookNames.verseTitle(ref, q.v)).font(.caption).foregroundStyle(Theme.dim)
                                }
                                Text(q.correctText).font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink)
                            }
                        }
                    }
                }
                Button("Review again", action: again).buttonStyle(.phos)
                Button("Done", action: done).buttonStyle(.phosSecondary)
            }
            .padding(20)
        }
    }
}

/// The small "Reviewed Sep 20, 9 of 10" lines under a journal entry or on a book page.
struct ReviewLines: View {
    let reviews: [ReviewRecord]

    var body: some View {
        if !reviews.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(reviews.sorted { $0.completedAt > $1.completedAt }.prefix(3)) { r in
                    HStack(spacing: 6) {
                        Image(systemName: r.score == r.total ? "checkmark.seal.fill" : "arrow.counterclockwise")
                            .font(.caption2).foregroundStyle(r.score == r.total ? Theme.gold : Theme.dim)
                        Text("Reviewed \(r.completedAt.formatted(.dateTime.month(.abbreviated).day())), \(r.score) of \(r.total)")
                            .font(.caption).foregroundStyle(Theme.dim)
                    }
                }
            }
        }
    }
}
