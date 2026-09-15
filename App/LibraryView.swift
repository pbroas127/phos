import SwiftUI

/// A chapter someone tapped, with the path it belongs to.
struct ChapterPick: Identifiable, Equatable {
    let planID: String
    let index: Int
    var id: String { "\(planID).\(index)" }
}

/// Every book and plan with how much has been read, and a saved place in each.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Called when a chapter should be read now.
    var onRead: (ChapterPick) -> Void
    @State private var open: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    continueSection
                    group("plans", "Reading plans", "Whole books and the whole Bible", ReadingPlans.curated)
                    ForEach(ReadingPlans.topicGroups) { g in group(g.id, g.title, g.subtitle, g.plans) }
                    group("ot", "Old Testament", "39 books, Genesis to Malachi", ReadingPlans.oldTestament.compactMap(ReadingPlans.bookPlan))
                    group("nt", "New Testament", "27 books, Matthew to Revelation", ReadingPlans.newTestament.compactMap(ReadingPlans.bookPlan))
                }
                .padding(20)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Books")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(for: String.self) { id in
                PathDetailView(planID: id, onRead: onRead)
            }
        }
    }

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Continue")
            let active = model.plan
            NavigationLink(value: active.id) {
                PathRow(plan: active, highlight: true)
            }
            .buttonStyle(.plain)
            if !model.planFinished {
                Button("Read \(BookNames.title(active.chapters[model.planPosition])) now") {
                    onRead(ChapterPick(planID: active.id, index: model.planPosition))
                }
                .buttonStyle(.phos)
            }
            ForEach(model.otherPathsInProgress.prefix(4)) { p in
                NavigationLink(value: p.id) { PathRow(plan: p) }.buttonStyle(.plain)
            }
        }
    }

    private func group(_ id: String, _ title: String, _ subtitle: String, _ plans: [ReadingPlan]) -> some View {
        let isOpen = open.contains(id)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    if isOpen { open.remove(id) } else { open.insert(id) }
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(Theme.serif(22)).foregroundStyle(Theme.ink)
                        Text("\(subtitle) · \(plans.count)").font(.caption).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    Image(systemName: "chevron.down").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.gold)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.vertical, 14).padding(.horizontal, 16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "Collapses the list" : "Shows the list")

            if isOpen {
                VStack(spacing: 0) {
                    ForEach(plans) { p in
                        NavigationLink(value: p.id) { PathRow(plan: p, compact: true) }
                            .buttonStyle(.plain)
                        if p.id != plans.last?.id { Divider().overlay(Theme.line).padding(.leading, 16) }
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))
            }
        }
    }
}

struct PathRow: View {
    @Environment(AppModel.self) private var model
    let plan: ReadingPlan
    var highlight = false
    var compact = false

    var body: some View {
        let read = model.readCount(plan)
        let pos = model.position(plan)
        let total = plan.chapters.count
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(plan.name).font(compact ? .body.weight(.semibold) : Theme.serif(22)).foregroundStyle(Theme.ink)
                    if plan.id == model.plan.id {
                        Text("ACTIVE").font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(Theme.gold)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Theme.soft, in: Capsule())
                    }
                }
                Text(subtitle(read: read, pos: pos, total: total)).font(.caption).foregroundStyle(Theme.dim)
                if read > 0 || pos > 0 {
                    ProgressBar(value: Double(read) / Double(max(1, total)), height: 4).frame(maxWidth: 220)
                }
            }
            Spacer()
            Text("\(read)/\(total)").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(read == total ? Theme.green : Theme.dim)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.line)
        }
        .padding(compact ? 14 : 18)
        .background(highlight ? Theme.card : Color.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(highlight ? Theme.gold : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
    }

    private func subtitle(read: Int, pos: Int, total: Int) -> String {
        if pos >= total { return read == total ? "Finished" : "Finished · \(read) of \(total) chapters read" }
        if pos == 0 && read == 0 { return plan.detail }
        let chapter = plan.chapters[pos]
        return "\(read) of \(total) read · next \(BookNames.title(chapter))"
    }
}

