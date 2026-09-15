import SwiftUI

/// Settings > Reading > Voice: which voice reads to you, how fast, and the natural voices download.
struct VoiceSettingsView: View {
    @Environment(AppModel.self) private var model
    @ObservedObject private var kokoro = KokoroModel.shared
    @StateObject private var preview = ChapterSpeaker()
    @State private var systemVoices: [VoiceChoice] = []
    @State private var confirmRemove = false
    @State private var voiceHelp = false

    private static let sample = "Your word is a lamp to my feet, and a light for my path."

    var body: some View {
        @Bindable var model = model
        List {
            Section {
                Button {
                    if preview.playing {
                        preview.stop()
                    } else {
                        preview.load([Self.sample])
                        preview.title = "Preview"
                        preview.voiceID = model.settings.voiceID
                        preview.rate = model.settings.voiceRate
                        preview.skip(-1000)
                        preview.resume()
                    }
                } label: {
                    Label(preview.playing ? "Stop preview" : "Preview \(VoiceCatalog.name(model.settings.voiceID))", systemImage: preview.playing ? "stop.fill" : "play.fill")
                }
                .foregroundStyle(Theme.ink)
                Picker("Speed", selection: $model.settings.voiceRate) {
                    ForEach(VoiceSpeed.options, id: \.self) { Text(VoiceSpeed.label($0)).tag($0) }
                }
            } footer: {
                Text("Natural voices change speed at once. iPhone voices restart the verse at the new speed.")
            }

            if VoiceCatalog.naturalSupported {
                Section("Natural voices") {
                    if kokoro.ready {
                        ForEach(VoiceCatalog.natural) { v in row(v) }
                        Button(role: .destructive) { confirmRemove = true } label: {
                            Label("Remove natural voices (\(KokoroModel.megabytes) MB)", systemImage: "trash")
                        }
                    } else if let progress = kokoro.progress {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressBar(value: progress)
                            Text("\(Int(progress * 100))% downloaded. The download keeps going if you lock your iPhone.")
                                .font(.caption).foregroundStyle(Theme.dim)
                        }
                        Button("Cancel download") { kokoro.cancel() }.foregroundStyle(Theme.red)
                    } else {
                        Text("13 lifelike voices that read on your iPhone with no connection. One download of \(KokoroModel.megabytes) MB, so WiFi is best.")
                            .font(.footnote).foregroundStyle(Theme.dim)
                        if let problem = kokoro.problem {
                            Text(problem).font(.footnote).foregroundStyle(Theme.red)
                        }
                        Button("Download natural voices") { kokoro.download() }.foregroundStyle(Theme.ink)
                    }
                }
            }

            Section("iPhone voices") {
                if systemVoices.isEmpty {
                    Text("Loading voices").foregroundStyle(Theme.dim)
                }
                ForEach(systemVoices) { v in row(v) }
                Button("Get more iPhone voices") { voiceHelp = true }.foregroundStyle(Theme.ink)
            }
        }
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .onAppear { VoiceCatalog.warm { systemVoices = VoiceCatalog.system() } }
        .onChange(of: model.settings.voiceRate) { _, r in
            model.savePreferences()
            preview.setRate(r)
        }
        .onDisappear { preview.stop() }
        .confirmationDialog("Remove natural voices?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove \(KokoroModel.megabytes) MB", role: .destructive) {
                preview.stop()
                kokoro.remove()
                if VoiceCatalog.kokoroName(model.settings.voiceID) != nil {
                    model.settings.voiceID = ""
                    model.savePreferences()
                }
            }
            Button("Keep them", role: .cancel) {}
        } message: {
            Text("Listening switches to iPhone voices. You can download the natural voices again any time.")
        }
        .sheet(isPresented: $voiceHelp) { BetterVoicesHelp().presentationDetents([.medium]) }
    }

    private var currentID: String {
        if !model.settings.voiceID.isEmpty { return model.settings.voiceID }
        return VoiceCatalog.isWarm ? "system:\(VoiceCatalog.systemVoice("").identifier)" : ""
    }

    private func row(_ v: VoiceChoice) -> some View {
        Button {
            model.settings.voiceID = v.id
            model.savePreferences()
            preview.voiceID = v.id
            preview.restartVerse()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(v.name).foregroundStyle(Theme.ink)
                    Text(v.detail).font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer()
                if v.id == currentID { Image(systemName: "checkmark").foregroundStyle(Theme.gold) }
            }
        }
    }
}
