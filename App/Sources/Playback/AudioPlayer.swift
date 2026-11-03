import AVFoundation
import Observation

@MainActor
@Observable
final class AudioPlayer {
    private(set) var isPlaying = false
    private(set) var duration: Double = 0
    var currentTime: Double = 0

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var loadedURL: URL?

    func load(_ url: URL) {
        guard url != loadedURL else { return }
        stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        duration = player?.duration ?? 0
        currentTime = 0
        loadedURL = url
    }

    func togglePlayback() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            ticker?.cancel()
        } else {
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
            #endif
            player.play()
            isPlaying = true
            startTicker()
        }
    }

    func seek(to time: Double) {
        let t = min(max(0, time), duration)
        player?.currentTime = t
        currentTime = t
    }

    func skip(by delta: Double) { seek(to: currentTime + delta) }

    func stop() {
        ticker?.cancel()
        player?.stop()
        isPlaying = false
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying {
                    self.isPlaying = false
                    return
                }
            }
        }
    }
}