/// One book or plan: where you are, every chapter, and ways to reread, skip, or restart.
struct PathDetailView: View {
    @Environment(AppModel.self) private var model
    let planID: String
    var onRead: (ChapterPick) -> Void
    @State private var picked: ChapterPick?
    @State private var confirmRestart = false
    @State private var reviewing: ReviewRequest?

    var body: some View {
        let plan = ReadingPlans.plan(planID)
        let pos = model.position(plan)
        let read = model.readIDs
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(plan.name).font(Theme.serif(38)).foregroundStyle(Theme.ink)
                    Text("\(model.readCount(plan)) of \(plan.chapters.count) chapters read").foregroundStyle(Theme.dim)
                    ProgressBar(value: Double(model.readCount(plan)) / Double(max(1, plan.chapters.count)))
                }

                if pos < plan.chapters.count {
                    Button(pos == 0 ? "Start with \(BookNames.title(plan.chapters[0]))" : "Continue with \(BookNames.title(plan.chapters[pos]))") {
                        onRead(ChapterPick(planID: plan.id, index: pos))
                    }
                    .buttonStyle(.phos)
                } else {
                    CardBox(fill: Theme.soft) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("You finished \(plan.name).", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(Theme.ink)
                            if let book = plan.bookID {
                                Text("Take one quiz across the whole book. Review only, nothing unlocks.")
                                    .font(.footnote).foregroundStyle(Theme.dim)
                                Button("Review \(plan.name)") { reviewing = .book(book) }.buttonStyle(.phos)
                                ReviewLines(reviews: model.reviews.filter { $0.scope == book })
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    if model.plan.id != plan.id {
                        Button("Make active") { model.makeActive(plan.id) }.buttonStyle(.phosSecondary)
                    }
                    Button("Restart") { confirmRestart = true }.buttonStyle(.phosSecondary)
                }

                Eyebrow(text: "Tap any chapter")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: plan.bookID == nil ? 4 : 6), spacing: 8) {
                    ForEach(Array(plan.chapters.enumerated()), id: \.offset) { i, ref in
                        Button { picked = ChapterPick(planID: plan.id, index: i) } label: {
                            ChapterCell(label: plan.bookID == nil ? BookNames.title(ref) : "\(ref.chapter)",
                                        read: read.contains(ref.id), next: i == pos)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 16) {
                    legend(Theme.gold, "Read")
                    legend(Theme.card, "Not yet", ring: Theme.line)
                    legend(Theme.card, "Next", ring: Theme.gold)
                }
            }
            .padding(20)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $picked) { pick in
            ChapterActionSheet(pick: pick, onRead: { p in picked = nil; onRead(p) })
                .environment(model)
                .presentationDetents([.medium])
        }
        .sheet(item: $reviewing) { ReviewFlow(request: $0).environment(model) }
        .confirmationDialog("Restart \(plan.name)?", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Restart from chapter 1") { model.restart(plan.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your place goes back to the beginning. Chapters you already read stay in your journal and count.")
        }
    }

    private func legend(_ fill: Color, _ text: String, ring: Color = .clear) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4).fill(fill).frame(width: 14, height: 14)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(ring, lineWidth: 1.5))
            Text(text).font(.caption).foregroundStyle(Theme.dim)
        }
    }
}

struct ChapterCell: View {
    let label: String
    let read: Bool
    let next: Bool

    var body: some View {
        Text(label)
            .font(.subheadline.weight(next ? .bold : .medium))
            .lineLimit(1).minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(read ? Color.white : Theme.ink)
            .background(read ? Theme.gold : Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(next ? Theme.gold : Theme.line, lineWidth: next ? 2.5 : 1))
    }
}

