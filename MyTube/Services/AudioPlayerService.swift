import Foundation
import AVFoundation
import MediaPlayer
import Combine
import CoreMedia

@MainActor
class AudioPlayerService: ObservableObject {
    static let shared = AudioPlayerService()
    
    // Native player for direct streams (or silent keep-alive)
    var player: AVPlayer?
    
    // Silent Audio Player for Keep-Alive
    var silentPlayer: AVAudioPlayer?
    
    @Published var isPlaying: Bool = false
    @Published var currentTitle: String = ""
    @Published var currentAuthor: String = ""
    @Published var currentVideoDate: String?
    @Published var coverArtURL: URL?
    @Published var currentVideoId: String?
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var seekRequest: Double?
    @Published var playbackRate: Float = 1.0
    
    // UI Presentation Trigger
    @Published var isPlayerPresented: Bool = false

    // Cached artwork for NowPlayingInfo (avoids re-downloading every update)
    private var cachedArtwork: MPMediaItemArtwork?
    private var cachedArtworkURL: URL?

    // Resume Logic
    private var pendingResumeVideoId: String?
    private var pendingResumeProgress: Double?
    private var hasResumed: Bool = false
    
    private init() {
        setupAudioSession()
        setupRemoteTransportControls()
        setupSilentAudio()
        setupInterruptionHandling()
        
        // Ensure session is active immediately
        try? AVAudioSession.sharedInstance().setActive(true)
        
        setupBackgroundHandlers()
    }
    
