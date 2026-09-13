import SwiftUI
import UIKit

/// Text view that refuses paste, drag and drop, Live Text scanning, and the three finger paste gesture.
final class NoPasteTextView: UITextView, UITextPasteDelegate, UITextDropDelegate {
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        pasteDelegate = self
        textDropDelegate = self
        textDragInteraction?.isEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        let name = NSStringFromSelector(action).lowercased()
        if name.contains("paste") || name.contains("capturetext") || name.contains("replace") { return false }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {}

    override var editingInteractionConfiguration: UIEditingInteractionConfiguration { .none }

    func textPasteConfigurationSupporting(_ textPasteConfigurationSupporting: UITextPasteConfigurationSupporting, transform item: UITextPasteItem) {
        item.setNoResult()
    }

    func textDroppableView(_ textDroppableView: UIView & UITextDroppable, proposalForDrop drop: UITextDropRequest) -> UITextDropProposal {
        UITextDropProposal(operation: .forbidden)
    }
}

struct NoPasteEditor: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var fontSize: CGFloat = 18
    var onBlocked: () -> Void = {}

    func makeUIView(context: Context) -> NoPasteTextView {
        let v = NoPasteTextView(frame: .zero, textContainer: nil)
        v.font = UIFont.systemFont(ofSize: fontSize)
        if let serif = UIFont.systemFont(ofSize: fontSize).fontDescriptor.withDesign(.serif) {
            v.font = UIFont(descriptor: serif, size: fontSize)
        }
        v.textColor = UIColor(Theme.ink)
        v.backgroundColor = .clear
        v.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        v.textContainer.lineFragmentPadding = 0
        v.autocorrectionType = .yes
        v.smartInsertDeleteType = .no
        v.delegate = context.coordinator
        v.text = text
        return v
    }

    func updateUIView(_ v: NoPasteTextView, context: Context) {
        if v.text != text { v.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NoPasteEditor
        init(_ p: NoPasteEditor) { parent = p }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Typing adds a character or two at a time. Big jumps come from paste style insertions.
            if TextChecks.wordCount(text) > 3 && text.count > 24 {
                parent.onBlocked()
                return false
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
    }
}

struct ReflectStep: View {
    @Environment(AppModel.self) private var model
    let ref: ChapterRef
    @Binding var mode: ReflectMode
    @Binding var text: String
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Picker("Reflection", selection: $mode) {
                ForEach(ReflectMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)

            switch mode {
            case .typed: TypeReflect(ref: ref, text: $text, onDone: onDone)
            case .spoken: SpeakReflect(ref: ref, text: $text, onDone: onDone)
            case .prompts: PromptsReflect(ref: ref, text: $text, onDone: onDone)
            }
        }
    }
}

/// Checks shared by every reflection style.
struct ReflectionGate {
    let ref: ChapterRef
    let text: String

    var chapterText: String { Bible.shared.plainText(ref) }

    var relevant: Bool {
        chapterText.isEmpty || TextChecks.isRelevant(reflection: text, chapterText: chapterText)
    }

    var offTopicMessage: String {
        "This does not sound like \(BookNames.title(ref)) yet. Mention a person, place, or idea from the chapter."
    }
}

struct TypeReflect: View {
    @Environment(AppModel.self) private var model
    let ref: ChapterRef
    @Binding var text: String
    var onDone: () -> Void
    @State private var notice: String?

    var body: some View {
        let rules = model.readingCheck
        let count = TextChecks.wordCount(text)
        let distinctNeeded = TextChecks.requiredDistinct(typedWords: rules.words)
        let distinctOK = TextChecks.distinctCount(text) >= distinctNeeded
        let enough = count >= rules.words
        VStack(alignment: .leading, spacing: 12) {
            Text("What stood out to you in \(BookNames.title(ref))?").font(Theme.serif(24)).foregroundStyle(Theme.ink)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Start typing. Paste is turned off.").font(Theme.serif(18, .regular)).foregroundStyle(Theme.dim.opacity(0.7)).padding(.top, 4)
                }
                NoPasteEditor(text: $text, placeholder: "", onBlocked: { notice = "Paste is turned off. Type it in your own words." })
            }
            .padding(16)
            .frame(maxHeight: .infinity)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))

            HStack {
                Label("Paste is off", systemImage: "doc.on.clipboard").font(.caption).foregroundStyle(Theme.dim)
                Spacer()
                Text("\(count) / \(rules.words) words").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(enough ? Theme.green : Theme.ink)
            }
            ProgressBar(value: Double(count) / Double(max(1, rules.words)))
            if let notice {
                Text(notice).font(.footnote).foregroundStyle(Theme.red)
            } else if enough && !distinctOK {
                Text("Try using more different words, at least \(distinctNeeded).").font(.footnote).foregroundStyle(Theme.red)
            }
            Button(enough ? "Continue to questions" : "Keep writing") {
                let gate = ReflectionGate(ref: ref, text: text)
                if gate.relevant { onDone() } else { notice = gate.offTopicMessage }
            }
            .buttonStyle(.phos)
            .disabled(!(enough && distinctOK))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .onChange(of: text) { _, _ in if notice?.hasPrefix("This does not") == true { notice = nil } }
    }
}