/// What to do with one chapter: read it, make it the next one, and what that means for the path.
struct ChapterActionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let pick: ChapterPick
    var onRead: (ChapterPick) -> Void
    @State private var reviewing: ReviewRequest?

    var body: some View {
        let plan = ReadingPlans.plan(pick.planID)
        let ref = plan.chapters[pick.index]
        let pos = model.position(plan)
        let last = model.lastRead(ref)
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: plan.name)
                Text(BookNames.title(ref)).font(Theme.serif(34)).foregroundStyle(Theme.ink)
                Text(status(pos: pos, last: last)).font(.subheadline).foregroundStyle(Theme.dim).wrapLines()
            }
            Button(last == nil ? "Read \(BookNames.title(ref))" : "Read it again") { onRead(pick) }
                .buttonStyle(.phos)
            if model.canReview(ref) {
                Button("Quiz only") { reviewing = .chapter(ref) }.buttonStyle(.phosSecondary)
            }
            if pick.index != pos {
                Button("Make this my next chapter") {
                    model.setPosition(plan.id, pick.index)
                    dismiss()
                }
                .buttonStyle(.phosSecondary)
            }
            if pos < plan.chapters.count && pick.index != pos {
                Text("Your place stays at \(BookNames.title(plan.chapters[pos])) unless you choose otherwise after reading.")
                    .font(.caption).foregroundStyle(Theme.dim)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .background(Theme.paper.ignoresSafeArea())
        .sheet(item: $reviewing) { ReviewFlow(request: $0).environment(model) }
    }

    private func status(pos: Int, last: Date?) -> String {
        var parts: [String] = []
        if let last { parts.append("Read \(last.formatted(.dateTime.month(.abbreviated).day())).") }
        if pick.index == pos { parts.append("This is the next chapter in your path.") }
        else if pick.index < pos { parts.append("This is before your place, so it would be a reread.") }
        else { parts.append("This skips ahead of your place.") }
        return parts.joined(separator: " ")
    }
}

/// After a reading: where the path picks up, with the other sensible choice one tap away.
struct NextStepCard: View {
    @Environment(AppModel.self) private var model
    let after: PathLogic.After
    @State private var chosen: Int?

    var body: some View {
        let plan = ReadingPlans.plan(after.planID)
        let selected = chosen ?? after.position
        VStack(alignment: .leading, spacing: 10) {
            switch after.kind {
            case .onPath:
                Label("Next time: \(title(plan, after.position))", systemImage: "arrow.turn.down.right")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            case .finished:
                Label("You finished \(plan.name)!", systemImage: "checkmark.seal.fill")
                    .font(.headline).foregroundStyle(Theme.ink)
                Text("Pick your next book from the Books screen, or start this one again.")
                    .font(.footnote).foregroundStyle(Theme.dim)
                Button("Restart \(plan.name)") { model.restart(plan.id); chosen = 0 }
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.gold)
            case .reread, .skippedAhead:
                Text(after.kind == .reread ? "You went back to a chapter you'd already passed. Where should your path pick up?" : "You skipped ahead. Where should your path pick up?")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).wrapLines()
                option(plan, after.position, after.kind == .reread ? "Where I left off" : "Keep going from here", selected)
                if let alt = after.alternative {
                    option(plan, alt, after.kind == .reread ? "Keep going from here" : "Go back to where I was", selected)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.soft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func title(_ plan: ReadingPlan, _ i: Int) -> String {
        i < plan.chapters.count ? BookNames.title(plan.chapters[i]) : "Finished"
    }

    private func option(_ plan: ReadingPlan, _ index: Int, _ label: String, _ selected: Int) -> some View {
        Button {
            chosen = index
            model.setPosition(plan.id, index)
        } label: {
            HStack {
                Image(systemName: selected == index ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected == index ? Theme.gold : Theme.dim)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text("Next: \(title(plan, index))").font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer()
            }
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
