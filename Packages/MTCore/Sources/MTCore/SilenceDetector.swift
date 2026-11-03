import Foundation

public struct TimeRange: Codable, Sendable, Equatable {
    public var start: Double
    public var end: Double
    public init(start: Double, end: Double) { self.start = start; self.end = end }
    public var duration: Double { end - start }
}

public struct SilenceTrimConfig: Codable, Sendable, Equatable {
    /// Silences shorter than this are kept untouched.
    public var minSilence: Double
    /// Audio kept on each side of a removed silence, so words are never clipped.
    public var padding: Double
    /// Speech threshold = noise floor + this many dB (clamped below).
    public var thresholdAboveNoiseFloor: Float
    public var minThreshold: Float
    public var maxThreshold: Float
    public var frameDuration: Double
    public var enabled: Bool

    public init(minSilence: Double = 2.0, padding: Double = 0.3,
                thresholdAboveNoiseFloor: Float = 10, minThreshold: Float = -60,
                maxThreshold: Float = -30, frameDuration: Double = 0.03, enabled: Bool = true) {
        self.minSilence = minSilence
        self.padding = padding
        self.thresholdAboveNoiseFloor = thresholdAboveNoiseFloor
        self.minThreshold = minThreshold
        self.maxThreshold = maxThreshold
        self.frameDuration = frameDuration
        self.enabled = enabled
    }
}

/// Adaptive energy-based silence detector.
/// Estimates the room's noise floor (10th percentile of frame levels) and treats
/// anything well above it as speech. Deliberately conservative: when in doubt, keep audio.
public struct SilenceDetector: Sendable {
    public let config: SilenceTrimConfig
    public init(config: SilenceTrimConfig = .init()) { self.config = config }

    public func threshold(for levels: [Float]) -> Float {
        guard !levels.isEmpty else { return config.minThreshold }
        let sorted = levels.sorted()
        let floor = sorted[Int(Double(sorted.count - 1) * 0.1)]
        return min(max(floor + config.thresholdAboveNoiseFloor, config.minThreshold), config.maxThreshold)
    }

    /// Ranges (seconds, original timeline) to keep.
    public func keepRanges(levels: [Float], totalDuration: Double) -> [TimeRange] {
        guard totalDuration > 0 else { return [] }
        let full = [TimeRange(start: 0, end: totalDuration)]
        guard config.enabled, !levels.isEmpty else { return full }

        let thr = threshold(for: levels)
        let fd = config.frameDuration
        var cuts: [TimeRange] = []
        var runStart: Int?
        var sawSpeech = false

        func closeRun(_ startIdx: Int, _ endIdx: Int) {
            let s = Double(startIdx) * fd
            let e = min(Double(endIdx) * fd, totalDuration)
            guard e - s >= config.minSilence else { return }
            let cutStart = startIdx == 0 ? 0 : s + config.padding
            let cutEnd = endIdx >= levels.count ? totalDuration : e - config.padding
            if cutEnd > cutStart { cuts.append(TimeRange(start: cutStart, end: cutEnd)) }
        }

        for (i, level) in levels.enumerated() {
            if level < thr {
                if runStart == nil { runStart = i }
            } else {
                sawSpeech = true
                if let rs = runStart { closeRun(rs, i); runStart = nil }
            }
        }
        if let rs = runStart { closeRun(rs, levels.count) }
        // Never reduce a recording to nothing.
        guard sawSpeech else { return full }

        var keeps: [TimeRange] = []
        var cursor = 0.0
        for c in cuts {
            if c.start > cursor { keeps.append(TimeRange(start: cursor, end: c.start)) }
            cursor = max(cursor, c.end)
        }
        if cursor < totalDuration { keeps.append(TimeRange(start: cursor, end: totalDuration)) }
        return keeps.filter { $0.duration > 0.001 }
    }
}

/// Maps times in the trimmed file back to the original (wall-clock) recording timeline.
public struct TimeMap: Codable, Sendable, Equatable {
    public struct Segment: Codable, Sendable, Equatable {
        public var trimmedStart: Double
        public var originalStart: Double
        public var duration: Double
    }

    public var segments: [Segment]

    public init(keepRanges: [TimeRange]) {
        var t = 0.0
        segments = keepRanges.map {
            let s = Segment(trimmedStart: t, originalStart: $0.start, duration: $0.duration)
            t += $0.duration
            return s
        }
    }

    public var trimmedDuration: Double { segments.reduce(0) { $0 + $1.duration } }

    public func originalTime(forTrimmed t: Double) -> Double {
        guard let seg = segments.last(where: { $0.trimmedStart <= t }) else { return t }
        return seg.originalStart + min(t - seg.trimmedStart, seg.duration)
    }
}
