import Foundation

/// Location and protection of audio files. Everything stays in the app's private container.
enum AudioStorage {
    static let recordingsDirectory: URL = {
        let dir = URL.applicationSupportDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        protect(dir)
        return dir
    }()

    static func url(forFileName name: String) -> URL {
        recordingsDirectory.appending(path: name, directoryHint: .notDirectory)
    }

    static func rawURL(for id: UUID) -> URL { url(forFileName: "\(id.uuidString).pcm") }
    static func trimmedURL(for id: UUID) -> URL { url(forFileName: "\(id.uuidString).m4a") }

    static func size(of url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Encrypted at rest; readable while locked only after the first unlock since boot,
    /// which is what lets recording (and later, background uploads) continue on the lock screen.
    static func protect(_ url: URL) {
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path)
        #endif
    }

    static func removeFiles(for recording: Recording) {
        let fm = FileManager.default
        for url in [recording.fileURL, AudioStorage.rawURL(for: recording.id), AudioStorage.trimmedURL(for: recording.id)].compactMap({ $0 }) {
            try? fm.removeItem(at: url)
        }
    }
}
