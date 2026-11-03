import AVFoundation
import Observation
import MTCore
#if os(iOS)
import UIKit
#endif

enum RecorderError: LocalizedError {
    case permissionDenied, noInput, converterFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Microphone access is off. Enable it in Settings › Privacy › Microphone."
        case .noInput: "No microphone is available."
        case .converterFailed: "Could not set up the audio converter."
        }
    }
}

/// Captures the built-in microphone into a crash-safe raw PCM file (16 kHz mono).
/// Survives screen lock (background audio mode) and resumes automatically after
/// phone calls, Siri and other interruptions.
@MainActor
@Observable
final class AudioRecorder {
    enum State: Equatable { case idle, recording, paused, interrupted }

    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var levels: [Float] = []
    private(set) var activeRecordingID: UUID?
    var lastError: String?

    static let maxLevels = 300

    @ObservationIgnored private var engine = AVAudioEngine()
    @ObservationIgnored private var processor: TapProcessor?
    @ObservationIgnored private var writer: PCMWriter?
    @ObservationIgnored private var outputURL: URL?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    var isActive: Bool { state != .idle }

    // MARK: Control

    func start(id: UUID, url: URL) async throws {
        guard state == .idle else { return }
        guard await AVAudioApplication.requestRecordPermission() else { throw RecorderError.permissionDenied }
        try activateSession()
        writer = try PCMWriter(url: url)
        outputURL = url
        activeRecordingID = id
        elapsed = 0
        levels = []
        lastError = nil
        do {
            try startEngine()
        } catch {
            try? writer?.close()
            writer = nil
            activeRecordingID = nil
            deactivateSession()
            throw error
        }
        state = .recording
        installObservers()
    }

    func pause() {
        guard state == .recording else { return }
        engine.pause()
        state = .paused
    }

    func resume() {
        guard state == .paused || state == .interrupted else { return }
        do {
            try activateSession()
            if state == .interrupted { try restartEngine() } else { try engine.start() }
            state = .recording
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Stops and returns the recording id and raw file URL for post-processing.
    func stop() -> (id: UUID, rawURL: URL)? {
        guard state != .idle, let id = activeRecordingID, let url = outputURL else { return nil }
        removeObservers()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? writer?.close()
        writer = nil
        processor = nil
        deactivateSession()
        state = .idle
        activeRecordingID = nil
        outputURL = nil
        return (id, url)
    }

    // MARK: Engine

    private func startEngine() throws {
        guard let writer else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.noInput }
        let processor = try TapProcessor(inputFormat: format, writer: writer) { [weak self] level, total in
            Task { @MainActor [weak self] in self?.ingest(level: level, totalSamples: total) }
        }
        input.removeTap(onBus: 0)
        Self.installTap(on: input, format: format, processor: processor)
        self.processor = processor
        engine.prepare()
        try engine.start()
    }

    /// Installed from a nonisolated context so the real-time audio callback is not main-actor bound.
    nonisolated private static func installTap(on input: AVAudioInputNode, format: AVAudioFormat, processor: TapProcessor) {
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            processor.process(buffer)
        }
    }

    private func restartEngine() throws {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try startEngine()
    }

    private func ingest(level: Float, totalSamples: Int64) {
        guard state == .recording else { return }
        elapsed = Double(totalSamples) / PCMFormat.sampleRate
        levels.append(AudioMath.meterValue(dB: level))
        if levels.count > Self.maxLevels { levels.removeFirst(levels.count - Self.maxLevels) }
    }

    // MARK: Session & interruptions

    private func activateSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: [])
        if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try? session.setPreferredInput(builtIn)
        }
        try session.setActive(true)
        #endif
    }

    private func deactivateSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func installObservers() {
        let center = NotificationCenter.default
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated { self?.handleInterruption(typeRaw: raw) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMediaServicesReset() }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            // Some interruptions never deliver an "ended" event; retry when the user returns.
            MainActor.assumeIsolated {
                if self?.state == .interrupted { self?.resumeAfterInterruption(attempt: 0) }
            }
        })
        #endif
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] note in
            let changed = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated { self?.handleConfigurationChange(engineID: changed) }
        })
    }

    private func removeObservers() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }

    #if os(iOS)
    private func handleInterruption(typeRaw: UInt?) {
        guard let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        switch type {
        case .began:
            if state == .recording { state = .interrupted }
        case .ended:
            // Always resume: a meeting recorder should never silently stay stopped.
            if state == .interrupted { resumeAfterInterruption(attempt: 0) }
        @unknown default:
            break
        }
    }

    private func handleMediaServicesReset() {
        guard state != .idle else { return }
        engine = AVAudioEngine()
        let wasPaused = state == .paused
        do {
            try activateSession()
            if !wasPaused { try startEngine(); state = .recording } else { state = .interrupted }
        } catch {
            state = .interrupted
            lastError = error.localizedDescription
        }
    }
    #endif

    private func resumeAfterInterruption(attempt: Int) {
        guard state == .interrupted else { return }
        do {
            try activateSession()
            try restartEngine()
            state = .recording
        } catch {
            if attempt < 10 {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    self?.resumeAfterInterruption(attempt: attempt + 1)
                }
            } else {
                lastError = "Recording is paused because the microphone is in use. Tap Resume when ready."
            }
        }
    }

    private func handleConfigurationChange(engineID: ObjectIdentifier?) {
        guard engineID == nil || engineID == ObjectIdentifier(engine) else { return }
        // Input device / route changed: the engine has stopped. Rebuild the tap with the new format.
        guard state == .recording else { return }
        do { try restartEngine() } catch {
            state = .interrupted
            resumeAfterInterruption(attempt: 0)
        }
    }
}

/// Runs on the real-time audio thread: converts to 16 kHz mono Int16 and appends to disk.
final class TapProcessor: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let writer: PCMWriter
    private let ratio: Double
    private let onUpdate: @Sendable (Float, Int64) -> Void

    init(inputFormat: AVAudioFormat, writer: PCMWriter, onUpdate: @escaping @Sendable (Float, Int64) -> Void) throws {
        guard let out = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: PCMFormat.sampleRate, channels: 1, interleaved: true),
              let conv = AVAudioConverter(from: inputFormat, to: out) else { throw RecorderError.converterFailed }
        converter = conv
        outputFormat = out
        self.writer = writer
        ratio = PCMFormat.sampleRate / inputFormat.sampleRate
        self.onUpdate = onUpdate
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, out.frameLength > 0, let channel = out.int16ChannelData else { return }
        let samples = UnsafeBufferPointer(start: channel[0], count: Int(out.frameLength))
        try? writer.write(samples)
        onUpdate(AudioMath.dBFS(samples), writer.samplesWritten)
    }
}
