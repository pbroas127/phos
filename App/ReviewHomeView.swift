import SwiftUI

/// Every way to review in one place: recent chapters, any book you have read, and past results. Reviews never open apps.
struct ReviewHomeView: View {
    @Environment(AppModel.self) private var model
    @State private var reviewing: ReviewRequest?

    var body: some View {
        let recent = model.recentReadChapters(limit: 10)
        let books = model.booksWithReadings()
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Review").font(Theme.serif(34)).foregroundStyle(Theme.ink)
                    Text("Quiz yourself on what you have read. Reviews count for trophies and never open your apps.")
                        .foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                }

                CardBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Quick review", systemImage: "bolt.fill").font(.headline).foregroundStyle(Theme.ink)
                        Text(recent.isEmpty
                             ? "Finish a chapter and it shows up here."
                             : "Ten questions from your last \(recent.count == 1 ? "chapter" : "\(recent.count) chapters").")
                            .font(.subheadline).foregroundStyle(Theme.dim)
                        if !recent.isEmpty {
                            Button("Start quick review") { reviewing = .recent(recent) }.buttonStyle(.phos)
                        }
                    }
                }

                if !books.isEmpty {
                    Eyebrow(text: "Books you have read")
                    VStack(spacing: 10) {
                        ForEach(books, id: \.id) { book in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(book.name).font(.headline).foregroundStyle(Theme.ink)
                                    Text(book.read == book.total ? "Finished · all \(book.total) chapters" : "\(book.read) of \(book.total) chapters read")
                                        .font(.caption).foregroundStyle(Theme.dim)
                                    ReviewLines(reviews: model.reviews.filter { $0.scope == book.id })
                                }
                                Spacer()
                                Button(book.read == book.total ? "Book exam" : "Review") {
                                    reviewing = .book(book.id, only: model.settings.allowReviewUnread ? nil : model.readIDs)
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.gold)
                                .buttonStyle(.borderless)
                            }
                            .padding(14)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line))
                        }
                    }
                }

                let past = model.reviews.sorted { $0.completedAt > $1.completedAt }.prefix(12)
                if !past.isEmpty {
                    Eyebrow(text: "Past reviews")
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(past)) { r in
                            HStack {
                                Text(ReviewRequest.title(for: r)).font(.subheadline).foregroundStyle(Theme.ink)
                                Spacer()
                                Text("\(r.score) of \(r.total)").font(.subheadline.monospacedDigit())
                                    .foregroundStyle(r.score == r.total ? Theme.gold : Theme.dim)
                                Text(r.completedAt.formatted(.dateTime.month(.abbreviated).day())).font(.caption).foregroundStyle(Theme.dim)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $reviewing) { ReviewFlow(request: $0).environment(model) }
    }
}

/// The way into reviews from the journal.
struct ReviewEntryCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationLink {
            ReviewHomeView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal").font(.title3).foregroundStyle(Theme.gold)
                    .frame(width: 40, height: 40).background(Theme.soft, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review").font(.headline).foregroundStyle(Theme.ink)
                    Text(model.reviews.isEmpty ? "Quiz yourself on chapters you have read" : "\(model.reviews.count) reviews so far")
                        .font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line))
        }
        .buttonStyle(.plain)
    }
}
