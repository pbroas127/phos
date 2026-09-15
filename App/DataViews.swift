import CoreText
import DeviceActivity
import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

// MARK: Export

/// Turns the journal into a text file or a PDF someone can keep or share.
enum JournalExport {
    static func text(_ records: [DayRecord], reviews: [ReviewRecord]) -> String {
        var out = "Wick journal\nExported \(Date().formatted(date: .long, time: .shortened))\n\(records.count) readings\n"
        for r in records.sorted(by: { $0.completedAt < $1.completedAt }) {
            out += "\n\n\(r.title)"
            if let title = ChapterTitles.title(r.ref) { out += ", \(title)" }
            out += "\n\(r.completedAt.formatted(date: .complete, time: .shortened))"
            out += "\n\(r.readMode.title) · \(r.reflectMode.title) · \(r.score) of \(r.total) correct"
            let text = r.reflection.trimmingCharacters(in: .whitespacesAndNewlines)
            out += "\n\n" + (text.isEmpty ? "No reflection saved." : text)
            for v in reviews.filter({ $0.scope == r.ref.id }) {
                out += "\nReviewed \(v.completedAt.formatted(date: .abbreviated, time: .omitted)), \(v.score) of \(v.total)"
            }
        }
        return out + "\n"
    }

    static func textFile(_ records: [DayRecord], reviews: [ReviewRecord]) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Wick Journal.txt")
        do {
            try text(records, reviews: reviews).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch { return nil }
    }

    /// A letter size PDF with a title, then each reading with its date, details, and reflection.
    static func pdfFile(_ records: [DayRecord], reviews: [ReviewRecord]) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Wick Journal.pdf")
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 56
        let body = attributed(records, reviews: reviews)
        let setter = CTFramesetterCreateWithAttributedString(body as CFAttributedString)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        do {
            try renderer.writePDF(to: url) { ctx in
                var start = 0
                let length = body.length
                repeat {
                    ctx.beginPage()
                    let cg = ctx.cgContext
                    cg.saveGState()
                    cg.translateBy(x: 0, y: page.height)
                    cg.scaleBy(x: 1, y: -1)
                    let path = CGPath(rect: page.insetBy(dx: margin, dy: margin), transform: nil)
                    let frame = CTFramesetterCreateFrame(setter, CFRange(location: start, length: 0), path, nil)
                    CTFrameDraw(frame, cg)
                    cg.restoreGState()
                    let visible = CTFrameGetVisibleStringRange(frame)
                    if visible.length == 0 { break }
                    start += visible.length
                } while start < length
            }
            return url
        } catch { return nil }
    }

    private static func attributed(_ records: [DayRecord], reviews: [ReviewRecord]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let ink = UIColor(red: 0x22 / 255, green: 0x1D / 255, blue: 0x17 / 255, alpha: 1)
        let dim = UIColor(red: 0x8A / 255, green: 0x7F / 255, blue: 0x71 / 255, alpha: 1)
        let serif = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body).withDesign(.serif)
        func font(_ size: CGFloat, bold: Bool = false) -> UIFont {
            let base = serif.map { UIFont(descriptor: $0, size: size) } ?? .systemFont(ofSize: size)
            guard bold, let d = base.fontDescriptor.withSymbolicTraits(.traitBold) else { return base }
            return UIFont(descriptor: d, size: size)
        }
        func add(_ s: String, _ f: UIFont, _ color: UIColor, after: CGFloat) {
            let p = NSMutableParagraphStyle()
            p.paragraphSpacing = after
            p.lineSpacing = 2
            out.append(NSAttributedString(string: s + "\n", attributes: [.font: f, .foregroundColor: color, .paragraphStyle: p]))
        }
        add("Wick journal", font(28, bold: true), ink, after: 4)
        add("Exported \(Date().formatted(date: .long, time: .shortened)) · \(records.count) readings", .systemFont(ofSize: 11), dim, after: 24)
        for r in records.sorted(by: { $0.completedAt < $1.completedAt }) {
            add([r.title, ChapterTitles.title(r.ref)].compactMap { $0 }.joined(separator: ", "), font(17, bold: true), ink, after: 2)
            add("\(r.completedAt.formatted(date: .complete, time: .shortened)) · \(r.readMode.title) · \(r.score) of \(r.total) correct",
                .systemFont(ofSize: 10), dim, after: 8)
            let text = r.reflection.trimmingCharacters(in: .whitespacesAndNewlines)
            add(text.isEmpty ? "No reflection saved." : text, font(12), ink, after: 6)
            for v in reviews.filter({ $0.scope == r.ref.id }) {
                add("Reviewed \(v.completedAt.formatted(date: .abbreviated, time: .omitted)), \(v.score) of \(v.total)", .systemFont(ofSize: 10), dim, after: 2)
            }
            add("", .systemFont(ofSize: 8), ink, after: 14)
        }
        return out
    }
}

/// Export, backup, and delete, shown together in Settings.
struct DataSection: View {
    @Environment(AppModel.self) private var model
    @State private var exportURL: URL?
    @State private var making = false
    @State private var confirmDelete = false

