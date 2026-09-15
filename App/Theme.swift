import SwiftUI

/// Morning Prayer: warm white, gold, a book serif.
enum Theme {
    static let paper = dyn(light: 0xFBF9F4, dark: 0x17140F)
    static let card = dyn(light: 0xFFFFFF, dark: 0x1F1B15)
    static let ink = dyn(light: 0x221D17, dark: 0xF3EDE2)
    static let dim = dyn(light: 0x8A7F71, dark: 0xA89C8B)
    static let line = dyn(light: 0xECE5D8, dark: 0x3A3229)
    static let gold = dyn(light: 0xA87A22, dark: 0xE0AE4B)
    static let soft = dyn(light: 0xF3EBDB, dark: 0x241F18)
    static let red = dyn(light: 0xB23A2B, dark: 0xE5484D)
    static let green = dyn(light: 0x2F8A57, dark: 0x4CBF7A)

    /// One color for light and one for dark, resolved by the system as the appearance changes.
    static func dyn(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

struct Eyebrow: View {
    let text: String
    var color: Color = Theme.dim
    var body: some View {
        Text(text.uppercased()).font(.caption.weight(.semibold)).tracking(1).foregroundStyle(color)
    }
}

struct CardBox<Content: View>: View {
    var padding: CGFloat = 20
    var fill: Color = Theme.card
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.line, lineWidth: fill == Theme.card ? 1 : 0))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var kind: Kind = .primary
    enum Kind { case primary, secondary, quiet }
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(kind == .primary ? Color.white : (kind == .secondary ? Theme.ink : Theme.gold))
            .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }

    private var background: Color {
        switch kind {
        case .primary: return Theme.gold
        case .secondary: return Theme.soft
        case .quiet: return .clear
        }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var phos: PrimaryButtonStyle { PrimaryButtonStyle() }
    static var phosSecondary: PrimaryButtonStyle { PrimaryButtonStyle(kind: .secondary) }
    static var phosQuiet: PrimaryButtonStyle { PrimaryButtonStyle(kind: .quiet) }
}

struct ProgressBar: View {
    var value: Double
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                Capsule().fill(Theme.gold).frame(width: g.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.25), value: value)
    }
}

struct RingProgress<Inner: View>: View {
    var value: Double
    var lineWidth: CGFloat = 10
    @ViewBuilder var inner: Inner
    var body: some View {
        ZStack {
            Circle().stroke(Theme.line, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, value)))
                .stroke(Theme.gold, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: value)
            inner
        }
    }
}

/// Close button shown at the top of full screen flows.
struct FlowHeader: View {
    let title: String
    var subtitle: String? = nil
    var onBack: (() -> Void)? = nil
    var onClose: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold)).foregroundStyle(Theme.dim)
                        .frame(width: 36, height: 36).background(Theme.soft, in: Circle())
                }
                .accessibilityLabel("Back")
            }
            VStack(alignment: .leading, spacing: 2) {
                if let subtitle { Eyebrow(text: subtitle) }
                Text(title).font(Theme.serif(26)).foregroundStyle(Theme.ink)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(Theme.dim)
                    .frame(width: 36, height: 36).background(Theme.soft, in: Circle())
            }
            .accessibilityLabel("Close")
        }
    }
}

/// Verse text with the words of Jesus in red.
struct RedLetterText: View {
    let verse: String
    var number: Int? = nil
    var size: CGFloat = 19

    var body: some View {
        var text = Text("")
        if let number {
            text = Text("\(number) ").font(.system(size: size * 0.6, weight: .semibold)).foregroundColor(Theme.dim).baselineOffset(size * 0.35)
        }
        for seg in TextChecks.segments(verse) {
            text = text + Text(seg.text).foregroundColor(seg.red ? Theme.red : Theme.ink)
        }
        return text.font(Theme.serif(size, .regular)).lineSpacing(size * 0.35)
    }
}

extension Date {
    var shortTime: String { formatted(date: .omitted, time: .shortened) }
}

func countdownText(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds.rounded(.up)))
    return String(format: "%d:%02d", s / 60, s % 60)
}
