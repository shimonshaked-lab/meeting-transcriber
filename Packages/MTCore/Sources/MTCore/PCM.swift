import Foundation

/// Format of the raw capture file written while recording:
/// headerless, 16 kHz, mono, signed 16-bit little-endian PCM.
/// A headerless file is crash-safe: every byte that reached disk is valid audio.
public enum PCMFormat {
    public static let sampleRate: Double = 16_000
    public static let bytesPerSample = 2
}

/// Appends Int16 samples to a raw PCM file. Thread-safe.
public final class PCMWriter: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var _samplesWritten: Int64

    public init(url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try FileHandle(forWritingTo: url)
        let end = try handle.seekToEnd()
        _samplesWritten = Int64(end) / Int64(PCMFormat.bytesPerSample)
    }

    public var samplesWritten: Int64 {
        lock.lock(); defer { lock.unlock() }
        return _samplesWritten
    }

    public func write(_ samples: UnsafeBufferPointer<Int16>) throws {
        guard !samples.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        try handle.write(contentsOf: Data(buffer: samples))
        _samplesWritten += Int64(samples.count)
    }

    public func write(_ samples: [Int16]) throws {
        try samples.withUnsafeBufferPointer { try write($0) }
    }

    public func close() throws {
        lock.lock(); defer { lock.unlock() }
        try handle.synchronize()
        try handle.close()
    }
}

/// Random-access reader for raw PCM files.
public final class PCMReader {
    private let handle: FileHandle
    public let sampleCount: Int64

    public init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        let size = try handle.seekToEnd()
        sampleCount = Int64(size) / Int64(PCMFormat.bytesPerSample)
        try handle.seek(toOffset: 0)
    }

    deinit { try? handle.close() }

    public var duration: Double { Double(sampleCount) / PCMFormat.sampleRate }

    public func read(from start: Int64, count: Int) throws -> [Int16] {
        guard start < sampleCount, count > 0 else { return [] }
        try handle.seek(toOffset: UInt64(start) * UInt64(PCMFormat.bytesPerSample))
        guard let data = try handle.read(upToCount: count * PCMFormat.bytesPerSample), !data.isEmpty else { return [] }
        var out = [Int16](repeating: 0, count: data.count / PCMFormat.bytesPerSample)
        _ = out.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return out
    }
}
