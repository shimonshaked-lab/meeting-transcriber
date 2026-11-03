import XCTest
@testable import MTCore

final class SilenceDetectorTests: XCTestCase {
    func testInteriorSilenceIsCutWithPadding() {
        let levels = [Float](repeating: -20, count: 100) + [Float](repeating: -90, count: 100) + [Float](repeating: -20, count: 100)
        let keeps = SilenceDetector().keepRanges(levels: levels, totalDuration: 9)
        XCTAssertEqual(keeps.count, 2)
        XCTAssertEqual(keeps[0].start, 0, accuracy: 1e-9)
        XCTAssertEqual(keeps[0].end, 3.3, accuracy: 1e-6)
        XCTAssertEqual(keeps[1].start, 5.7, accuracy: 1e-6)
        XCTAssertEqual(keeps[1].end, 9, accuracy: 1e-9)
    }

    func testShortPausesAreKept() {
        // 1.5 s pause < 2 s minimum
        let levels = [Float](repeating: -20, count: 100) + [Float](repeating: -90, count: 50) + [Float](repeating: -20, count: 100)
        let keeps = SilenceDetector().keepRanges(levels: levels, totalDuration: 7.5)
        XCTAssertEqual(keeps, [TimeRange(start: 0, end: 7.5)])
    }

    func testLeadingAndTrailingSilenceKeepPaddingNextToSpeech() {
        let levels = [Float](repeating: -90, count: 100) + [Float](repeating: -20, count: 100) + [Float](repeating: -90, count: 100)
        let keeps = SilenceDetector().keepRanges(levels: levels, totalDuration: 9)
        XCTAssertEqual(keeps.count, 1)
        XCTAssertEqual(keeps[0].start, 2.7, accuracy: 1e-6)
        XCTAssertEqual(keeps[0].end, 6.3, accuracy: 1e-6)
    }

    func testAllSilenceKeepsEverything() {
        let levels = [Float](repeating: -90, count: 300)
        XCTAssertEqual(SilenceDetector().keepRanges(levels: levels, totalDuration: 9), [TimeRange(start: 0, end: 9)])
    }

    func testDisabledKeepsEverything() {
        let levels = [Float](repeating: -20, count: 100) + [Float](repeating: -90, count: 200)
        let keeps = SilenceDetector(config: .init(enabled: false)).keepRanges(levels: levels, totalDuration: 9)
        XCTAssertEqual(keeps, [TimeRange(start: 0, end: 9)])
    }

    func testThresholdAdaptsToNoisyRoom() {
        // Noise floor at -45 dB → threshold clamped to -35 dB max -30.
        let levels = [Float](repeating: -45, count: 200) + [Float](repeating: -15, count: 100)
        XCTAssertEqual(SilenceDetector().threshold(for: levels), -35, accuracy: 0.001)
    }
}

final class TimeMapTests: XCTestCase {
    func testMapsTrimmedTimesBackToOriginal() {
        let map = TimeMap(keepRanges: [TimeRange(start: 0, end: 3.3), TimeRange(start: 5.7, end: 9)])
        XCTAssertEqual(map.trimmedDuration, 6.6, accuracy: 1e-9)
        XCTAssertEqual(map.originalTime(forTrimmed: 1), 1, accuracy: 1e-9)
        XCTAssertEqual(map.originalTime(forTrimmed: 3.3), 5.7, accuracy: 1e-9)
        XCTAssertEqual(map.originalTime(forTrimmed: 4.3), 6.7, accuracy: 1e-9)
    }

    func testCodableRoundTrip() throws {
        let map = TimeMap(keepRanges: [TimeRange(start: 1, end: 2)])
        let decoded = try JSONDecoder().decode(TimeMap.self, from: JSONEncoder().encode(map))
        XCTAssertEqual(map, decoded)
    }
}

final class PCMAndMathTests: XCTestCase {
    func testWriterReaderRoundTripAndAppend() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pcm")
        defer { try? FileManager.default.removeItem(at: url) }
        var w = try PCMWriter(url: url)
        try w.write([1, 2, 3])
        try w.close()
        w = try PCMWriter(url: url) // reopening appends (crash recovery path)
        XCTAssertEqual(w.samplesWritten, 3)
        try w.write([4, 5])
        try w.close()
        let r = try PCMReader(url: url)
        XCTAssertEqual(r.sampleCount, 5)
        XCTAssertEqual(try r.read(from: 1, count: 10), [2, 3, 4, 5])
    }

    func testDBFS() {
        XCTAssertEqual(AudioMath.dBFS([Int16](repeating: 0, count: 10)), -120)
        XCTAssertEqual(AudioMath.dBFS([Int16](repeating: 32767, count: 10)), 0, accuracy: 0.01)
        XCTAssertEqual(AudioMath.dBFS([Int16](repeating: 16384, count: 10)), -6.02, accuracy: 0.05)
    }

    func testFade() {
        var s = [Int16](repeating: 1000, count: 10)
        AudioMath.applyFade(&s, fadeIn: 4, fadeOut: 4)
        XCTAssertEqual(s.first, 0)
        XCTAssertEqual(s.last, 0)
        XCTAssertEqual(s[5], 1000)
    }

    func testFrameLevels() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pcm")
        defer { try? FileManager.default.removeItem(at: url) }
        let w = try PCMWriter(url: url)
        try w.write([Int16](repeating: 0, count: 480) + [Int16](repeating: 16384, count: 480) + [Int16](repeating: 0, count: 100))
        try w.close()
        let levels = try AudioMath.frameLevels(reader: PCMReader(url: url), samplesPerFrame: 480)
        XCTAssertEqual(levels.count, 3)
        XCTAssertEqual(levels[0], -120)
        XCTAssertEqual(levels[1], -6.02, accuracy: 0.05)
    }
}

final class LibraryTests: XCTestCase {
    func testVoiceMemoDetection() {
        XCTAssertEqual(ImportSourceDetector.detect(path: "/x/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings/a.m4a", fileName: "a.m4a", channel: .dragAndDrop), .voiceMemos)
        XCTAssertEqual(ImportSourceDetector.detect(path: "/tmp/New Recording 4.m4a", fileName: "New Recording 4.m4a", channel: .openIn), .voiceMemos)
        XCTAssertEqual(ImportSourceDetector.detect(path: "/tmp/הקלטה חדשה 2.m4a", fileName: "הקלטה חדשה 2.m4a", channel: .openIn), .voiceMemos)
        XCTAssertEqual(ImportSourceDetector.detect(path: "/tmp/20241103 140512-1A2B3C4D.m4a", fileName: "20241103 140512-1A2B3C4D.m4a", channel: .filePicker), .voiceMemos)
        XCTAssertEqual(ImportSourceDetector.detect(path: "/tmp/Board meeting.m4a", fileName: "Board meeting.m4a", channel: .openIn), .shared)
        XCTAssertEqual(ImportSourceDetector.detect(path: "/tmp/call.mp3", fileName: "call.mp3", channel: .filePicker), .files)
    }

    func testFormatting() {
        XCTAssertEqual(Formatting.duration(245), "4:05")
        XCTAssertEqual(Formatting.duration(3723), "1:02:03")
        XCTAssertEqual(Formatting.timer(12.345), "00:12.34")
        XCTAssertEqual(Formatting.timer(3723.5), "1:02:03.50")
    }
}
