import XCTest
import AVFoundation
import MTCore
import SwiftData
@testable import MeetingTranscriber

final class SilenceTrimmerTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func tone(seconds: Double, amplitude: Double = 8000) -> [Int16] {
        let n = Int(seconds * PCMFormat.sampleRate)
        return (0..<n).map { Int16(sin(Double($0) * 2 * .pi * 440 / PCMFormat.sampleRate) * amplitude) }
    }

    private func silence(seconds: Double) -> [Int16] {
        [Int16](repeating: 0, count: Int(seconds * PCMFormat.sampleRate))
    }

    func testRemovesLongSilenceAndWritesPlayableAAC() throws {
        let raw = dir.appending(path: "rec.pcm")
        let out = dir.appending(path: "rec.m4a")
        let writer = try PCMWriter(url: raw)
        try writer.write(tone(seconds: 2) + silence(seconds: 6) + tone(seconds: 2))
        try writer.close()

        let result = try SilenceTrimmer.trim(rawURL: raw, outputURL: out, config: SilenceTrimConfig())

        XCTAssertEqual(result.originalDuration, 10, accuracy: 0.01)
        // 2 s speech + 0.3 s padding + 0.3 s padding + 2 s speech
        XCTAssertEqual(result.trimmedDuration, 4.6, accuracy: 0.1)
        let file = try AVAudioFile(forReading: out)
        let seconds = Double(file.length) / file.fileFormat.sampleRate
        XCTAssertEqual(seconds, result.trimmedDuration, accuracy: 0.2)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertLessThan(AudioStorage.size(of: out), AudioStorage.size(of: raw) / 4, "AAC should be much smaller than raw PCM")
        // A moment just after the cut maps back to the second tone in the original timeline.
        XCTAssertEqual(result.timeMap.originalTime(forTrimmed: 2.4), 7.8, accuracy: 0.1)
    }

    func testDisabledTrimmingKeepsFullLength() throws {
        let raw = dir.appending(path: "rec.pcm")
        let out = dir.appending(path: "rec.m4a")
        let writer = try PCMWriter(url: raw)
        try writer.write(tone(seconds: 1) + silence(seconds: 4) + tone(seconds: 1))
        try writer.close()

        let result = try SilenceTrimmer.trim(rawURL: raw, outputURL: out, config: SilenceTrimConfig(enabled: false))
        XCTAssertEqual(result.trimmedDuration, 6, accuracy: 0.01)
    }

    func testEmptyRecordingThrows() throws {
        let raw = dir.appending(path: "empty.pcm")
        FileManager.default.createFile(atPath: raw.path, contents: Data())
        XCTAssertThrowsError(try SilenceTrimmer.trim(rawURL: raw, outputURL: dir.appending(path: "x.m4a"), config: .init()))
    }

    @MainActor
    func testImportAddsBadgedRecording() async throws {
        // Build a small m4a, then import it as if it came from Voice Memos.
        let raw = dir.appending(path: "src.pcm")
        let writer = try PCMWriter(url: raw)
        try writer.write(tone(seconds: 1))
        try writer.close()
        let source = dir.appending(path: "New Recording 7.m4a")
        _ = try SilenceTrimmer.trim(rawURL: raw, outputURL: source, config: .init())

        let container = try ModelContainer(for: Recording.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let errors = await ImportService.importFiles([source], channel: .openIn, context: context)
        XCTAssertEqual(errors, [])
        let all = try context.fetch(FetchDescriptor<Recording>())
        XCTAssertEqual(all.count, 1)
        let rec = try XCTUnwrap(all.first)
        XCTAssertEqual(rec.name, "New Recording 7")
        XCTAssertEqual(rec.source, .voiceMemos)
        XCTAssertEqual(rec.status, .new)
        XCTAssertEqual(rec.duration, 1, accuracy: 0.2)
        XCTAssertGreaterThan(rec.fileSize, 0)
        AudioStorage.removeFiles(for: rec)
    }
}
