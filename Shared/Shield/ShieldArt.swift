import UIKit

/// The words on a locked app's screen.
struct ShieldCopy {
    var eyebrow: String
    var title: String
    /// The app name when the title starts with it, so long names can break cleanly.
    var appName: String?
    var body: String
    var isVerse: Bool
    var reference: String?
    var button: String
}

/// Draws the locked app screen as one image, so typography and spacing are ours instead of the system's.
enum ShieldArt {
    struct Palette {
        let background: UIColor
        let eyebrow: UIColor
        let title: UIColor
        let body: UIColor
        let reference: UIColor
        let buttonFill: UIColor
        let buttonLabel: UIColor
    }

    static func hex(_ v: UInt32) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    static func palette(_ theme: ShieldTheme) -> Palette {
        switch theme {
        case .dark:
            return Palette(background: hex(0x15120E), eyebrow: hex(0xD4A84B), title: hex(0xF6F1E7), body: hex(0xCFC6B6),
                           reference: hex(0xC9A04A), buttonFill: hex(0xD4A84B), buttonLabel: hex(0x15120E))
        case .light:
            return Palette(background: hex(0xFBF9F4), eyebrow: hex(0x8A6318), title: hex(0x221D17), body: hex(0x4A4238),
                           reference: hex(0x8A6318), buttonFill: hex(0x221D17), buttonLabel: hex(0xFBF9F4))
        }
    }

    static func copy(state: LockLogic.State, lock: LockSet?, app: String, snap: SharedSnapshot, now: Date = Date()) -> ShieldCopy {
        let chapter = snap.chapterTitle
        switch state {
        case .strict:
            let f = DateFormatter()
            f.timeStyle = .short
            let time = lock.map { f.string(from: LockLogic.activeEnd($0, now: now)) } ?? "later"
            return ShieldCopy(eyebrow: lock?.name ?? "Strict hours", title: "Rest now.", appName: nil,
                              body: "\(app) opens again at \(time).", isVerse: false, reference: nil, button: "Open Phos")
        case .usedUp:
            return ShieldCopy(eyebrow: "Daily limit reached", title: "Enough for today.", appName: nil,
                              body: "Unlocks reset at midnight. Rest in what you read.", isVerse: false, reference: nil, button: "Open Phos")
        case .needsQuestion:
            return ShieldCopy(eyebrow: "Almost there", title: "One question left.", appName: nil,
                              body: "Answer one question about \(chapter) to open \(app).", isVerse: false, reference: nil,
                              button: "Answer the question")
        case .needsTap:
            let reward = lock.map { LockSet.rewardLabel($0.rewardSeconds).lowercased() } ?? "a while"
            let forText = lock?.rewardSeconds == LockSet.untilEnd ? "until this lock ends" : "for \(reward)"
            return ShieldCopy(eyebrow: "Chapter read", title: "Well done.", appName: nil,
                              body: "You read \(chapter) today. \(app) opens \(forText).", isVerse: false, reference: nil,
                              button: app.count <= 14 ? "Unlock \(app)" : "Unlock")
        case .needsReading, .open, .inactive:
            switch snap.style {
            case .verse:
                return ShieldCopy(eyebrow: "Today · \(chapter)", title: "\(app) can wait.", appName: app,
                                  body: snap.verseText, isVerse: true, reference: snap.verseRef, button: "Read \(chapter)")
            case .streak:
                return ShieldCopy(eyebrow: snap.streak > 0 ? "\(snap.streak) day streak" : "Today · \(chapter)",
                                  title: snap.streak > 0 ? "Keep it going." : "Start today.", appName: nil,
                                  body: "Read \(chapter) to keep your streak and open \(app).", isVerse: false, reference: nil,
                                  button: "Read \(chapter)")
            case .quiet:
                return ShieldCopy(eyebrow: "Today · \(chapter)", title: "Read first.", appName: nil,
                                  body: "\(app) opens after \(chapter).", isVerse: false, reference: nil, button: "Read \(chapter)")
            }
        }
    }

    // MARK: Drawing

    static let width: CGFloat = 330
    static let textWidth: CGFloat = 290

    static func serif(_ size: CGFloat, _ weight: UIFont.Weight, italic: Bool = false) -> UIFont {
        var d = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        if let s = d.withDesign(.serif) { d = s }
        if italic, let i = d.withSymbolicTraits(.traitItalic) { d = i }
        return UIFont(descriptor: d, size: size)
    }