    var body: some View {
        Section {
            BackupRow()
            Menu {
                Button { export(pdf: true) } label: { Label("As a PDF", systemImage: "doc.richtext") }
                Button { export(pdf: false) } label: { Label("As plain text", systemImage: "doc.plaintext") }
            } label: {
                Label(making ? "Preparing your journal" : "Export my journal", systemImage: "square.and.arrow.up")
                    .foregroundStyle(model.records.isEmpty ? Theme.dim : Theme.ink)
            }
            .disabled(model.records.isEmpty || making)
            Button(role: .destructive) { confirmDelete = true } label: {
                Label("Delete all my data", systemImage: "trash").foregroundStyle(Theme.red)
            }
        } header: {
            Text("Your data")
        } footer: {
            Text(model.records.isEmpty
                 ? "Your journal can be exported once you finish a chapter."
                 : "Export saves every reading and reflection as a file you can keep or share.")
        }
        .sheet(item: Binding(get: { exportURL.map(ExportFile.init) }, set: { if $0 == nil { exportURL = nil } })) { file in
            ExportShareSheet(url: file.url)
        }
        .sheet(isPresented: $confirmDelete) {
            DeleteDataSheet().environment(model)
        }
    }

    private func export(pdf: Bool) {
        making = true
        let records = model.records
        let reviews = model.reviews
        DispatchQueue.global(qos: .userInitiated).async {
            let url = pdf ? JournalExport.pdfFile(records, reviews: reviews) : JournalExport.textFile(records, reviews: reviews)
            DispatchQueue.main.async {
                making = false
                exportURL = url
            }
        }
    }
}

private struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

private struct ExportShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: Delete

/// Deleting everything takes three deliberate steps: read what goes, type DELETE, then confirm once more.
/// Protected locks must be unprotected first, so this can never be used to get around a lock.
struct DeleteDataSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var includeCloud = true
    @State private var includeVoices = false
    @State private var finalCheck = false
    @FocusState private var focused: Bool

    private var protectedLocks: [LockSet] { model.settings.lockSets.filter { $0.protection.kind != .none } }
    private var ready: Bool { typed.trimmingCharacters(in: .whitespaces).uppercased() == "DELETE" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 40)).foregroundStyle(Theme.red)
                    Text("Delete all your data?").font(Theme.serif(30)).foregroundStyle(Theme.ink)
                    if !protectedLocks.isEmpty {
                        blocked
                    } else {
                        details
                    }
                }
                .padding(24)
            }
            .background(Theme.paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .confirmationDialog("This cannot be undone", isPresented: $finalCheck, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) {
                model.deleteAllData(includeCloud: includeCloud, includeVoices: includeVoices)
                dismiss()
            }
            Button("Keep my data", role: .cancel) {}
        } message: {
            Text("Wick will start over like a new install.")
        }
    }

    private var blocked: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("These locks are protected, so deleting your data is turned off until their protection is removed. This keeps delete from becoming a way around a lock.")
                .foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            ForEach(protectedLocks) { lock in
                HStack {
                    Image(systemName: "lock.shield.fill").foregroundStyle(Theme.gold)
                    Text(lock.name).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(lock.protection.kind.title).font(.caption).foregroundStyle(Theme.dim)
                }
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Text("Open each lock in Settings, remove its protection, then come back.").font(.footnote).foregroundStyle(Theme.dim)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This removes everything Wick keeps on this iPhone:").foregroundStyle(Theme.dim)
            VStack(alignment: .leading, spacing: 8) {
                bullet("Your journal, reflections, and voice recordings")
                bullet("Streaks, trophies, and reviews")
                bullet("Reading plans and your place in each book")
                bullet("Every lock and schedule. Locked apps open right away.")
                bullet("Reminders and all settings")
            }
            if !model.records.isEmpty {
                Text("Want a copy first? Close this and use Export my journal.").font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink)
            }
            VStack(spacing: 0) {
                if CloudBackup.available {
                    Toggle("Also delete my iCloud backup", isOn: $includeCloud).padding(.vertical, 10)
                    Divider()
                }
                if VoiceCatalog.naturalSupported && KokoroModel.shared.ready {
                    Toggle("Also remove natural voices (312 MB)", isOn: $includeVoices).padding(.vertical, 10)
                }
            }
            .foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 8) {
                Text("Type DELETE to continue").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                TextField("DELETE", text: $typed)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(ready ? Theme.red : Theme.line))
                    .accessibilityLabel("Type DELETE to continue")
            }
            Button {
                focused = false
                finalCheck = true
            } label: {
                Text("Delete all my data").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(ready ? Theme.red : Theme.red.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(!ready)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(Theme.red).padding(.top, 3)
            Text(text).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension AppModel {
    /// Wipes Wick back to a fresh install. The sheet has already checked that no lock is protected.
    func deleteAllData(includeCloud: Bool, includeVoices: Bool) {
        guard !demo else { return }
        for lock in settings.lockSets { Blocker.clear(id: lock.id) }
        let center = DeviceActivityCenter()
        center.stopMonitoring()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        if includeCloud { CloudBackup.erase() }
        if includeVoices { KokoroModel.shared.remove() }
        let fm = FileManager.default
        try? fm.removeItem(at: SpeechRecorder.reflectionsDirectory)
        if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id),
           let files = try? fm.contentsOfDirectory(at: group, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix("widget_trophy_") { try? fm.removeItem(at: file) }
        }
        for key in store.defaults.dictionaryRepresentation().keys { store.defaults.removeObject(forKey: key) }
        for key in ["wick.backup.savedAt", "wick.backup.fingerprint"] { UserDefaults.standard.removeObject(forKey: key) }
        resetAfterDelete()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
