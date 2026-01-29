import Foundation
import AVFoundation
import MediaPlayer
import Combine
import CoreMedia

@MainActor
class AudioPlayerService: NSObject, ObservableObject {
    static let shared = AudioPlayerService()

    // Native AVPlayer - the sole playback engine
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    // Fallback Player (WebView)
    @Published var useFallbackPlayer: Bool = false
    
    @Published var isPlaying: Bool = false
    @Published var currentTitle: String = ""
    @Published var currentAuthor: String = ""
    @Published var currentVideoDate: String?
    @Published var coverArtURL: URL?
    @Published var currentVideoId: String?
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var playbackRate: Float = 1.0
    
    // Seek Request for Fallback (WebView)
    @Published var playNext: Bool = false // Placeholder if needed

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

    override private init() {
        super.init()
        setupAudioSession()
        setupRemoteTransportControls()
        setupInterruptionHandling()
        try? AVAudioSession.sharedInstance().setActive(true)
        setupBackgroundHandlers()
    }

    // MARK: - Audio Session

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // .longFormAudio non supporta .allowAirPlay (che è implicito o incompatibile)
            // Rimuoviamo le opzioni che possono causare conflitto (errore -50)
            try session.setCategory(
                .playback,
                mode: .default,
                options: [] // Removed .allowAirPlay and implicitly .longFormAudio
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("Audio session configured for native playback (no special policy)")
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
            Task { @MainActor [weak self] in
                print("App entered background")
                self?.handleBackgroundEntry()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                print("App entering foreground")
                try? AVAudioSession.sharedInstance().setActive(true)
                self?.syncTimeFromPlayer()
            }
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

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
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
    }

    // MARK: - Playback

    func playVideo(videoId: String, title: String, author: String, thumbnailURL: URL?, publishedAt: String? = nil) {
        print("Playing video: \(videoId)")
        // Ensure remote controls are receiving events when playback starts
        UIApplication.shared.beginReceivingRemoteControlEvents()
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

        self.useFallbackPlayer = false // Reset fallback flag
        updateNowPlayingInfo()

        // Fetch audio stream URL and start native playback
        Task {
            do {
                let streamURL = try await YouTubeStreamService.shared.getAudioStreamURL(videoId: videoId)

                // Verify we're still supposed to play this video
                guard self.currentVideoId == videoId else { return }

                // Always use proxy to safely bypass 403 Forbidden by masking User-Agent
                await self.startProxiedPlayback(remoteURL: streamURL)
                
                self.isLoadingStream = false
            } catch {
                print("Stream extraction failed: \(error)")
                self.isLoadingStream = false
                self.isPlaying = false
            }
        }
    }
    
    /// Determine if we should use the proxy based on file size (>10MB)
    /// (Method kept for reference but now unused as we proxy everything)
    private func shouldUseProxy(for url: URL) -> Bool {
        return true
    }
    
