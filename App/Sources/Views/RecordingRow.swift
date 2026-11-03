import SwiftUI
import MTCore

struct RecordingRow: View {
    let recording: Recording
    let liveElapsed: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(recording.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                StatusChip(status: recording.status)
            }
            HStack(spacing: 6) {
                if recording.source.isImported {
                    SourceBadge(source: recording.source, compact: true)
                }
                Text(recording.createdAt, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                Text("·")
                Text(Formatting.duration(liveElapsed ?? recording.duration))
                    .monospacedDigit()
                if recording.fileSize > 0 {
                    Text("·")
                    Text(Formatting.fileSize(recording.fileSize))
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct StatusChip: View {
    let status: RecordingStatus

    var body: some View {
        HStack(spacing: 4) {
            if status == .recording {
                Circle().fill(.red).frame(width: 6, height: 6)
            } else if status == .processing || status == .transcribing {
                ProgressView().controlSize(.mini)
            }
            Text(status.displayName)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.15), in: Capsule())
    }

    private var color: Color {
        switch status {
        case .recording: .red
        case .processing, .transcribing: .orange
        case .new: .blue
        case .done: .green
        case .failed: .pink
        }
    }
}

/// Visual marker that distinguishes imported audio from in-app recordings.
struct SourceBadge: View {
    let source: RecordingSource
    var compact = false

    var body: some View {
        Label {
            Text(compact ? (source == .voiceMemos ? "Voice Memos" : "Imported") : source.badgeTitle)
        } icon: {
            Image(systemName: source.symbolName)
        }
        .labelStyle(.titleAndIcon)
        .font(.caption2.weight(.bold))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(.purple)
        .background(Color.purple.opacity(0.15), in: Capsule())
        .accessibilityLabel(source.badgeTitle)
    }
}
