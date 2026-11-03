import Foundation
import SwiftData
import MTCore

/// One meeting recording. All properties have defaults and there are no unique
/// constraints, so the model is CloudKit-compatible and iCloud sync can be switched on later.
@Model
final class Recording {
    var id: UUID = UUID()
    var name: String = ""
    /// When the meeting was recorded (for imports: the source file's date).
    var createdAt: Date = Date.now
    var importedAt: Date? = nil
    /// Duration of the stored (trimmed) audio, seconds.
    var duration: Double = 0
    /// Duration before silence removal, seconds.
    var originalDuration: Double = 0
    var fileSize: Int64 = 0
    /// File name inside the app's Recordings directory.
    var fileName: String = ""
    var sourceRaw: String = RecordingSource.inApp.rawValue
    var statusRaw: String = RecordingStatus.new.rawValue
    var timeMapData: Data? = nil
    var errorMessage: String? = nil

    init(name: String, createdAt: Date = .now, source: RecordingSource, status: RecordingStatus) {
        self.id = UUID()
        self.name = name
        self.createdAt = createdAt
        self.sourceRaw = source.rawValue
        self.statusRaw = status.rawValue
    }

    var source: RecordingSource {
        get { RecordingSource(rawValue: sourceRaw) ?? .files }
        set { sourceRaw = newValue.rawValue }
    }

    var status: RecordingStatus {
        get { RecordingStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    var fileURL: URL? {
        fileName.isEmpty ? nil : AudioStorage.url(forFileName: fileName)
    }

    var timeMap: TimeMap? {
        get { timeMapData.flatMap { try? JSONDecoder().decode(TimeMap.self, from: $0) } }
        set { timeMapData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var isPlayable: Bool {
        status != .recording && status != .processing && fileURL.map { FileManager.default.fileExists(atPath: $0.path) } == true
    }

    static func defaultName(for date: Date) -> String {
        "Recording " + date.formatted(date: .abbreviated, time: .shortened)
    }
}
