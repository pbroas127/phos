import SwiftUI

/// The medal art for a trophy. Unearned medals are shown in soft grayscale.
struct TrophyMedal: View {
    let achievement: Achievement
    let earned: Bool
    var size: CGFloat = 84

    var body: some View {
        Group {
            if achievement.secret && !earned {
                Circle()
                    .fill(Theme.soft)
                    .overlay(Image(systemName: "questionmark").font(.system(size: size * 0.34, weight: .semibold)).foregroundStyle(Theme.dim))
                    .overlay(Circle().stroke(Theme.line, lineWidth: 2))
            } else if let image = UIImage(named: "trophy_\(achievement.art)") {
                Image(uiImage: image).resizable().scaledToFit()
                    .grayscale(earned ? 0 : 1)
                    .opacity(earned ? 1 : 0.38)
                    .shadow(color: earned ? Theme.gold.opacity(0.28) : .clear, radius: size * 0.1, y: size * 0.04)
            } else {
                Circle()
                    .fill(earned ? Theme.gold : Theme.soft)
                    .overlay(Image(systemName: "rosette").font(.system(size: size * 0.4)).foregroundStyle(earned ? .white : Theme.dim))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct TrophyScreen: View {
    @Environment(AppModel.self) private var model
    @State private var filter: Filter = .all
    @State private var selected: Achievement?

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", earned = "Earned", progress = "In progress"
        var id: String { rawValue }
    }

    var body: some View {
        let stats = model.stats
        let earnedCount = Achievements.all.filter { model.earned[$0.id] != nil }.count
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header(earned: earnedCount, total: Achievements.all.count)
                    Picker("Show", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    ForEach(Achievement.Group.allCases) { group in
                        let items = Achievements.all.filter { $0.group == group && include($0, stats) }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(group.title).font(Theme.serif(24)).foregroundStyle(Theme.ink)
                                        Text(group.subtitle).font(.subheadline).foregroundStyle(Theme.dim)
                                    }
                                    Spacer()
                                    let all = Achievements.all.filter { $0.group == group }
                                    Text("\(all.filter { model.earned[$0.id] != nil }.count) of \(all.count)")
                                        .font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.dim)
                                }
                                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)], spacing: 18) {
                                    ForEach(items) { a in
                                        Button { selected = a } label: { TrophyCell(achievement: a, stats: stats, earned: model.earned[a.id] != nil) }
                                            .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selected) { a in
                TrophyDetail(achievement: a).environment(model).presentationDetents([.medium, .large])
            }
        }
    }

    private func include(_ a: Achievement, _ stats: AchievementStats) -> Bool {
        switch filter {
        case .all: return true
        case .earned: return model.earned[a.id] != nil
        case .progress: return model.earned[a.id] == nil && a.progress(stats) > 0 && !a.secret
        }
    }

    private func header(earned: Int, total: Int) -> some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Theme.line, lineWidth: 8)
                Circle().trim(from: 0, to: Double(earned) / Double(max(total, 1)))
                    .stroke(Theme.gold, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "trophy.fill").font(.title2).foregroundStyle(Theme.gold)
            }
            .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Trophy room")
                Text("\(earned) of \(total) earned").font(Theme.serif(30)).foregroundStyle(Theme.ink)
                Text(earned == 0 ? "Finish a chapter to earn your first." : "Tap any medal to see how to earn it.")
                    .font(.subheadline).foregroundStyle(Theme.dim)
            }
        }
    }
}

struct TrophyCell: View {
    let achievement: Achievement
    let stats: AchievementStats
    let earned: Bool

    var body: some View {
        let hideName = achievement.secret && !earned
        VStack(spacing: 8) {
            TrophyMedal(achievement: achievement, earned: earned, size: 86)
            Text(hideName ? "Hidden" : achievement.name)
                .font(.footnote.weight(.semibold)).foregroundStyle(earned ? Theme.ink : Theme.dim)
                .multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if !earned && !hideName && achievement.goal > 1 {
                ProgressBar(value: achievement.fraction(stats), height: 4).frame(width: 64)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hideName ? "Hidden trophy" : "\(achievement.name), \(earned ? "earned" : "not earned yet")")
    }
}

struct TrophyDetail: View {
    @Environment(AppModel.self) private var model
    let achievement: Achievement
    @State private var shine = false

    var body: some View {
        let stats = model.stats
        let earnedAt = model.earned[achievement.id]
        let hide = achievement.secret && earnedAt == nil
        let pinned = model.settings.pinnedTrophies.contains(achievement.id)
        ScrollView {
            VStack(spacing: 16) {
                TrophyMedal(achievement: achievement, earned: earnedAt != nil, size: 190)
                    .scaleEffect(shine ? 1 : 0.9)
                    .padding(.top, 26)
                Eyebrow(text: achievement.group.title, color: Theme.gold)
                Text(hide ? "A hidden trophy" : achievement.name).font(Theme.serif(30)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                Text(hide ? "Keep reading. This one reveals itself when you find it." : achievement.detail)
                    .font(.body).foregroundStyle(Theme.dim).multilineTextAlignment(.center).padding(.horizontal, 24)
                if let earnedAt {
                    Label("Earned \(earnedAt.formatted(date: .long, time: .omitted))", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.green)
                } else if !hide {
                    VStack(spacing: 6) {
                        ProgressBar(value: achievement.fraction(stats), height: 8)
                        Text("\(achievement.progress(stats).formatted()) of \(achievement.goal.formatted())")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(Theme.dim)
                    }
                    .padding(.horizontal, 40)
                    Button(pinned ? "Stop tracking on Today" : "Track on Today") { model.togglePin(achievement) }
                        .buttonStyle(.phos).padding(.horizontal, 40).padding(.top, 6)
                }
            }
            .padding(.bottom, 30)
        }
        .background(Theme.paper.ignoresSafeArea())
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { shine = true } }
    }
}

/// Shown over the app when a trophy is earned.
struct TrophyCelebration: View {
    let achievement: Achievement
    let more: Int
    var onClose: () -> Void
    @State private var appear = false
    @State private var spin = false

