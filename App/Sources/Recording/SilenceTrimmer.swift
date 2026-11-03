import AVFoundation
import MTCore

/// Post-recording step: removes no-talk periods from the raw capture and encodes
/// the result as AAC (.m4a). Runs off the main thread.
enum SilenceTrimmer {
    struct Result: Sendable {
        var originalDuration: Double
        var trimmedDuration: Double
        var timeMap: TimeMap
    }

    enum TrimError: LocalizedError {
        case emptyRecording, bufferAllocation
        var errorDescription: String? {
            switch self {
            case .emptyRecording: "The recording contains no audio."
            case .bufferAllocation: "Out of memory while encoding audio."
            }
        }
    }

    static func trim(rawURL: URL, outputURL: URL, config: SilenceTrimConfig) throws -> Result {
        let reader = try PCMReader(url: rawURL)
        guard reader.sampleCount > 0 else { throw TrimError.emptyRecording }
        let sampleRate = PCMFormat.sampleRate
        let total = reader.duration
        let samplesPerFrame = max(1, Int(config.frameDuration * sampleRate))
        let levels = try AudioMath.frameLevels(reader: reader, samplesPerFrame: samplesPerFrame)
        let ranges = SilenceDetector(config: config).keepRanges(levels: levels, totalDuration: total)

        try? FileManager.default.removeItem(at: outputURL)
        try encodeAAC(reader: reader, ranges: ranges, to: outputURL)
        AudioStorage.protect(outputURL)

        let map = TimeMap(keepRanges: ranges)
        return Result(originalDuration: total, trimmedDuration: map.trimmedDuration, timeMap: map)
    }

    private static func encodeAAC(reader: PCMReader, ranges: [TimeRange], to url: URL) throws {
        let sampleRate = PCMFormat.sampleRate
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        // The file is finalized when `file` is released at the end of this scope.
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatInt16, interleaved: true)
        let format = file.processingFormat
        let fadeSamples = Int(0.01 * sampleRate)
        let block = Int(sampleRate) * 10

        for range in ranges {
            let start = Int64((range.start * sampleRate).rounded())
            let end = min(reader.sampleCount, Int64((range.end * sampleRate).rounded()))
            var pos = start
            while pos < end {
                var samples = try reader.read(from: pos, count: Int(min(Int64(block), end - pos)))
                if samples.isEmpty { break }
                let isFirst = pos == start
                let isLast = pos + Int64(samples.count) >= end
                AudioMath.applyFade(&samples, fadeIn: isFirst && start > 0 ? fadeSamples : 0,
                                    fadeOut: isLast && end < reader.sampleCount ? fadeSamples : 0)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                      let channel = buffer.int16ChannelData else { throw TrimError.bufferAllocation }
                buffer.frameLength = AVAudioFrameCount(samples.count)
                samples.withUnsafeBufferPointer { src in
                    channel[0].update(from: src.baseAddress!, count: src.count)
                }
                try file.write(from: buffer)
                pos += Int64(samples.count)
            }
        }
    }
}
