import SwiftUI

/// Runs a set of questions one at a time and reports the score and misses.
struct QuizRunner: View {
    let items: [QuizItem]
    var onAnswer: (Int, Int, [Question]) -> Void
    var onFinish: (Int, [Question]) -> Void
    var footnote = "The chapter is hidden until you finish"
    var footnoteIcon = "eye.slash"

    @State private var index: Int
    @State private var correct: Int
    @State private var missed: [Question]
    @State private var answered: Bool? = nil

    init(items: [QuizItem], startIndex: Int = 0, startCorrect: Int = 0, startMissed: [Question] = [],
         footnote: String = "The chapter is hidden until you finish", footnoteIcon: String = "eye.slash",
         onAnswer: @escaping (Int, Int, [Question]) -> Void = { _, _, _ in },
         onFinish: @escaping (Int, [Question]) -> Void) {
        self.items = items
        self.onAnswer = onAnswer
        self.onFinish = onFinish
        self.footnote = footnote
        self.footnoteIcon = footnoteIcon
        _index = State(initialValue: min(startIndex, max(items.count - 1, 0)))
        _correct = State(initialValue: startCorrect)
        _missed = State(initialValue: startMissed)
    }

    var body: some View {
        if items.isEmpty {
            Color.clear
        } else {
            let item = items[min(index, items.count - 1)]
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Eyebrow(text: "Question \(index + 1) of \(items.count)")
                    Spacer()
                    HStack(spacing: 5) {
                        ForEach(0..<items.count, id: \.self) { i in
                            Capsule().fill(i <= index ? Theme.gold : Theme.line).frame(width: i == index ? 22 : 8, height: 8)
                        }
                    }
                }
                QuestionView(item: item, locked: answered != nil) { isRight in
                    answered = isRight
                    if isRight { correct += 1 } else { missed.append(item.question) }
                    onAnswer(index + 1, correct, missed)
                }
                .id(item.id)

                if let answered {
                    Feedback(item: item, right: answered)
                    Button(index + 1 >= items.count ? "See result" : "Next question") {
                        if index + 1 >= items.count {
                            onFinish(correct, missed)
                        } else {
                            withAnimation { index += 1; self.answered = nil }
                        }
                    }
                    .buttonStyle(.phos)
                }
                Spacer(minLength: 0)
                Label(footnote, systemImage: footnoteIcon)
                    .font(.caption).foregroundStyle(Theme.dim).frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            }
        }
    }
}

struct Feedback: View {
    let item: QuizItem
    let right: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title2).foregroundStyle(right ? Theme.green : Theme.red)
            VStack(alignment: .leading, spacing: 4) {
                Text(right ? "Right" : "Not quite").font(.headline).foregroundStyle(Theme.ink)
                if !right {
                    Text(item.question.correctText).font(.subheadline).foregroundStyle(Theme.ink)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background((right ? Theme.green : Theme.red).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct QuestionView: View {
    let item: QuizItem
    let locked: Bool
    var onAnswer: (Bool) -> Void

    var body: some View {
        switch item.question.t {
        case .choice: ChoiceQuestion(item: item, locked: locked, onAnswer: onAnswer)
        case .blank: BlankQuestion(item: item, locked: locked, onAnswer: onAnswer)
        case .order: OrderQuestion(item: item, locked: locked, onAnswer: onAnswer)
        case .tf: TrueFalseQuestion(item: item, locked: locked, onAnswer: onAnswer)
        }
    }
}

struct OptionRow: View {
    let text: String
    let state: State
    enum State { case idle, selected, right, wrong }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .strokeBorder(border, lineWidth: state == .selected ? 6 : 1.5)
                .frame(width: 22, height: 22)
            Text(text).font(.body).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if state == .right { Image(systemName: "checkmark").foregroundStyle(Theme.green) }
            if state == .wrong { Image(systemName: "xmark").foregroundStyle(Theme.red) }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(minHeight: 56)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(border, lineWidth: state == .idle ? 1 : 2))
    }

    private var border: Color {
        switch state {
        case .idle: return Theme.line
        case .selected: return Theme.gold
        case .right: return Theme.green
        case .wrong: return Theme.red
        }
    }
}

struct ChoiceQuestion: View {
    let item: QuizItem
    let locked: Bool
    var onAnswer: (Bool) -> Void
    @State private var selected: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.question.q ?? "").font(Theme.serif(25)).foregroundStyle(Theme.ink).wrapLines()
            ForEach(item.choices, id: \.self) { choice in
                Button { if !locked { selected = choice } } label: {
                    OptionRow(text: choice, state: state(choice))
                }
                .buttonStyle(.plain)
            }
            if !locked {
                Button("Check") { if let s = selected { onAnswer(item.isCorrect(choice: s)) } }
                    .buttonStyle(.phos).disabled(selected == nil)
            }
        }
    }

    private func state(_ c: String) -> OptionRow.State {
        if locked {
            if item.isCorrect(choice: c) { return .right }
            return c == selected ? .wrong : .idle
        }
        return c == selected ? .selected : .idle
    }
}