    /// Start playback through local proxy (for large files)
    private func startProxiedPlayback(remoteURL: URL) async {
        // Extract expected duration from URL parameter (dur=xxx.xxx)
        if let urlComponents = URLComponents(url: remoteURL, resolvingAgainstBaseURL: false),
           let durParam = urlComponents.queryItems?.first(where: { $0.name == "dur" }),
           let durString = durParam.value,
           let expectedDuration = Double(durString) {
            self.duration = expectedDuration
            print("Duration from URL: \(expectedDuration)s")
        }
        
        // Set up proxy
        let headers: [String: String] = [
            "User-Agent": "com.google.android.youtube/19.29.35 (Linux; U; Android 14) gzip",
            "Referer": "https://www.youtube.com/",
            "Origin": "https://www.youtube.com",
            "X-Goog-Visitor-Id": "CgtjZEhZUWt0VGVzayjRzrq3BjIKCgJJVBIEGgAgDw%3D%3D" // Optional, often helps
        ]
        
        do {
            // Start proxy server if not running
            if !LocalStreamProxy.shared.isRunning {
                try await LocalStreamProxy.shared.startServer()
            }
            
            // Configure proxy with remote URL
            LocalStreamProxy.shared.setRemoteURL(remoteURL, headers: headers)
            
            // Give server a moment to be ready
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            
            guard let localURL = LocalStreamProxy.shared.getLocalURL() else {
                print("Failed to get local proxy URL")
                self.startNativePlayback(url: remoteURL) // Fallback to direct
                return
            }
            
            print("Using local proxy URL: \(localURL)")
            
            // Create player with local URL
            let playerItem = AVPlayerItem(url: localURL)
            playerItem.preferredForwardBufferDuration = 10.0
            
            // Observe status and error for debugging
            playerItem.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), options: [.new], context: nil)
            playerItem.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.error), options: [.new], context: nil)

            if player == nil {
                player = AVPlayer(playerItem: playerItem)
            } else {
                player?.replaceCurrentItem(with: playerItem)
            }
            
            player?.automaticallyWaitsToMinimizeStalling = true
            player?.play()
            player?.rate = playbackRate
            isPlaying = true

            setupTimeObserver()
            setupEndObserver()
            startProgressTracking()
            updateNowPlayingInfo()

            print("Proxied AVPlayer started for remote URL: \(remoteURL.absoluteString.prefix(100))...")
            
        } catch {
            print("Proxy setup failed: \(error), falling back to direct playback")
            self.startNativePlayback(url: remoteURL)
        }
    }

    /// Enable fallback mode (WebView) - DEPRECATED / DISABLED
    /// We now rely on the local proxy to handle 403 errors.
    private func enableFallbackMode() {
        print("Fallback Mode triggered but DISABLED in favor of Proxy.")
        // Optionally, we could retry with proxy here if we weren't already using it.
        // But since we proxy everything now, a failure here is real.
        Task { @MainActor in
            self.isPlaying = false
            self.stop()
        }
    }

    private func startNativePlayback(url: URL) {
        // Try to mimic the headers that might be expected for the Android client URL or generic playback
        let headers: [String: String] = [
            "User-Agent": "com.google.android.youtube/19.09.37 (Linux; U; Android 11) gzip",
            "Referer": "https://www.youtube.com/",
            "Origin": "https://www.youtube.com"
        ]
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        
        // Extract expected duration from URL parameter (dur=xxx.xxx)
        if let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let durParam = urlComponents.queryItems?.first(where: { $0.name == "dur" }),
           let durString = durParam.value,
           let expectedDuration = Double(durString) {
            self.duration = expectedDuration
            print("Duration from URL: \(expectedDuration)s")
        }
        
        // Extract file size from URL for debugging
        if let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let clenParam = urlComponents.queryItems?.first(where: { $0.name == "clen" }),
           let clenString = clenParam.value,
           let fileSize = Int(clenString) {
            let fileSizeMB = Double(fileSize) / 1024.0 / 1024.0
            print("File size: \(String(format: "%.1f", fileSizeMB))MB")
        }
        
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = 10.0  // Increased buffer for stability
        
        // Observe status and error for debugging
        playerItem.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), options: [.new], context: nil)
        playerItem.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.error), options: [.new], context: nil)

        if player == nil {
            player = AVPlayer(playerItem: playerItem)
        } else {
            player?.replaceCurrentItem(with: playerItem)
        }
        
        // Enable automatic waiting for proper buffering
        player?.automaticallyWaitsToMinimizeStalling = true

        player?.play()
        player?.rate = playbackRate
        isPlaying = true

        setupTimeObserver()
        setupEndObserver()
        startProgressTracking()
        updateNowPlayingInfo()

        print("Native AVPlayer started for URL: \(url.absoluteString)")
    }
    
    // KVO for AVPlayerItem debugging
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let playerItem = object as? AVPlayerItem else { return }
        
        if keyPath == #keyPath(AVPlayerItem.status) {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch playerItem.status {
                case .readyToPlay:
                    print("AVPlayerItem: Ready to play - ensuring playback")
                    // Ensure playback is active when item becomes ready
                    if self.isPlaying && self.player?.rate == 0 {
                        self.player?.play()
                        self.player?.rate = self.playbackRate
                    }
                case .failed:
                    print("AVPlayerItem: Failed. Error: \(String(describing: playerItem.error))")
                    if let error = playerItem.error as NSError? {
                        print("Error stats: \(error.userInfo)")
                        
                        // Check for 403 Forbidden or other fatal errors
                        if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                            if underlyingError.code == -12660 { // HTTP 403
                                print("AVPlayerItem: 403 Forbidden detected. Switching to Fallback Player.")
                                self.enableFallbackMode()
                                return
                            }
                        }
                    }
                    self.isPlaying = false
                    self.isLoadingStream = false
                case .unknown:
                    print("AVPlayerItem: Unknown status")
                @unknown default:
                    break
                }
            }
        }
        
        if keyPath == #keyPath(AVPlayerItem.error) {
             if let error = playerItem.error {
                 print("AVPlayerItem: Error observed: \(error)")
             }
        }
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
                    // Only update duration if we don't have one from the URL,
                    // or if player duration is smaller (indicating URL duration was wrong)
                    if self.duration == 0 || dur < self.duration {
                        self.duration = dur
                    }

                    // Handle pending resume (seek to saved position once duration is known)
                    let effectiveDuration = self.duration > 0 ? self.duration : dur
                    if !self.hasResumed,
                       let resumeVideoId = self.pendingResumeVideoId,
                       resumeVideoId == self.currentVideoId,
                       let progress = self.pendingResumeProgress {
                        self.hasResumed = true
                        let seekTime = effectiveDuration * progress
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
        // deliberately NOT stopping progress tracking here if switching to fallback,
        // but since cleanupPlayer is called before switch, we handle it carefully.
        // Actually, fallback has its own progress flow.
        stopProgressTracking()
    }

    func stop() {
        cleanupPlayer()
        player = nil
        
        LocalStreamProxy.shared.stopServer()

        isPlaying = false
        useFallbackPlayer = false
        currentTitle = ""
        currentAuthor = ""
        currentVideoId = nil
        coverArtURL = nil
        currentTime = 0
        duration = 0
        playbackRate = 1.0

        // Clear now playing info and set state to stopped
        let nowPlayingCenter = MPNowPlayingInfoCenter.default()
        nowPlayingCenter.playbackState = .stopped
        nowPlayingCenter.nowPlayingInfo = nil
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
        // Essential for Lock Screen / Dynamic Island controls to appear
        UIApplication.shared.beginReceivingRemoteControlEvents()
        
        let commandCenter = MPRemoteCommandCenter.shared()

        // Play
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let player = self.player else { return }
                player.play()
                player.rate = self.playbackRate
                self.isPlaying = true
                self.updateNowPlayingInfo()
            }
            return .success
        }

        // Pause
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.player?.pause()
                self.isPlaying = false
                self.updateNowPlayingInfo()
            }
            return .success
        }

        // Skip Backward (15 seconds)
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.seek(to: self.currentTime - 15)
            }
            return .success
        }

        // Skip Forward (30 seconds)
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.seek(to: self.currentTime + 30)
            }
            return .success
        }

        // Lock Screen Scrubber (seek slider)
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor [weak self] in
                self?.seek(to: positionEvent.positionTime)
            }
            return .success
        }
    }
    
    // MARK: - Now Playing Info

    func updateNowPlayingInfo() {
        print("Updating NowPlayingInfo: Title=\(currentTitle), Rate=\(playbackRate), Time=\(currentTime)")
        
        let nowPlayingCenter = MPNowPlayingInfoCenter.default()
        
        // Set the playback state explicitly - CRITICAL for Lock Screen and Dynamic Island
        nowPlayingCenter.playbackState = isPlaying ? .playing : .paused
        
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = currentTitle
        info[MPMediaItemPropertyArtist] = currentAuthor
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = Double(playbackRate)
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        // info[MPMediaItemPropertyMediaType] = NSNumber(value: MPMediaType.podcast.rawValue) // Removed to ensure standard compatibility
        
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }

        if let cached = cachedArtwork {
            info[MPMediaItemPropertyArtwork] = cached
            nowPlayingCenter.nowPlayingInfo = info
        } else if let coverArtURL = coverArtURL {
            // Set info immediately with placeholder while downloading
            info[MPMediaItemPropertyArtwork] = getPlaceholderArtwork()
            nowPlayingCenter.nowPlayingInfo = info

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
            // Always provide an artwork, otherwise Lock Screen might hide the player
            info[MPMediaItemPropertyArtwork] = getPlaceholderArtwork()
            nowPlayingCenter.nowPlayingInfo = info
        }
    }
    
    private func getPlaceholderArtwork() -> MPMediaItemArtwork {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512))
        let image = renderer.image { ctx in
            UIColor.darkGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
        }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
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
              dur > 0 else { return }

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