    var body: some View {
        ZStack {
            Color(hex: 0x15120E).opacity(0.94).ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                ZStack {
                    RaysShape().fill(Theme.gold.opacity(0.18))
                        .frame(width: 360, height: 360)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                    TrophyMedal(achievement: achievement, earned: true, size: 210)
                        .scaleEffect(appear ? 1 : 0.3)
                        .opacity(appear ? 1 : 0)
                }
                Text("Trophy earned").font(.caption.weight(.semibold)).tracking(1.5).textCase(.uppercase).foregroundStyle(Color(hex: 0xD4A84B))
                Text(achievement.name).font(Theme.serif(34)).foregroundStyle(Color(hex: 0xF6F1E7)).multilineTextAlignment(.center)
                Text(achievement.detail).font(.body).foregroundStyle(Color(hex: 0xCFC6B6)).multilineTextAlignment(.center).padding(.horizontal, 32)
                if more > 0 {
                    Text("And \(more) more waiting in your trophy room").font(.subheadline).foregroundStyle(Color(hex: 0xCFC6B6))
                }
                Spacer()
                Button(action: onClose) {
                    Text("Keep going").font(.headline).foregroundStyle(Color(hex: 0x15120E))
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Color(hex: 0xD4A84B), in: Capsule())
                }
                .padding(.horizontal, 28).padding(.bottom, 20)
            }
        }
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.6, dampingFraction: 0.55)) { appear = true }
            withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}

private struct RaysShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let count = 16
        for i in 0..<count {
            let a0 = Double(i) / Double(count) * 2 * .pi
            let a1 = a0 + .pi / Double(count) * 0.55
            p.move(to: c)
            p.addLine(to: CGPoint(x: c.x + r * CGFloat(Foundation.cos(a0)), y: c.y + r * CGFloat(Foundation.sin(a0))))
            p.addLine(to: CGPoint(x: c.x + r * CGFloat(Foundation.cos(a1)), y: c.y + r * CGFloat(Foundation.sin(a1))))
            p.closeSubpath()
        }
        return p
    }
}

/// Trophies on the Today plan view: ones you are tracking, the closest to done, and recent wins.
struct TodayTrophies: View {
    @Environment(AppModel.self) private var model
    @State private var selected: Achievement?

    var body: some View {
        let stats = model.stats
        let pinned = model.settings.pinnedTrophies.compactMap { id in Achievements.all.first { $0.id == id && model.earned[id] == nil } }
        let close = Achievements.almost(stats, earned: Set(model.earned.keys), limit: 4).filter { a in !pinned.contains { $0.id == a.id } }
        let chasing = Array((pinned + close).prefix(3))
        let recent = Achievements.all.compactMap { a in model.earned[a.id].map { (a, $0) } }.sorted { $0.1 > $1.1 }.prefix(6).map(\.0)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your trophies").font(Theme.serif(24)).foregroundStyle(Theme.ink)
                Spacer()
                Button { model.tab = 3 } label: {
                    Label("Trophy room", systemImage: "trophy.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.soft, in: Capsule())
                        .foregroundStyle(Theme.ink)
                }
            }
            if chasing.isEmpty {
                Text("Finish today's chapter to start earning trophies.").font(.subheadline).foregroundStyle(Theme.dim)
            }
            ForEach(chasing) { a in
                Button { selected = a } label: { chaseRow(a, stats: stats, pinned: pinned.contains { $0.id == a.id }) }
                    .buttonStyle(.plain)
            }
            if !recent.isEmpty {
                Eyebrow(text: "Recently earned").padding(.top, 6)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Array(recent)) { a in
                            Button { selected = a } label: {
                                VStack(spacing: 6) {
                                    TrophyMedal(achievement: a, earned: true, size: 64)
                                    Text(a.name).font(.caption2.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1).frame(width: 78)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .sheet(item: $selected) { a in
            TrophyDetail(achievement: a).environment(model).presentationDetents([.medium, .large])
        }
    }

    private func chaseRow(_ a: Achievement, stats: AchievementStats, pinned: Bool) -> some View {
        HStack(spacing: 14) {
            TrophyMedal(achievement: a, earned: false, size: 58)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(a.name).font(.headline).foregroundStyle(Theme.ink)
                    if pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Theme.gold) }
                }
                Text(a.detail).font(.footnote).foregroundStyle(Theme.dim).lineLimit(2)
                HStack(spacing: 8) {
                    ProgressBar(value: a.fraction(stats), height: 5)
                    Text("\(a.progress(stats)) of \(a.goal)").font(.caption2.monospacedDigit()).foregroundStyle(Theme.dim).fixedSize()
                }
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))
    }
}
