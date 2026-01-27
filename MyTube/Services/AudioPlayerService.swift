import Foundation
import AVFoundation
import MediaPlayer
import Combine
import CoreMedia

@MainActor
class AudioPlayerService: ObservableObject {
    static let shared = AudioPlayerService()

    // Native AVPlayer - the sole playback engine
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    @Published var isPlaying: Bool = false
    @Published var currentTitle: String = ""
    @Published var currentAuthor: String = ""
    @Published var currentVideoDate: String?
    @Published var coverArtURL: URL?
    @Published var currentVideoId: String?
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var playbackRate: Float = 1.0

    // UI state
    @Published var isPlayerPresented: Bool = false
    @Published var isLoadingStream: Bool = false

    // Cached artwork for NowPlayingInfo
    private var cachedArtwork: MPMediaItemArtwork?
    private var cachedArtworkURL: URL?

    // Resume logic
    private var pendingResumeVideoId: String?
    private var pendingResumeProgress: Double?
    private var hasResumed: Bool = false

    // Progress tracking
    private var progressTimer: AnyCancellable?

    private init() {
        setupAudioSession()
        setupRemoteTransportControls()
        setupInterruptionHandling()
        try? AVAudioSession.sharedInstance().setActive(true)
        setupBackgroundHandlers()
    }

