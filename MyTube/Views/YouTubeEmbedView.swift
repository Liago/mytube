import SwiftUI
import WebKit

struct YouTubeEmbedView: UIViewRepresentable {
    let videoId: String
    @Binding var isPlaying: Bool
    @Binding var seekRequest: Double?
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "playbackState")
        config.userContentController = contentController
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.currentVideoId != videoId {
            context.coordinator.currentVideoId = videoId
            loadVideo(webView: uiView, videoId: videoId)
        }
        
        if isPlaying {
            uiView.evaluateJavaScript("playVideoSafe();")
        } else {
            uiView.evaluateJavaScript("pauseVideoSafe();")
        }
        
        if let seekTime = seekRequest {
            uiView.evaluateJavaScript("player.seekTo(\(seekTime), true);")
            DispatchQueue.main.async {
                self.seekRequest = nil
            }
        }
    }
    
    private func loadVideo(webView: WKWebView, videoId: String) {
        let embedHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                body { margin: 0; padding: 0; background-color: black; }
                #player { position: absolute; top: 0; left: 0; width: 100%; height: 100%; }
            </style>
        </head>
        <body>
            <div id="player"></div>
            <script>
                var tag = document.createElement('script');
                tag.src = "https://www.youtube.com/iframe_api";
                var firstScriptTag = document.getElementsByTagName('script')[0];
                firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);

                var player;
                function onYouTubeIframeAPIReady() {
                    player = new YT.Player('player', {
                        height: '100%',
                        width: '100%',
                        videoId: '\(videoId)',
                        playerVars: {
                            'playsinline': 1,
                            'controls': 0,
                            'autoplay': 1,
                            'modestbranding': 1,
                            'rel': 0,
                            'showinfo': 0,
                            'fs': 0,
                            'origin': 'https://www.example.com',
                            'widget_referrer': 'https://www.example.com'
                        },
                        events: {
                            'onReady': onPlayerReady,
                            'onStateChange': onPlayerStateChange,
                            'onError': onPlayerError
                        }
                    });
                }

                function onPlayerReady(event) {
                    event.target.playVideo();
                    startProgressLoop();
                }

                function onPlayerStateChange(event) {
                    window.webkit.messageHandlers.playbackState.postMessage({
                        type: 'stateChange',
                        data: event.data
                    });
                    if (event.data == YT.PlayerState.PLAYING) {
                        startProgressLoop();
                    }
                }
                
                function onPlayerError(event) {
                    window.webkit.messageHandlers.playbackState.postMessage({
                        type: 'error',
                        data: event.data
                    });
                }

                function playVideoSafe() {
                    if (player && player.playVideo) {
                        player.playVideo();
                    }
                }

                function pauseVideoSafe() {
                    if (player && player.pauseVideo) {
                        player.pauseVideo();
                    }
                }
                
                var progressInterval;
                function startProgressLoop() {
                    if (progressInterval) clearInterval(progressInterval);
                    progressInterval = setInterval(function() {
                        if (player && player.getCurrentTime) {
                            var currentTime = player.getCurrentTime();
                            var duration = player.getDuration();
                            window.webkit.messageHandlers.playbackState.postMessage({
                                type: 'timeUpdate',
                                currentTime: currentTime,
                                duration: duration
                            });
                        }
                    }, 500);
                }
            </script>
        </body>
        </html>
        """
        // Important: baseURL needs to be valid (http/https) for some API features
        webView.loadHTMLString(embedHTML, baseURL: URL(string: "https://www.example.com"))
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: YouTubeEmbedView
        var currentVideoId: String?
        
        init(_ parent: YouTubeEmbedView) {
            self.parent = parent
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let dict = message.body as? [String: Any],
                  let type = dict["type"] as? String else { return }
            
            DispatchQueue.main.async {
                switch type {
                case "stateChange":
                    if let state = dict["data"] as? Int {
                        // YT.PlayerState.PLAYING = 1
                        if state == 1 {
                            AudioPlayerService.shared.isPlaying = true
                        } else if state == 2 { // PAUSED
                            AudioPlayerService.shared.isPlaying = false
                        } else if state == 0 { // ENDED
                            AudioPlayerService.shared.isPlaying = false
                            // TODO: Implement playlist navigation
                            // AudioPlayerService.shared.playNext(autoPlay: true)
                        }
                    }
                case "timeUpdate":
                     if let currentTime = dict["currentTime"] as? Double,
                        let duration = dict["duration"] as? Double {
                         // Only update duration if positive (prevents overwriting valid URL-derived duration)
                         if duration > 0 {
                             AudioPlayerService.shared.duration = duration
                         }
                         AudioPlayerService.shared.currentTime = currentTime
                     }
                case "error":
                    print("YouTube Player Error: \(dict["data"] ?? "unknown")")
                default:
                    break
                }
            }
        }
    }
}