    private static func text(_ s: String, font: UIFont, color: UIColor, kern: CGFloat, lineHeight: CGFloat) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        p.minimumLineHeight = lineHeight
        p.maximumLineHeight = lineHeight
        p.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .kern: kern, .paragraphStyle: p])
    }

    private static func height(_ s: NSAttributedString, maxLines: Int, lineHeight: CGFloat) -> CGFloat {
        let r = s.boundingRect(with: CGSize(width: textWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return min(ceil(r.height), CGFloat(maxLines) * lineHeight)
    }

    /// Keeps titles to one clean line, or breaks after the app name. Never leaves one lonely word on line two.
    static func fitTitle(_ c: ShieldCopy) -> (text: String, size: CGFloat) {
        func w(_ s: String, _ size: CGFloat) -> CGFloat {
            (s as NSString).size(withAttributes: [.font: serif(size, .semibold), .kern: -0.4]).width
        }
        if w(c.title, 34) <= textWidth { return (c.title, 34) }
        if let app = c.appName, c.title.hasPrefix(app) {
            let rest = String(c.title.dropFirst(app.count)).trimmingCharacters(in: .whitespaces)
            if w(app, 34) <= textWidth { return (app + "\n" + rest, 34) }
            if w(app, 28) <= textWidth { return (app + "\n" + rest, 28) }
            return ("This app " + rest, 34)
        }
        return (c.title, 28)
    }

    static func render(_ c: ShieldCopy, theme: ShieldTheme, scale: CGFloat = 3) -> UIImage {
        let p = palette(theme)
        let emblem = UIImage(named: theme == .dark ? "EmblemDark" : "EmblemLight")
        let emblemWidth: CGFloat = 88
        let emblemHeight = emblem.map { emblemWidth * $0.size.height / max(1, $0.size.width) } ?? 0

        let eyebrow = text(c.eyebrow.uppercased(), font: .systemFont(ofSize: 12, weight: .semibold), color: p.eyebrow, kern: 1.5, lineHeight: 16)
        let fitted = fitTitle(c)
        let titleLine = fitted.size + 6
        let title = text(fitted.text, font: serif(fitted.size, .semibold), color: p.title, kern: -0.4, lineHeight: titleLine)
        let bodyLine: CGFloat = c.isVerse ? 28 : 24
        let body = c.isVerse
            ? text("“\(c.body)”", font: serif(20, .regular, italic: true), color: p.body, kern: 0, lineHeight: bodyLine)
            : text(c.body, font: .systemFont(ofSize: 17, weight: .regular), color: p.body, kern: 0, lineHeight: bodyLine)
        let reference = c.reference.map { text($0.uppercased(), font: .systemFont(ofSize: 13, weight: .semibold), color: p.reference, kern: 1, lineHeight: 18) }

        let eyebrowH = height(eyebrow, maxLines: 1, lineHeight: 16)
        let titleH = height(title, maxLines: 2, lineHeight: titleLine)
        let bodyH = height(body, maxLines: c.isVerse ? 4 : 3, lineHeight: bodyLine)
        let refH = reference.map { height($0, maxLines: 1, lineHeight: 18) } ?? 0
        let bottomPadding: CGFloat = 56 // ponytail: lifts the art above center; tune on device
        let total = emblemHeight + 28 + eyebrowH + 12 + titleH + 20 + bodyH + (reference == nil ? 0 : 16 + refH) + bottomPadding

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: ceil(total)), format: format).image { _ in
            var y: CGFloat = 0
            emblem?.draw(in: CGRect(x: (width - emblemWidth) / 2, y: y, width: emblemWidth, height: emblemHeight))
            y += emblemHeight + 28
            let x = (width - textWidth) / 2
            let options: NSStringDrawingOptions = [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
            eyebrow.draw(with: CGRect(x: x, y: y, width: textWidth, height: eyebrowH), options: options, context: nil)
            y += eyebrowH + 12
            title.draw(with: CGRect(x: x, y: y, width: textWidth, height: titleH), options: options, context: nil)
            y += titleH + 20
            body.draw(with: CGRect(x: x, y: y, width: textWidth, height: bodyH), options: options, context: nil)
            y += bodyH
            if let reference {
                y += 16
                reference.draw(with: CGRect(x: x, y: y, width: textWidth, height: refH), options: options, context: nil)
            }
        }
    }
}