    // MARK: - Audio Session

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.allowAirPlay, .allowBluetooth]
            )
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            print("Audio session configured for native playback")
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }

    // MARK: - Background Handlers

    private func setupBackgroundHandlers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            print("App entered background")
            self?.handleBackgroundEntry()
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            print("App entering foreground")
            try? AVAudioSession.sharedInstance().setActive(true)
            self?.syncTimeFromPlayer()
        }
    }

    private func handleBackgroundEntry() {
        if isPlaying {
            // Re-assert audio session to ensure iOS keeps us alive
            setupAudioSession()
            updateNowPlayingInfo()
        }
    }

    // MARK: - Interruption Handling

    private func setupInterruptionHandling() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            if type == .began {
                print("Audio interrupted")
            } else if type == .ended {
                print("Audio interruption ended")
                try? AVAudioSession.sharedInstance().setActive(true)

                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume), let player = self.player {
                        player.play()
                        player.rate = self.playbackRate
                        self.isPlaying = true
                        self.updateNowPlayingInfo()
                    }
                }
            }
        }
    }

    // MARK: - Playback

    func playVideo(videoId: String, title: String, author: String, thumbnailURL: URL?, publishedAt: String? = nil) {
        print("Playing video: \(videoId)")
        setupAudioSession()

        // Set UI state immediately so the player sheet is responsive
        self.currentTitle = title
        self.currentAuthor = author
        self.currentVideoDate = publishedAt
        self.currentVideoId = videoId
        self.playbackRate = 1.0
        self.currentTime = 0
        self.duration = 0
        self.isPlayerPresented = true
        self.isLoadingStream = true
        self.isPlaying = false

        // Invalidate artwork cache if thumbnail changed
        if self.coverArtURL != thumbnailURL {
            self.coverArtURL = thumbnailURL
            self.cachedArtwork = nil
            self.cachedArtworkURL = nil
        }

        // Check for saved progress to resume
        self.pendingResumeVideoId = nil
        self.pendingResumeProgress = nil
        self.hasResumed = false

        if let status = VideoStatusManager.shared.getStatus(videoId: videoId),
           status.progress > 0.05 && status.progress < 0.95 {
            self.pendingResumeVideoId = videoId
            self.pendingResumeProgress = status.progress
        }

        // Stop any current playback
        cleanupPlayer()

        updateNowPlayingInfo()

        // Fetch audio stream URL and start native playback
        Task {
            do {
                let streamURL = try await YouTubeStreamService.shared.getAudioStreamURL(videoId: videoId)

                // Verify we're still supposed to play this video
                guard self.currentVideoId == videoId else { return }

                self.startNativePlayback(url: streamURL)
                self.isLoadingStream = false
            } catch {
                print("Stream extraction failed: \(error)")
                self.isLoadingStream = false
                self.isPlaying = false
            }
        }
    }

    private func startNativePlayback(url: URL) {
        let playerItem = AVPlayerItem(url: url)

        if player == nil {
            player = AVPlayer(playerItem: playerItem)
        } else {
            player?.replaceCurrentItem(with: playerItem)
        }

        player?.play()
        player?.rate = playbackRate
        isPlaying = true

        setupTimeObserver()
        setupEndObserver()
        startProgressTracking()
        updateNowPlayingInfo()

        print("Native AVPlayer started")
    }

    private func setupTimeObserver() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }

            Task { @MainActor in
                let seconds = time.seconds
                guard !seconds.isNaN else { return }

                self.currentTime = seconds

                if let dur = self.player?.currentItem?.duration.seconds, !dur.isNaN {
                    self.duration = dur

                    // Handle pending resume (seek to saved position once duration is known)
                    if !self.hasResumed,
                       let resumeVideoId = self.pendingResumeVideoId,
                       resumeVideoId == self.currentVideoId,
                       let progress = self.pendingResumeProgress {
                        self.hasResumed = true
                        let seekTime = dur * progress
                        let cmTime = CMTime(seconds: seekTime, preferredTimescale: 600)
                        self.player?.seek(to: cmTime)
                        self.currentTime = seekTime
                        self.pendingResumeVideoId = nil
                        self.pendingResumeProgress = nil
                        print("Resumed at \(seekTime)s (\(Int(progress * 100))%)")
                    }
                }

                // Sync NowPlaying info every 5 seconds to correct lock screen drift
                if Int(seconds) % 5 == 0 {
                    self.updateNowPlayingInfo()
                }
            }
        }
    }

    private func setupEndObserver() {
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.isPlaying = false
                self.updateNowPlayingInfo()
                self.stopProgressTracking()

                // Mark video as fully watched
                if let videoId = self.currentVideoId, self.duration > 0 {
                    VideoStatusManager.shared.saveProgress(
                        videoId: videoId,
                        progress: self.duration,
                        duration: self.duration
                    )
                }
                print("Playback ended")
            }
        }
    }

    private func cleanupPlayer() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        stopProgressTracking()
    }

    func stop() {
        cleanupPlayer()
        player = nil

        isPlaying = false
        currentTitle = ""
        currentAuthor = ""
        currentVideoId = nil
        coverArtURL = nil
        currentTime = 0
        duration = 0
        playbackRate = 1.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func togglePlayPause() {
        guard let player = player else { return }

        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            player.rate = playbackRate
            isPlaying = true
        }
        updateNowPlayingInfo()
    }

    func setPlaybackRate(_ rate: Float) {
        self.playbackRate = rate
        if let player = player, isPlaying {
            player.rate = rate
        }
        updateNowPlayingInfo()
    }

    func seek(to time: Double) {
        let clampedTime = max(0, min(time, duration))
        let cmTime = CMTime(seconds: clampedTime, preferredTimescale: 600)
        player?.seek(to: cmTime)
        self.currentTime = clampedTime
        updateNowPlayingInfo()
    }

    // MARK: - Remote Transport Controls (Lock Screen / Control Center)

    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()

        // Play
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self, let player = self.player else { return .commandFailed }
            player.play()
            player.rate = self.playbackRate
            self.isPlaying = true
            self.updateNowPlayingInfo()
            return .success
        }

        // Pause
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.player?.pause()
            self.isPlaying = false
            self.updateNowPlayingInfo()
            return .success
        }

        // Skip Backward (15 seconds)
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.seek(to: self.currentTime - 15)
            return .success
        }

        // Skip Forward (30 seconds)
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.seek(to: self.currentTime + 30)
            return .success
        }

        // Lock Screen Scrubber (seek slider)
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.seek(to: positionEvent.positionTime)
            return .success
        }
    }

    // MARK: - Now Playing Info

    func updateNowPlayingInfo() {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = currentTitle
        info[MPMediaItemPropertyArtist] = currentAuthor
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = Double(playbackRate)
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }

        if let cached = cachedArtwork {
            info[MPMediaItemPropertyArtwork] = cached
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        } else if let coverArtURL = coverArtURL {
            // Set info immediately without artwork so lock screen is responsive
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info

            let urlToCache = coverArtURL
            Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: urlToCache)
                    if let image = UIImage(data: data) {
                        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                        await MainActor.run {
                            if self.coverArtURL == urlToCache {
                                self.cachedArtwork = artwork
                                self.cachedArtworkURL = urlToCache
                                var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                                updatedInfo[MPMediaItemPropertyArtwork] = artwork
                                MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
                            }
                        }
                    }
                } catch {
                    print("Artwork download failed: \(error)")
                }
            }
        } else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    // MARK: - Progress Tracking

    private func startProgressTracking() {
        stopProgressTracking()
        progressTimer = Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.saveCurrentProgress()
            }
    }

    private func stopProgressTracking() {
        progressTimer?.cancel()
        progressTimer = nil
    }

    private func saveCurrentProgress() {
        guard let videoId = currentVideoId, isPlaying,
              let player = player,
              let dur = player.currentItem?.duration.seconds,
              !dur.isNaN, dur > 0 else { return }

        let pos = player.currentTime().seconds
        guard !pos.isNaN else { return }

        VideoStatusManager.shared.saveProgress(videoId: videoId, progress: pos, duration: dur)
    }

    /// Sync published time/duration from AVPlayer (useful on foreground return)
    private func syncTimeFromPlayer() {
        guard let player = player else { return }
        let seconds = player.currentTime().seconds
        if !seconds.isNaN {
            self.currentTime = seconds
        }
        if let dur = player.currentItem?.duration.seconds, !dur.isNaN {
            self.duration = dur
        }
        updateNowPlayingInfo()
    }
}
