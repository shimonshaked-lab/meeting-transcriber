import Foundation
import Observation
import SwiftData
import MTCore

/// Turns a finished raw capture into the stored, silence-trimmed file,
/// and recovers recordings that were cut short by a crash or forced quit.
@MainActor
@Observable
final class RecordingProcessor {
    func finalize(_ recording: Recording, rawURL: URL, context: ModelContext) async {
        recording.status = .processing
        recording.errorMessage = nil
        try? context.save()

        let outputURL = AudioStorage.trimmedURL(for: recording.id)
        let config = AppSettings.trimConfig
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try SilenceTrimmer.trim(rawURL: rawURL, outputURL: outputURL, config: config)
            }.value
            recording.fileName = outputURL.lastPathComponent
            recording.duration = result.trimmedDuration
            recording.originalDuration = result.originalDuration
            recording.timeMap = result.timeMap
            recording.fileSize = AudioStorage.size(of: outputURL)
            recording.status = .new
            // Keep only the trimmed file.
            try? FileManager.default.removeItem(at: rawURL)
        } catch {
            // Raw audio is kept so nothing is lost; the user can retry.
            recording.status = .failed
            recording.errorMessage = "Processing failed: \(error.localizedDescription)"
        }
        try? context.save()
    }

    func retry(_ recording: Recording, context: ModelContext) async {
        let raw = AudioStorage.rawURL(for: recording.id)
        guard FileManager.default.fileExists(atPath: raw.path) else { return }
        await finalize(recording, rawURL: raw, context: context)
    }

    func canRetry(_ recording: Recording) -> Bool {
        recording.status == .failed && FileManager.default.fileExists(atPath: AudioStorage.rawURL(for: recording.id).path)
    }

    /// Called at launch: anything still marked recording/processing was interrupted by the app ending.
    func recoverInterrupted(context: ModelContext, excluding activeID: UUID?) async {
        let recordingRaw = RecordingStatus.recording.rawValue
        let processingRaw = RecordingStatus.processing.rawValue
        let descriptor = FetchDescriptor<Recording>(predicate: #Predicate {
            $0.statusRaw == recordingRaw || $0.statusRaw == processingRaw
        })
        guard let stale = try? context.fetch(descriptor) else { return }
        for recording in stale where recording.id != activeID {
            let raw = AudioStorage.rawURL(for: recording.id)
            if FileManager.default.fileExists(atPath: raw.path), AudioStorage.size(of: raw) > 0 {
                await finalize(recording, rawURL: raw, context: context)
            } else {
                recording.status = .failed
                recording.errorMessage = "The recording was interrupted before any audio was saved."
                try? context.save()
            }
        }
    }
}
