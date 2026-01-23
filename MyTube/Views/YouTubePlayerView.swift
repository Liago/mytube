import SwiftUI
import WebKit

struct YouTubePlayerView: UIViewRepresentable {
    let videoId: String
    // Observe AudioPlayerService to react to play/pause state changes
    @ObservedObject var playerService = AudioPlayerService.shared
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Crucial for background audio in some cases
        config.allowsAirPlayForMediaPlayback = true
        
        let js = """
        console.log("Injecting Visibility Hacks...");
        
        // Mock Page Visibility API to always be visible
        Object.defineProperty(document, 'hidden', { get: function() { return false; } });
        Object.defineProperty(document, 'visibilityState', { get: function() { return 'visible'; } });
        Object.defineProperty(document, 'webkitHidden', { get: function() { return false; } });
        Object.defineProperty(document, 'webkitVisibilityState', { get: function() { return 'visible'; } });
        
        // Prevent events from bubbling up that might signal background state
        window.addEventListener('visibilitychange', function(e) { e.stopImmediatePropagation(); }, true);
        window.addEventListener('webkitvisibilitychange', function(e) { e.stopImmediatePropagation(); }, true);
        window.addEventListener('blur', function(e) { e.stopImmediatePropagation(); }, true);
        
        // Flag to track explicit user pause
        window.isUserPaused = false;
        
        // Heartbeat to keep JS execution alive if possible
        setInterval(function() {
            var v = document.getElementsByTagName('video')[0];
            if(v && !v.paused && !window.isUserPaused) {
                // Ensure audio track is enabled
                // console.log("Video is playing...");
            }
        }, 1000);
        """
        let userScript = WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        let contentController = WKUserContentController()
        contentController.addUserScript(userScript)
        contentController.add(context.coordinator, name: "logHandler")
        config.userContentController = contentController
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Load new video if ID changed
        if context.coordinator.currentVideoId != videoId {
            context.coordinator.currentVideoId = videoId
            // Reset user pause state for new video
            uiView.evaluateJavaScript("window.isUserPaused = false;")
            loadPlayer(uiView, videoId: videoId)
        }
        
        // React to isPlaying state changes
        // React to isPlaying state changes - DEDUPLICATED
        if context.coordinator.lastIsPlaying != playerService.isPlaying {
            context.coordinator.lastIsPlaying = playerService.isPlaying
            
            if playerService.isPlaying {
                 uiView.evaluateJavaScript("if(player) { window.isUserPaused = false; player.playVideo(); }")
            } else {
                 uiView.evaluateJavaScript("if(player) { window.isUserPaused = true; player.pauseVideo(); }")
            }
        }
        
        // Handle Playback Rate
        uiView.evaluateJavaScript("if(player && player.setPlaybackRate) { player.setPlaybackRate(\(playerService.playbackRate)); }")
        
        // Handle Seek Request
        // Handle Seek Request
        if let seekTo = playerService.seekRequest {
            // Check if this specific seek request has already been handled
            if context.coordinator.lastHandledSeek != seekTo {
                context.coordinator.lastHandledSeek = seekTo
                print("Executing Seek to: \(seekTo)")
                uiView.evaluateJavaScript("if(player) { player.seekTo(\(seekTo), true); }")
            }
        }
    }
    
    func loadPlayer(_ webView: WKWebView, videoId: String) {
        let html = """
        <!DOCTYPE html>
        <html>
        <body style="margin:0px;padding:0px;">
            <div id="player"></div>
            <script>
                var tag = document.createElement('script');
                tag.src = "https://www.youtube.com/iframe_api";
                var firstScriptTag = document.getElementsByTagName('script')[0];
                firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);

                var player;
                function onYouTubeIframeAPIReady() {
                    window.webkit.messageHandlers.logHandler.postMessage("API Ready");
                    player = new YT.Player('player', {
                        height: '100%',
                        width: '100%',
                        videoId: '\(videoId)',
                        playerVars: {
                            'playsinline': 1,
                            'autoplay': 1,
                            'controls': 0,
                            'origin': 'https://www.example.com'
                        },
                        events: {
                            'onReady': onPlayerReady,
                            'onStateChange': onPlayerStateChange,
                            'onError': onPlayerError
                        }
                    });
                }

                function onPlayerReady(event) {
                    window.webkit.messageHandlers.logHandler.postMessage("Player Ready");
                    event.target.playVideo();
                }

                function onPlayerStateChange(event) {
                    window.webkit.messageHandlers.logHandler.postMessage("State Change: " + event.data);
                    
                    // AUTO-RESUME CHECK
                    // Only resume if it wasn't a user-initiated pause
                    if (event.data === 2 && !window.isUserPaused) { 
                         window.webkit.messageHandlers.logHandler.postMessage("Detected SYSTEM PAUSE. Forcing RESUME...");
                         event.target.playVideo();
                    }
                }

                function onPlayerError(event) {
                    window.webkit.messageHandlers.logHandler.postMessage("Player Error: " + event.data);
                }
                
                // Keep-Alive Heartbeat & Time Polling
                setInterval(function() {
                   // console.log("Heartbeat");
                   if (player && player.getCurrentTime) {
                       var time = player.getCurrentTime();
                       var duration = player.getDuration();
                       window.webkit.messageHandlers.logHandler.postMessage("Time:" + time + ":" + duration);
                   }
                }, 1000);
            </script>
        </body>
        </html>
        """
        // Important: Set baseURL to match the origin
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.example.com"))
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: YouTubePlayerView
        var currentVideoId: String = ""
        var lastHandledSeek: Double?
        var lastIsPlaying: Bool?
        
        init(_ parent: YouTubePlayerView) {
            self.parent = parent
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? String else { return }
            
            if body.starts(with: "Time:") {
                let components = body.split(separator: ":")
                if components.count >= 3,
                   let time = Double(components[1]),
                   let duration = Double(components[2]) {
                    
                    DispatchQueue.main.async {
                        AudioPlayerService.shared.currentTime = time
                        AudioPlayerService.shared.duration = duration
                        // Trigger NowPlaying update occasionally or rely on the fact that changing these properties doesn't auto-update MPNowPlayingInfo
                        // To be efficient, we might only update MPNowPlayingInfo every few seconds or on play/pause
                        // For now, let's strictly update UI via ObservableObject and let MPNowPlayingInfo be updated by the periodic actions
                        
                        // Actually, updating NowPlayingInfo every second might be too heavy? 
                        // It's usually fine. Let's do it sparingly or rely on start/pause updates for the static info 
                        // and let `elapsedPlaybackTime` handle the ticking in the lock screen. 
                        // HOWEVER, if we seek or drift, we should update.
                        
                        if Int(time) % 5 == 0 { // Sync every 5 seconds to correct drift
                             AudioPlayerService.shared.updateNowPlayingInfo()
                        }
                    }
                }
            } else if message.name == "logHandler" {
                print("YT Player Log: \(body)")
            }
        }
    }
}
