import SwiftUI
import SwiftData
import MTCore

struct RecordingDetailView: View {
    @Bindable var recording: Recording
    @Environment(\.modelContext) private var context
    @Environment(AudioRecorder.self) private var recorder
    @Environment(RecordingProcessor.self) private var processor
    @State private var player = AudioPlayer()

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $recording.name)
                    .font(.title3.weight(.semibold))
                    .onSubmit { try? context.save() }
            }

            Section("Details") {
                LabeledContent("Date") {
                    Text(recording.createdAt, format: .dateTime.weekday().day().month().year().hour().minute())
                }
                LabeledContent("Duration") {
                    Text(Formatting.duration(recorder.activeRecordingID == recording.id ? recorder.elapsed : recording.duration))
                        .monospacedDigit()
                }
                if recording.originalDuration - recording.duration > 0.5 {
                    LabeledContent("Silence removed") {
                        Text("\(Formatting.duration(recording.originalDuration - recording.duration)) (\(savedPercent)%)")
                    }
                }
                LabeledContent("Size", value: recording.fileSize > 0 ? Formatting.fileSize(recording.fileSize) : "—")
                LabeledContent("Source") {
                    if recording.source.isImported {
                        SourceBadge(source: recording.source)
                    } else {
                        Text("Recorded in app")
                    }
                }
                LabeledContent("Status") { StatusChip(status: recording.status) }
                if let error = recording.errorMessage {
                    Text(error).foregroundStyle(.red).font(.footnote)
                    if processor.canRetry(recording) {
                        Button("Retry Processing") { Task { await processor.retry(recording, context: context) } }
                    }
                }
            }

            if recording.isPlayable {
                Section("Playback") { PlayerControls(player: player) }
            }

            Section("Transcript") {
                Text("Transcription arrives in the next stage.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(recording.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear(perform: loadAudio)
        .onChange(of: recording.fileName) { _, _ in loadAudio() }
        .onDisappear { player.stop() }
    }

    private var savedPercent: Int {
        guard recording.originalDuration > 0 else { return 0 }
        return Int(((recording.originalDuration - recording.duration) / recording.originalDuration * 100).rounded())
    }

    private func loadAudio() {
        if recording.isPlayable, let url = recording.fileURL { player.load(url) }
    }
}

struct PlayerControls: View {
    @Bindable var player: AudioPlayer

    var body: some View {
        VStack(spacing: 8) {
            Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                   in: 0...max(player.duration, 0.1))
            HStack {
                Text(Formatting.duration(player.currentTime)).monospacedDigit()
                Spacer()
                Text("-" + Formatting.duration(max(0, player.duration - player.currentTime))).monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack(spacing: 40) {
                Button { player.skip(by: -15) } label: { Image(systemName: "gobackward.15") }
                    .accessibilityLabel("Back 15 seconds")
                Button { player.togglePlayback() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title)
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Button { player.skip(by: 15) } label: { Image(systemName: "goforward.15") }
                    .accessibilityLabel("Forward 15 seconds")
            }
            .font(.title2)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 4)
    }
}