struct SpeakReflect: View {
    @Environment(AppModel.self) private var model
    let ref: ChapterRef
    @Binding var text: String
    var onDone: () -> Void
    @StateObject private var recorder = SpeechRecorder()
    @State private var notice: String?
    @State private var permitted: Bool?

    var body: some View {
        let rules = model.readingCheck
        let seconds = model.demo && recorder.speechSeconds == 0 ? Double(rules.seconds) * 0.7 : recorder.speechSeconds
        let spoken = model.demo && recorder.transcript.isEmpty ? DemoData.reflection : recorder.transcript
        let distinctNeeded = TextChecks.requiredDistinct(spokenSeconds: rules.seconds)
        let enough = Int(seconds) >= rules.seconds
        let distinctOK = TextChecks.distinctCount(spoken) >= distinctNeeded
        VStack(spacing: 16) {
            Text("Tell me what stood out in \(BookNames.title(ref))").font(Theme.serif(24)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            RingProgress(value: seconds / Double(max(1, rules.seconds)), lineWidth: 10) {
                Button {
                    if recorder.isRecording { recorder.stop() } else { startRecording() }
                } label: {
                    Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 44))
                        .frame(width: 128, height: 128)
                        .background(recorder.isRecording ? Theme.gold : Theme.soft, in: Circle())
                        .foregroundStyle(recorder.isRecording ? Color.white : Theme.gold)
                        .scaleEffect(1 + recorder.level * 0.08)
                }
                .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Start recording")
            }
            .frame(width: 180, height: 180)
            VStack(spacing: 2) {
                Text("\(Int(seconds)) / \(rules.seconds) sec").font(Theme.serif(28)).monospacedDigit().foregroundStyle(Theme.ink)
                Text(recorder.isRecording ? "Only time you are talking counts" : "Tap the microphone and start talking").font(.subheadline).foregroundStyle(Theme.dim)
            }
            ScrollView {
                Text(spoken.isEmpty ? "Your words show up here as you speak." : spoken)
                    .font(Theme.serif(17, .regular)).italic()
                    .foregroundStyle(spoken.isEmpty ? Theme.dim : Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxHeight: .infinity)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))
            if let msg = notice ?? recorder.problem {
                Text(msg).font(.footnote).foregroundStyle(Theme.red)
            } else if enough && !distinctOK {
                Text("Keep going a little. Say more about what you read.").font(.footnote).foregroundStyle(Theme.red)
            }
            Button(enough ? "Continue to questions" : "Keep talking") {
                recorder.stop()
                text = spoken
                let gate = ReflectionGate(ref: ref, text: spoken)
                if gate.relevant { onDone() } else { notice = gate.offTopicMessage }
            }
            .buttonStyle(.phos)
            .disabled(!(enough && distinctOK))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .onDisappear { recorder.stop() }
    }

    private func startRecording() {
        notice = nil
        Task {
            let ok = await SpeechRecorder.requestPermissions()
            await MainActor.run {
                if ok { recorder.start() } else { notice = "Allow the microphone and speech recognition in Settings, or type instead." }
            }
        }
    }
}

struct PromptsReflect: View {
    @Environment(AppModel.self) private var model
    let ref: ChapterRef
    @Binding var text: String
    var onDone: () -> Void
    @State private var answers = ["", "", ""]
    @State private var notice: String?

    private let prompts = ["What happened in this chapter?", "What surprised you or stood out?", "What will you do differently today?"]

    var body: some View {
        let need = Int((Double(model.readingCheck.words) / 3).rounded(.up))
        let counts = answers.map(TextChecks.wordCount)
        let done = counts.allSatisfy { $0 >= need }
        VStack(spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Three short answers").font(Theme.serif(24)).foregroundStyle(Theme.ink)
                    ForEach(0..<3, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(prompts[i]).font(.headline).foregroundStyle(Theme.ink)
                                Spacer()
                                Text(counts[i] >= need ? "Done" : "\(counts[i]) / \(need)")
                                    .font(.caption.weight(.semibold)).monospacedDigit()
                                    .foregroundStyle(counts[i] >= need ? Theme.green : Theme.dim)
                            }
                            NoPasteEditor(text: $answers[i], placeholder: "", fontSize: 17, onBlocked: { notice = "Paste is turned off." })
                                .frame(minHeight: 90)
                        }
                        .padding(16)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))
                    }
                    if let notice { Text(notice).font(.footnote).foregroundStyle(Theme.red) }
                }
                .padding(.horizontal, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            Button(done ? "Continue to questions" : "Keep writing") {
                let combined = zip(prompts, answers).map { "\($0.0) \($0.1)" }.joined(separator: "\n")
                let gate = ReflectionGate(ref: ref, text: answers.joined(separator: " "))
                if gate.relevant {
                    text = combined
                    onDone()
                } else {
                    notice = gate.offTopicMessage
                }
            }
            .buttonStyle(.phos)
            .disabled(!done)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .onAppear {
            if model.demo && answers == ["", "", ""] {
                answers = ["Nicodemus visits Jesus at night and asks how anyone can be born again when they are old.",
                           "Jesus does not shame him for coming in secret. He just tells him the truth plainly.",
                           "Bring the questions I keep hiding into the light"]
            }
        }
    }
}