    private func setupBackgroundHandlers() {
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            print("App entered background")
            self?.handleBackgroundEntry()
        }
        
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
             print("App will enter foreground")
             // Ensure session is active
             try? AVAudioSession.sharedInstance().setActive(true)
        }
    }
    
    private func handleBackgroundEntry() {
        // If we are playing (WebView or Native)
        if isPlaying {
            // 1. Re-assert Audio Session
            setupAudioSession()

            // 2. Start a fresh background task to bridge the transition
            endBackgroundTask()
            startBackgroundTask()

            // 3. If using WebView (player is nil), we MUST rely on silent audio
            if player == nil {
                if silentPlayer == nil { setupSilentAudio() }
                if let sp = silentPlayer, !sp.isPlaying {
                    sp.play()
                    print("Silent player forced in background")
                }
            }

            // 4. Re-assert Now Playing Info
            updateNowPlayingInfo()
        }
    }
    
    private func setupAudioSession() {
        do {
            // Use .moviePlayback which is often better for WebView video content
            // Remove .mixWithOthers so we become the primary audio
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            print("Audio Session set active (playback/default/mixWithOthers)")
        } catch {
            print("Failed to set audio session: \(error)")
        }
    }
    
    private func setupInterruptionHandling() {
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self = self, let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            if type == .began {
                print("Audio session interrupted")
                // Don't set isPlaying = false here; the system paused us,
                // we want to auto-resume when the interruption ends
            } else if type == .ended {
                print("Audio session interruption ended")
                // Re-activate the audio session
                try? AVAudioSession.sharedInstance().setActive(true)

                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        if let player = self.player {
                            player.play()
                            player.rate = self.playbackRate
                        } else {
                            // WebView mode: restart silent player and signal WebView to resume
                            if self.silentPlayer == nil { self.setupSilentAudio() }
                            self.silentPlayer?.play()
                        }
                        self.isPlaying = true
                        self.startBackgroundTask()
                        self.updateNowPlayingInfo()
                    }
                }
            }
        }
    }
    
    private func setupSilentAudio() {
        // Create 1 second of silence using a valid WAV header + empty data
        let sampleRate: Int32 = 44100
        let duration: Int32 = 5
        let dataSize = Int32(sampleRate * duration * 2)
        let fileSize = 36 + dataSize
        
        let header: [UInt8] = [
            0x52, 0x49, 0x46, 0x46, // RIFF
            UInt8(fileSize & 0xff), UInt8((fileSize >> 8) & 0xff), UInt8((fileSize >> 16) & 0xff), UInt8((fileSize >> 24) & 0xff),
            0x57, 0x41, 0x56, 0x45, // WAVE
            0x66, 0x6d, 0x74, 0x20, // fmt 
            16, 0, 0, 0, // Subchunk1Size
            1, 0, // AudioFormat (PCM)
            1, 0, // NumChannels (Mono)
            0x44, 0xAC, 0, 0, // SampleRate (44100)
            0x88, 0x58, 0x1, 0, // ByteRate
            2, 0, // BlockAlign
            16, 0, // BitsPerSample
            0x64, 0x61, 0x74, 0x61, // data
            UInt8(dataSize & 0xff), UInt8((dataSize >> 8) & 0xff), UInt8((dataSize >> 16) & 0xff), UInt8((dataSize >> 24) & 0xff)
        ]
        
        var bytes = header
        bytes.append(contentsOf: Array(repeating: 0, count: Int(dataSize)))
        
        let data = Data(bytes)
        
        do {
            silentPlayer = try AVAudioPlayer(data: data)
            silentPlayer?.numberOfLoops = -1 // Infinite
            silentPlayer?.volume = 0.01 // Nearly silent
            silentPlayer?.prepareToPlay()
            print("Silent Audio Player Initialized Memory-Only")
        } catch {
            print("Failed to init silent player: \(error)")
        }
    }
    
    // Legacy file function removed
    private func createAndLoadSilentFile() {
        setupSilentAudio()
    }
    
    // Removed generateSilentFile placeholder
    private func generateSilentAudioFile() -> URL? { nil }
    
    func playVideo(videoId: String, title: String, author: String, thumbnailURL: URL?, publishedAt: String? = nil) {
        print("Attempting to play video: \(videoId)")
        setupAudioSession()
        
        self.currentTitle = title
        self.currentAuthor = author
        self.currentVideoDate = publishedAt
        self.currentVideoId = videoId
        self.isPlaying = true
        self.playbackRate = 1.0

        // Invalidate artwork cache if thumbnail changed
        if self.coverArtURL != thumbnailURL {
            self.coverArtURL = thumbnailURL
            self.cachedArtwork = nil
            self.cachedArtworkURL = nil
        }

        // Trigger UI Presentation
        self.isPlayerPresented = true

        // Reset Resume State
        self.pendingResumeVideoId = nil
        self.pendingResumeProgress = nil
        self.hasResumed = false
        
        // Check for saved progress
        if let status = VideoStatusManager.shared.getStatus(videoId: videoId),
           status.progress > 0.05 && status.progress < 0.95 {
            self.pendingResumeVideoId = videoId
            self.pendingResumeProgress = status.progress
        }
        
        // Start "Keep Alive" silent player
        // We only play it if we don't have a native AVPlayer (which we don't for YouTube)
        if player == nil {
             if silentPlayer == nil {
                 setupSilentAudio()
             }
             silentPlayer?.play()
        }
        
        updateNowPlayingInfo()
        startProgressTracking()
        startBackgroundTask()
    }

    func playStream(url: URL) {
        // ... (Native AVPlayer logic - unchanged mostly, but we pause silent player)
        silentPlayer?.stop()
        
        let playerItem = AVPlayerItem(url: url)
        if player == nil {
            player = AVPlayer(playerItem: playerItem)
        } else {
            player?.replaceCurrentItem(with: playerItem)
        }
        player?.play()
        isPlaying = true
        updateNowPlayingInfo()
        startBackgroundTask()
    }
    
    func stop() {
        if let player = player {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        silentPlayer?.stop()
        
        isPlaying = false
        currentTitle = ""
        currentAuthor = ""
        currentVideoId = nil
        coverArtURL = nil
        currentTime = 0
        duration = 0
        playbackRate = 1.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        stopProgressTracking()
    }
    
    func togglePlayPause() {
        if let player = player {
            // Native Player
            if player.timeControlStatus == .playing {
                player.pause()
                isPlaying = false
                endBackgroundTask()
            } else {
                startBackgroundTask()
                player.play()
                player.rate = playbackRate
                isPlaying = true
            }
        } else {
            // WebView Mode
            if isPlaying {
                 isPlaying = false
                 silentPlayer?.pause()
                 endBackgroundTask()
            } else {
                 startBackgroundTask()
                 isPlaying = true
                 if silentPlayer == nil { createAndLoadSilentFile() }
                 silentPlayer?.play()
            }
        }
        updateNowPlayingInfo()
    }
    
    func setPlaybackRate(_ rate: Float) {
        self.playbackRate = rate
        if let player = player {
            player.rate = rate
        }
        updateNowPlayingInfo()
    }
    
    func seek(to time: Double) {
        if let player = player {
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            player.seek(to: cmTime)
        }
        
        self.seekRequest = time
        self.currentTime = time
        updateNowPlayingInfo()
        
        if isPlaying {
            startBackgroundTask()
            // Ensure silent player is running if needed
             if player == nil && (silentPlayer == nil || !silentPlayer!.isPlaying) {
                 silentPlayer?.play()
             }
        }
    }

    func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()

        // Play
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }

            if let player = self.player {
                player.play()
                player.rate = self.playbackRate
            } else {
                if self.silentPlayer == nil { self.createAndLoadSilentFile() }
                self.silentPlayer?.play()
            }

            self.isPlaying = true
            self.startBackgroundTask()
            self.updateNowPlayingInfo()
            return .success
        }

        // Pause
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }

            if let player = self.player {
                player.pause()
            } else {
                self.silentPlayer?.pause()
            }

            self.isPlaying = false
            self.updateNowPlayingInfo()
            return .success
        }

        // Skip Backward (15 seconds)
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            let newTime = max(0, self.currentTime - 15)
            self.seek(to: newTime)
            return .success
        }

        // Skip Forward (30 seconds)
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            let newTime = min(self.duration, self.currentTime + 30)
            self.seek(to: newTime)
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
    
    func updateNowPlayingInfo() {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = currentTitle
        nowPlayingInfo[MPMediaItemPropertyArtist] = currentAuthor
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0.0
        nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = Double(playbackRate)
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        if duration > 0 { nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration }

        // Use cached artwork if available
        if let cached = cachedArtwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = cached
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        } else if let coverArtURL = coverArtURL {
            // Download artwork once, cache it, then set NowPlayingInfo
            // Set info immediately without artwork so lock screen is responsive
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

            let urlToCache = coverArtURL
            Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: urlToCache)
                    if let image = UIImage(data: data) {
                        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                        await MainActor.run {
                            // Only cache if the URL hasn't changed in the meantime
                            if self.coverArtURL == urlToCache {
                                self.cachedArtwork = artwork
                                self.cachedArtworkURL = urlToCache
                                // Re-set NowPlayingInfo with artwork
                                var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                                updatedInfo[MPMediaItemPropertyArtwork] = artwork
                                MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
                            }
                        }
                    }
                } catch {
                    print("Failed to download artwork: \(error)")
                }
            }
        } else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        }
    }
    
    // MARK: - Background Task Handling
    // We rely primarily on AVAudioSession and the 'audio' background mode.
    // However, we start a background task solely to keep the app alive during the transition
    // until the media is fully playing, helping the WebView survive the suspension.
    
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    
    private func startBackgroundTask() {
        // Only start if not already running
        guard bgTask == .invalid else { return }
        
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "MyTubeAudioTransition") { [weak self] in
            // Expiration handler
            self?.endBackgroundTask()
        }
        print("Background task started: \(bgTask)")
    }
    
    private func endBackgroundTask() {
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
            print("Background task ended")
        }
    }
    
    // MARK: - Video Status Tracking
    
    private var progressTimer: AnyCancellable?
    
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
        guard let videoId = currentVideoId, isPlaying else { return }
        
        var currentPos: Double = 0
        var totalDur: Double = 0
        
        if let player = player {
            currentPos = player.currentTime().seconds
            if let d = player.currentItem?.duration.seconds, !d.isNaN {
                totalDur = d
            }
        } else {
             // WebView case fallback
             currentPos = currentTime
             totalDur = duration
        }
        
        if totalDur > 0 {
            VideoStatusManager.shared.saveProgress(videoId: videoId, progress: currentPos, duration: totalDur)
        }
    }
}
