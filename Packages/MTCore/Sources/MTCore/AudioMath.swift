import Foundation

public enum AudioMath {
    /// RMS level in dBFS (0 = full scale). Returns -120 for empty or digital silence.
    public static func dBFS<C: Collection>(_ samples: C) -> Float where C.Element == Int16 {
        guard !samples.isEmpty else { return -120 }
        var sum: Double = 0
        for v in samples {
            let x = Double(v) / 32768
            sum += x * x
        }
        let rms = (sum / Double(samples.count)).squareRoot()
        return rms > 0 ? max(-120, Float(20 * log10(rms))) : -120
    }

    /// Maps dBFS to 0...1 for meters/waveforms (−60 dB → 0).
    public static func meterValue(dB: Float, floor: Float = -60) -> Float {
        min(1, max(0, (dB - floor) / -floor))
    }

    /// Linear fade-in/out at the edges of a block, to avoid clicks at cut points.
    public static func applyFade(_ samples: inout [Int16], fadeIn: Int, fadeOut: Int) {
        let n = samples.count
        guard n > 0 else { return }
        let fi = min(fadeIn, n), fo = min(fadeOut, n)
        if fi > 0 {
            for i in 0..<fi { samples[i] = Int16(Double(samples[i]) * Double(i) / Double(fi)) }
        }
        if fo > 0 {
            for j in 0..<fo {
                let i = n - 1 - j
                samples[i] = Int16(Double(samples[i]) * Double(j) / Double(fo))
            }
        }
    }

    /// Per-frame dBFS levels of a raw PCM file, read in streaming blocks.
    public static func frameLevels(reader: PCMReader, samplesPerFrame: Int) throws -> [Float] {
        precondition(samplesPerFrame > 0)
        var levels: [Float] = []
        levels.reserveCapacity(Int(reader.sampleCount) / samplesPerFrame + 1)
        let block = samplesPerFrame * 1_000
        var pos: Int64 = 0
        while pos < reader.sampleCount {
            let samples = try reader.read(from: pos, count: block)
            if samples.isEmpty { break }
            var i = 0
            while i < samples.count {
                let end = min(i + samplesPerFrame, samples.count)
                levels.append(dBFS(samples[i..<end]))
                i = end
            }
            pos += Int64(samples.count)
        }
        return levels
    }
}
