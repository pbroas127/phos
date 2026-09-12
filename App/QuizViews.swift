import SwiftUI

/// Runs a set of questions one at a time and reports the score and misses.
struct QuizRunner: View {
    let items: [QuizItem]
    var onFinish: (Int, [Question]) -> Void

    @State private var index = 0
    @State private var correct = 0
    @State private var missed: [Question] = []
    @State private var answered: Bool? = nil

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
                Label("The chapter is hidden until you finish", systemImage: "eye.slash")
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
            Text("Drag to reorder").font(.subheadline).foregroundStyle(Theme.dim)
            List {
                ForEach(Array(order.enumerated()), id: \.element) { i, text in
                    HStack(spacing: 12) {
                        Text("\(i + 1)").font(Theme.serif(20)).foregroundStyle(rowColor(i, text)).frame(width: 22)
                        Text(text).foregroundStyle(Theme.ink)
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Theme.card)
                }
                .onMove { from, to in if !locked { order.move(fromOffsets: from, toOffset: to) } }
            }
            .listStyle(.plain)
            .scrollDisabled(true)
            .environment(\.editMode, .constant(locked ? .inactive : .active))
            .frame(height: CGFloat(order.count) * 64)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line))
            if !locked {
                Button("Check order") { onAnswer(item.isCorrect(order: order)) }.buttonStyle(.phos)
            }
        }
        .onAppear { if order.isEmpty { order = item.choices } }
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
