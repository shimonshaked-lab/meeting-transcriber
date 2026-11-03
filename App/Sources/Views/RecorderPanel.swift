import SwiftUI
import MTCore

/// Voice Memos–style recording control: big record button, live timer and waveform, pause/resume, stop.
struct RecorderPanel: View {
    @Environment(AudioRecorder.self) private var recorder
    let onRecord: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            if recorder.isActive {
                WaveformView(levels: recorder.levels, isLive: recorder.state == .recording)
                    .frame(height: 64)
                Text(Formatting.timer(recorder.elapsed))
                    .font(.system(size: 44, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityLabel("Elapsed \(Formatting.duration(recorder.elapsed))")
                statusLine
                HStack(spacing: 44) {
                    Button(action: togglePause) {
                        Image(systemName: recorder.state == .recording ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .frame(width: 56, height: 56)
                            .background(.quaternary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(recorder.state == .recording ? "Pause" : "Resume")
                    RecordButton(isRecording: true, action: onStop)
                    Color.clear.frame(width: 56, height: 56)
                }
            } else {
                RecordButton(isRecording: false, action: onRecord)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .animation(.snappy, value: recorder.isActive)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch recorder.state {
        case .paused:
            Label("Paused", systemImage: "pause.circle").font(.footnote).foregroundStyle(.secondary)
        case .interrupted:
            Label("Paused by a call or Siri — will resume automatically", systemImage: "phone.fill")
                .font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
        default:
            Label("Recording", systemImage: "record.circle").font(.footnote).foregroundStyle(.red)
        }
    }

    private func togglePause() {
        if recorder.state == .recording { recorder.pause() } else { recorder.resume() }
    }
}

struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 4)
                    .frame(width: 76, height: 76)
                RoundedRectangle(cornerRadius: isRecording ? 7 : 31, style: .continuous)
                    .fill(Color.red)
                    .frame(width: isRecording ? 30 : 62, height: isRecording ? 30 : 62)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.3), value: isRecording)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
        .keyboardShortcut("r", modifiers: .command)
    }
}

struct WaveformView: View {
    let levels: [Float]
    var isLive = true

    var body: some View {
        Canvas { ctx, size in
            let barWidth: CGFloat = 3, gap: CGFloat = 2
            let capacity = max(1, Int(size.width / (barWidth + gap)))
            let slice = levels.suffix(capacity)
            var x = size.width - CGFloat(slice.count) * (barWidth + gap)
            let color: Color = isLive ? .red : .secondary
            for level in slice {
                let h = max(2, CGFloat(level) * size.height)
                let rect = CGRect(x: x, y: (size.height - h) / 2, width: barWidth, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color))
                x += barWidth + gap
            }
        }
        .accessibilityHidden(true)
    }
}
