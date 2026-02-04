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
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var errorObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?

    // Fallback Player (WebView) - DEPRECATED
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

    @Published var playNext: Bool = false

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

    // Track if we need to resume after interruption
    private var wasPlayingBeforeInterruption: Bool = false

    override private init() {
        super.init()
        setupAudioSession()
        setupRemoteTransportControls()
        setupInterruptionHandling()
        setupBackgroundHandlers()
    }

    // MARK: - Audio Session

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Use .playback category for background audio
            // .spokenAudio mode is optimized for spoken word content like podcasts
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.allowBluetooth, .allowBluetoothA2DP]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("Audio session configured: category=playback, mode=spokenAudio")
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }

    private func ensureAudioSessionActive() {
        do {
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to activate audio session: \(error)")
        }
    }

    // MARK: - Background Handlers

    private func setupBackgroundHandlers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            print("App entered background - isPlaying: \(self.isPlaying)")
            if self.isPlaying {
                self.ensureAudioSessionActive()
                self.updateNowPlayingInfo()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            print("App entering foreground")
            self.ensureAudioSessionActive()
            self.syncTimeFromPlayer()
            self.updateNowPlayingInfo()
        }

        // Handle route changes (headphones unplugged, etc.)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

            if reason == .oldDeviceUnavailable {
                // Headphones were unplugged - pause playback
                print("Audio route changed: old device unavailable - pausing")
                self.player?.pause()
                self.isPlaying = false
                self.updateNowPlayingInfo()
            }
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

            switch type {
            case .began:
                print("Audio interruption began")
                self.wasPlayingBeforeInterruption = self.isPlaying
                self.isPlaying = false
                self.updateNowPlayingInfo()

            case .ended:
                print("Audio interruption ended")
                self.ensureAudioSessionActive()

                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) && self.wasPlayingBeforeInterruption {
                        print("Resuming playback after interruption")
                        self.player?.play()
                        self.player?.rate = self.playbackRate
                        self.isPlaying = true
                        self.updateNowPlayingInfo()
                    }
                }
                self.wasPlayingBeforeInterruption = false

            @unknown default:
                break
            }
        }
    }

    // MARK: - Playback

    func playVideo(videoId: String, title: String, author: String, thumbnailURL: URL?, publishedAt: String? = nil) {
        print("=== Starting playback for video: \(videoId) ===")

        // Ensure remote controls are receiving events
        UIApplication.shared.beginReceivingRemoteControlEvents()
        ensureAudioSessionActive()

        // Set UI state immediately
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
        self.useFallbackPlayer = false

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
            print("Will resume at \(Int(status.progress * 100))%")
        }

        // Stop any current playback
        cleanupPlayer()
        updateNowPlayingInfo()

        // Fetch audio stream URL from Backend API
        Task {
            do {
                // Determine Backend URL based on environment
                #if targetEnvironment(simulator)
                let backendBaseURL = "http://localhost:8888"
                print("AudioPlayerService: Running on Simulator -> Using Local Backend: \(backendBaseURL)")
                #else
                let backendBaseURL = "https://mytube-be.netlify.app"
                print("AudioPlayerService: Running on Device -> Using Production Backend: \(backendBaseURL)")
                #endif
                
                let backendURLString = "\(backendBaseURL)/.netlify/functions/audio?videoId=\(videoId)"
                guard let url = URL(string: backendURLString) else { return }

                print("AudioPlayerService: Requesting audio from: \(url.absoluteString)")

                // Verify we're still supposed to play this video
                guard self.currentVideoId == videoId else { return }
                
                // For the backend solution, we can just play the URL directly.
                // The backend will handle the 403/downloading logic and return a 307 Redirect to the final R2 URL.
                // AVPlayer handles redirects automatically.
                
                // Note: We do NOT set isLoadingStream = false here.
                // We wait for the AVPlayer to actually be ready or buffering to finish.
                self.startNativePlayback(url: url)

            } catch {
                print("Backend request failed: \(error)")
                self.isLoadingStream = false
                self.isPlaying = false
            }
        }
    }

    private func startNativePlayback(url: URL) {
        print("Starting native playback with URL: \(url.absoluteString.prefix(100))...")
        
        // Create AVURLAsset - no custom headers needed for backend/R2 URL
        let headers: [String: String] = [
            "x-api-key": Secrets.apiSecret
        ]
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])

        // Create player item
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 30  // Buffer 30 seconds ahead
        
        // Create or reuse player
        if player == nil {
            player = AVPlayer(playerItem: item)
            // Set audio output to mix with others when needed
            player?.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        } else {
            player?.replaceCurrentItem(with: item)
        }

        // Configure player for background playback
        player?.automaticallyWaitsToMinimizeStalling = true
        player?.allowsExternalPlayback = true
        
        player?.play()
        player?.rate = playbackRate
        isPlaying = true

        setupItemObservers(for: item)
        setupTimeObserver()
        setupEndObserver()
        startProgressTracking()
        updateNowPlayingInfo()
    }

    private func setupItemObservers(for item: AVPlayerItem) {
        // Remove old observers
        statusObserver = nil
        errorObserver = nil
        rateObserver = nil
        timeControlObserver = nil

        // Observe item status
        statusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            DispatchQueue.main.async {
                self?.handleItemStatusChange(item)
            }
        }

        // Observe item error
        errorObserver = item.observe(\.error, options: [.new]) { [weak self] item, _ in
            if let error = item.error {
                DispatchQueue.main.async {
                    self?.handlePlaybackError(error)
                }
            }
        }

        // Observe player rate changes
        if let player = player {
            rateObserver = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    let newIsPlaying = player.rate > 0
                    if self.isPlaying != newIsPlaying {
                        self.isPlaying = newIsPlaying
                        self.updateNowPlayingInfo()
                    }
                }
            }

            // Observe time control status for stalling detection
            timeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    switch player.timeControlStatus {
                    case .playing:
                        print("Player: Playing")
                        self.isPlaying = true
                    case .paused:
                        print("Player: Paused")
                        // Don't update isPlaying here - it might be intentional pause
                    case .waitingToPlayAtSpecifiedRate:
                        print("Player: Buffering...")
                    @unknown default:
                        break
                    }
                }
            }
        }
    }

    private func handleItemStatusChange(_ item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay:
            print("AVPlayerItem: Ready to play")
            self.isLoadingStream = false // <--- Spinner off
            
            // Ensure playback is active
            if isPlaying && player?.rate == 0 {
                player?.play()
                player?.rate = playbackRate
            }
            // Update duration if available from item
            let dur = item.duration.seconds
            if dur.isFinite && dur > 0 {
                if duration == 0 || dur < duration {
                    duration = dur
                }
            }

        case .failed:
            print("AVPlayerItem: Failed")
            handlePlaybackError(item.error)

        case .unknown:
            print("AVPlayerItem: Unknown status")

        @unknown default:
            break
        }
    }

    private func handlePlaybackError(_ error: Error?) {
        guard let error = error as NSError? else { return }
        print("Playback error: \(error.localizedDescription)")
        print("Error details: \(error.userInfo)")

        // Check for specific errors
        if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            print("Underlying error: \(underlyingError)")
            if underlyingError.code == -12660 { // HTTP 403
                print("HTTP 403 Forbidden - stream URL may have expired")
            }
        }

        isPlaying = false
        isLoadingStream = false
    }

    private func setupTimeObserver() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }

            let seconds = time.seconds
            guard seconds.isFinite else { return }

            self.currentTime = seconds

            if let dur = self.player?.currentItem?.duration.seconds, dur.isFinite && dur > 0 {
                // Update duration from player if we don't have it or player's is more accurate
                if self.duration == 0 || dur < self.duration {
                    self.duration = dur
                }

                // Handle pending resume
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
                    print("Resumed playback at \(seekTime)s (\(Int(progress * 100))%)")
                }
            }

            // Update NowPlayingInfo every 5 seconds
            if Int(seconds) % 5 == 0 {
                self.updateNowPlayingInfo()
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
            print("Playback ended")
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
        }
    }

    private func cleanupPlayer() {
        statusObserver = nil
        errorObserver = nil
        rateObserver = nil
        timeControlObserver = nil

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
        playerItem = nil
        stopProgressTracking()
    }

    func stop() {
        cleanupPlayer()
        player = nil

        isPlaying = false
        useFallbackPlayer = false
        currentTitle = ""
        currentAuthor = ""
        currentVideoId = nil
        coverArtURL = nil
        currentTime = 0
        duration = 0
        playbackRate = 1.0

        // Clear now playing info
        let nowPlayingCenter = MPNowPlayingInfoCenter.default()
        nowPlayingCenter.playbackState = .stopped
        nowPlayingCenter.nowPlayingInfo = nil
    }

    func togglePlayPause() {
        guard let player = player else { return }

        if player.timeControlStatus == .playing || player.rate > 0 {
            player.pause()
            isPlaying = false
        } else {
            ensureAudioSessionActive()
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
        let clampedTime = max(0, min(time, duration > 0 ? duration : .greatestFiniteMagnitude))
        let cmTime = CMTime(seconds: clampedTime, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        self.currentTime = clampedTime
        updateNowPlayingInfo()
    }

    // MARK: - Remote Transport Controls (Lock Screen / Control Center)

    private func setupRemoteTransportControls() {
        UIApplication.shared.beginReceivingRemoteControlEvents()

        let commandCenter = MPRemoteCommandCenter.shared()

        // Disable all commands first, then enable only what we need
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false

        // Play Command
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async {
                self.ensureAudioSessionActive()
                self.player?.play()
                self.player?.rate = self.playbackRate
                self.isPlaying = true
                self.updateNowPlayingInfo()
            }
            return .success
        }

        // Pause Command
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async {
                self.player?.pause()
                self.isPlaying = false
                self.updateNowPlayingInfo()
            }
            return .success
        }

        // Toggle Play/Pause (for headphone button)
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async {
                self.togglePlayPause()
            }
            return .success
        }

        // Skip Backward (15 seconds)
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async {
                self.seek(to: self.currentTime - 15)
            }
            return .success
        }

        // Skip Forward (30 seconds)
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async {
                self.seek(to: self.currentTime + 30)
            }
            return .success
        }

        // Seek bar (change playback position)
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            DispatchQueue.main.async {
                self.seek(to: positionEvent.positionTime)
            }
            return .success
        }

        print("Remote transport controls configured")
    }

    // MARK: - Now Playing Info

    func updateNowPlayingInfo() {
        let nowPlayingCenter = MPNowPlayingInfoCenter.default()

        // Set playback state - CRITICAL for Lock Screen display
        nowPlayingCenter.playbackState = isPlaying ? .playing : .paused

        var info = [String: Any]()

        // Basic metadata
        info[MPMediaItemPropertyTitle] = currentTitle.isEmpty ? "Loading..." : currentTitle
        info[MPMediaItemPropertyArtist] = currentAuthor
        info[MPMediaItemPropertyAlbumTitle] = "YouTube"

        // Playback info
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0

        // Duration
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }

        // Media type (audio)
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        info[MPNowPlayingInfoPropertyIsLiveStream] = false

        // Artwork
        if let cached = cachedArtwork, cachedArtworkURL == coverArtURL {
            info[MPMediaItemPropertyArtwork] = cached
        } else {
            info[MPMediaItemPropertyArtwork] = getPlaceholderArtwork()

            // Download artwork asynchronously
            if let artworkURL = coverArtURL, artworkURL != cachedArtworkURL {
                downloadArtwork(from: artworkURL)
            }
        }

        nowPlayingCenter.nowPlayingInfo = info
    }

    private func downloadArtwork(from url: URL) {
        let urlToDownload = url
        Task.detached(priority: .userInitiated) {
            do {
                let (data, _) = try await URLSession.shared.data(from: urlToDownload)
                guard let image = UIImage(data: data) else { return }

                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }

                await MainActor.run {
                    // Verify URL hasn't changed
                    guard self.coverArtURL == urlToDownload else { return }

                    self.cachedArtwork = artwork
                    self.cachedArtworkURL = urlToDownload

                    // Update NowPlayingInfo with new artwork
                    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    info[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                }
            } catch {
                print("Artwork download failed: \(error.localizedDescription)")
            }
        }
    }

    private func getPlaceholderArtwork() -> MPMediaItemArtwork {
        let size = CGSize(width: 600, height: 600)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            // Dark gradient background
            let colors = [UIColor(white: 0.2, alpha: 1.0).cgColor,
                          UIColor(white: 0.1, alpha: 1.0).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                       colors: colors as CFArray,
                                       locations: [0.0, 1.0])!
            ctx.cgContext.drawLinearGradient(gradient,
                                              start: .zero,
                                              end: CGPoint(x: 0, y: size.height),
                                              options: [])

            // Music note icon
            let iconRect = CGRect(x: size.width/2 - 80, y: size.height/2 - 80, width: 160, height: 160)
            UIColor.white.withAlphaComponent(0.3).setFill()
            let path = UIBezierPath(roundedRect: iconRect, cornerRadius: 20)
            path.fill()
        }
        return MPMediaItemArtwork(boundsSize: size) { _ in image }
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
        guard let videoId = currentVideoId,
              let player = player,
              let item = player.currentItem,
              item.duration.seconds.isFinite,
              item.duration.seconds > 0 else { return }

        let pos = player.currentTime().seconds
        guard pos.isFinite else { return }

        let dur = item.duration.seconds
        VideoStatusManager.shared.saveProgress(videoId: videoId, progress: pos, duration: dur)
    }

    /// Sync published time/duration from AVPlayer
    private func syncTimeFromPlayer() {
        guard let player = player else { return }
        let seconds = player.currentTime().seconds
        if seconds.isFinite {
            self.currentTime = seconds
        }
        if let dur = player.currentItem?.duration.seconds, dur.isFinite {
            self.duration = dur
        }

        // Update isPlaying based on actual player state
        self.isPlaying = player.rate > 0

        updateNowPlayingInfo()
    }
}
