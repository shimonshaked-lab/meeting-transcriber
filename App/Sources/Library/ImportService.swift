import AVFoundation
import SwiftData
import MTCore

/// Copies external audio (Files, Voice Memos, drag & drop, "Open in") into the library.
@MainActor
enum ImportService {
    /// Returns error messages for files that could not be imported.
    @discardableResult
    static func importFiles(_ urls: [URL], channel: ImportChannel, context: ModelContext) async -> [String] {
        var errors: [String] = []
        for url in urls {
            do {
                try await importFile(url, channel: channel, context: context)
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return errors
    }

    static func importFile(_ url: URL, channel: ImportChannel, context: ModelContext) async throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let source = ImportSourceDetector.detect(path: url.path, fileName: url.lastPathComponent, channel: channel)
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let originalDate = values?.creationDate ?? values?.contentModificationDate ?? .now
        let name = url.deletingPathExtension().lastPathComponent

        let recording = Recording(name: name, createdAt: originalDate, source: source, status: .new)
        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension.lowercased()
        let dest = AudioStorage.url(forFileName: "\(recording.id.uuidString).\(ext)")

        let fm = FileManager.default
        try fm.copyItem(at: url, to: dest)
        AudioStorage.protect(dest)

        let asset = AVURLAsset(url: dest)
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        guard duration.isFinite, duration > 0 else {
            try? fm.removeItem(at: dest)
            throw ImportError.notAudio
        }

        recording.fileName = dest.lastPathComponent
        recording.duration = duration
        recording.originalDuration = duration
        recording.fileSize = AudioStorage.size(of: dest)
        recording.importedAt = .now
        context.insert(recording)
        try context.save()

        // Files handed over via "Open in" land in our Inbox; don't keep a second copy.
        if channel == .openIn, url.path.contains("/Inbox/") { try? fm.removeItem(at: url) }
    }

    enum ImportError: LocalizedError {
        case notAudio
        var errorDescription: String? { "This file doesn't contain playable audio." }
    }
}