struct BlankQuestion: View {
    let item: QuizItem
    let locked: Bool
    var onAnswer: (Bool) -> Void
    @State private var selected: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow(text: "Fill in the blank")
            sentence
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))
            FlowLayout(spacing: 10) {
                ForEach(item.choices, id: \.self) { phrase in
                    Button { if !locked { selected = phrase } } label: {
                        Text(phrase)
                            .font(.body.weight(.medium))
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .foregroundStyle(chipText(phrase))
                            .background(chipFill(phrase), in: Capsule())
                            .overlay(Capsule().stroke(chipBorder(phrase), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            if !locked {
                Button("Check") { if let s = selected { onAnswer(item.isCorrect(choice: s)) } }
                    .buttonStyle(.phos).disabled(selected == nil)
            }
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-demoData"), selected == nil { selected = item.question.answerText }
        }
    }

    private var sentence: some View {
        let parts = (item.question.q ?? "").components(separatedBy: "____")
        let fill = selected ?? "            "
        var t = Text(parts.first ?? "").foregroundColor(Theme.ink)
        t = t + Text(fill).foregroundColor(locked ? (item.isCorrect(choice: fill) ? Theme.green : Theme.red) : Theme.gold).underline(true, color: Theme.gold)
        if parts.count > 1 { t = t + Text(parts[1]).foregroundColor(Theme.ink) }
        return t.font(Theme.serif(21, .regular)).lineSpacing(6)
    }

    private func chipFill(_ p: String) -> Color { p == selected && !locked ? Theme.gold : Theme.card }
    private func chipText(_ p: String) -> Color { p == selected && !locked ? .white : Theme.ink }
    private func chipBorder(_ p: String) -> Color {
        if locked {
            if item.isCorrect(choice: p) { return Theme.green }
            return p == selected ? Theme.red : Theme.line
        }
        return p == selected ? Theme.gold : Theme.line
    }
}

struct OrderQuestion: View {
    let item: QuizItem
    let locked: Bool
    var onAnswer: (Bool) -> Void
    @State private var order: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Put these in the order they appear").font(Theme.serif(25)).foregroundStyle(Theme.ink)
            Text("Hold and drag a card, or use the arrows").font(.subheadline).foregroundStyle(Theme.dim)
            // Cards size to their text, so long events wrap instead of getting cut off.
            VStack(spacing: 10) {
                ForEach(Array(order.enumerated()), id: \.element) { i, text in
                    card(i, text)
                }
            }
            if !locked {
                Button("Check order") { onAnswer(item.isCorrect(order: order)) }.buttonStyle(.phos)
            }
        }
        .onAppear { if order.isEmpty { order = item.choices } }
    }

    private func card(_ i: Int, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text("\(i + 1)").font(Theme.serif(20)).foregroundStyle(rowColor(i, text)).frame(width: 22)
            Text(text).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !locked {
                VStack(spacing: 2) {
                    arrow("chevron.up", disabled: i == 0) { move(i, to: i - 1) }
                    arrow("chevron.down", disabled: i == order.count - 1) { move(i, to: i + 1) }
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line))
        .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 16, style: .continuous))
        .draggable(text)
        .dropDestination(for: String.self) { dropped, _ in
            guard !locked, let s = dropped.first, let from = order.firstIndex(of: s), let to = order.firstIndex(of: text), from != to else { return false }
            move(from, to: to)
            return true
        }
    }

    private func arrow(_ symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 30)
                .foregroundStyle(disabled ? Theme.line : Theme.gold)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func move(_ from: Int, to: Int) {
        guard !locked, order.indices.contains(from), order.indices.contains(to) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            let s = order.remove(at: from)
            order.insert(s, at: to)
        }
    }

    private func rowColor(_ i: Int, _ text: String) -> Color {
        guard locked else { return Theme.gold }
        let items = item.question.items ?? []
        return i < items.count && items[i] == text ? Theme.green : Theme.red
    }
}

struct TrueFalseQuestion: View {
    let item: QuizItem
    let locked: Bool
    var onAnswer: (Bool) -> Void
    @State private var picked: Bool?

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 14) {
                Eyebrow(text: "True or false")
                Text(item.question.q ?? "").font(Theme.serif(27)).foregroundStyle(Theme.ink).multilineTextAlignment(.center).wrapLines()
            }
            .padding(28)
            .frame(maxWidth: .infinity, minHeight: 240)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.line))
            .rotationEffect(.degrees(locked ? 0 : -1.2))
            HStack(spacing: 12) {
                answerButton(false)
                answerButton(true)
            }
        }
    }

    private func answerButton(_ value: Bool) -> some View {
        Button {
            guard !locked else { return }
            picked = value
            onAnswer(item.isCorrect(bool: value))
        } label: {
            Label(value ? "True" : "False", systemImage: value ? "checkmark" : "xmark")
        }
        .buttonStyle(PrimaryButtonStyle(kind: value ? .primary : .secondary))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(locked && picked == value ? (item.isCorrect(bool: value) ? Theme.green : Theme.red) : .clear, lineWidth: 3))
    }
}

/// Wraps chips onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
