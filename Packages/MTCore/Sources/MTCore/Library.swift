import Foundation

public enum RecordingStatus: String, Codable, CaseIterable, Sendable {
    case recording, processing, new, transcribing, done, failed

    public var displayName: String {
        switch self {
        case .recording: "Recording"
        case .processing: "Processing"
        case .new: "New"
        case .transcribing: "Transcribing"
        case .done: "Done"
        case .failed: "Failed"
        }
    }
}

public enum RecordingSource: String, Codable, CaseIterable, Sendable {
    case inApp, files, voiceMemos, shared

    public var isImported: Bool { self != .inApp }

    public var badgeTitle: String {
        switch self {
        case .inApp: "Recorded"
        case .files: "Imported · Files"
        case .voiceMemos: "Imported · Voice Memos"
        case .shared: "Imported"
        }
    }

    public var symbolName: String {
        switch self {
        case .inApp: "mic.fill"
        case .files: "folder.fill"
        case .voiceMemos: "waveform"
        case .shared: "square.and.arrow.down.fill"
        }
    }
}

public enum ImportChannel: Sendable {
    case filePicker, dragAndDrop, openIn
}

public enum ImportSourceDetector {
    public static func detect(path: String, fileName: String, channel: ImportChannel) -> RecordingSource {
        if path.contains("com.apple.VoiceMemos") { return .voiceMemos }
        if looksLikeVoiceMemoFileName(fileName) { return .voiceMemos }
        return channel == .openIn ? .shared : .files
    }

    /// Voice Memos exports are named either "<yyyyMMdd HHmmss>[-ID].m4a" (Mac storage)
    /// or by the memo title, which defaults to "New Recording N" / "הקלטה חדשה N".
    public static func looksLikeVoiceMemoFileName(_ fileName: String) -> Bool {
        let ns = fileName as NSString
        let ext = ns.pathExtension.lowercased()
        guard ext == "m4a" || ext == "qta" else { return false }
        let base = ns.deletingPathExtension
        let patterns = [
            #"^\d{8} \d{6}(-[0-9A-Fa-f]{8})?$"#,
            #"^(New Recording|הקלטה חדשה)( \d+)?$"#,
        ]
        return patterns.contains { base.range(of: $0, options: .regularExpression) != nil }
    }
}

public enum Formatting {
    /// "4:05" or "1:02:03".
    public static func duration(_ seconds: Double) -> String {
        let t = Int(max(0, seconds).rounded(.down))
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0 ? String(format: "%ld:%02ld:%02ld", h, m, s) : String(format: "%ld:%02ld", m, s)
    }

    /// Voice Memos–style running timer: "00:12.34" or "1:02:03.45".
    public static func timer(_ seconds: Double) -> String {
        let t = max(0, seconds)
        let whole = Int(t)
        let cs = min(99, Int((t - Double(whole)) * 100))
        let h = whole / 3600, m = (whole % 3600) / 60, s = whole % 60
        return h > 0 ? String(format: "%ld:%02ld:%02ld.%02ld", h, m, s, cs)
                     : String(format: "%02ld:%02ld.%02ld", m, s, cs)
    }

    public static func fileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
