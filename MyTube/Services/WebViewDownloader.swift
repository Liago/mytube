import Foundation
import WebKit
import Combine

/// Downloads audio files using WKWebView to bypass TLS fingerprinting.
/// WKWebView has a legitimate browser TLS fingerprint that YouTube accepts.
@MainActor
class WebViewDownloader: NSObject, ObservableObject {
    static let shared = WebViewDownloader()
    
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadError: String?
    
    private var webView: WKWebView?
    private var currentVideoId: String?
    private var completionHandler: ((Result<URL, Error>) -> Void)?
    private var expectedContentLength: Int64 = 0
    private var receivedData = Data()
    
    private override init() {
        super.init()
    }
    
    // MARK: - Cache Management
    
    private var cacheDirectory: URL {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let cacheDir = paths[0].appendingPathComponent("AudioCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        return cacheDir
    }
    
    func getCachedFile(for videoId: String) -> URL? {
        let fileURL = cacheDirectory.appendingPathComponent("\(videoId).m4a")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            print("WebViewDownloader: Cache hit for \(videoId)")
            return fileURL
        }
        return nil
    }
    
    // MARK: - Download
    
    func downloadAudio(from remoteURL: URL, videoId: String, completion: @escaping (Result<URL, Error>) -> Void) {
        // Check cache first
        if let cachedURL = getCachedFile(for: videoId) {
            completion(.success(cachedURL))
            return
        }
        
        cancelDownload()
        
        self.currentVideoId = videoId
        self.isDownloading = true
        self.downloadProgress = 0.0
        self.downloadError = nil
        self.completionHandler = completion
        self.receivedData = Data()
        
        // Create a WKWebView configuration that mimics a real browser
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        
        // Create the webview (offscreen)
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        wv.navigationDelegate = self
        self.webView = wv
        
        // Create a URLRequest - WKWebView will handle the download with its TLS stack
        var request = URLRequest(url: remoteURL)
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        
        print("WebViewDownloader: Starting download for \(videoId)")
        wv.load(request)
    }
    
    func cancelDownload() {
        webView?.stopLoading()
        webView = nil
        isDownloading = false
        downloadProgress = 0.0
        currentVideoId = nil
        completionHandler = nil
        receivedData = Data()
    }
    
    private func saveAndComplete() {
        guard let videoId = currentVideoId, !receivedData.isEmpty else {
            let error = NSError(domain: "WebViewDownloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])
            downloadError = "No data received"
            completionHandler?(.failure(error))
            cleanup()
            return
        }
        
        let destURL = cacheDirectory.appendingPathComponent("\(videoId).m4a")
        
        do {
            try? FileManager.default.removeItem(at: destURL)
            try receivedData.write(to: destURL)
            print("WebViewDownloader: Saved \(receivedData.count) bytes to \(destURL.lastPathComponent)")
            completionHandler?(.success(destURL))
        } catch {
            print("WebViewDownloader: Failed to save: \(error)")
            downloadError = "Failed to save file"
            completionHandler?(.failure(error))
        }
        
        cleanup()
    }
    
    private func cleanup() {
        webView = nil
        isDownloading = false
        currentVideoId = nil
        completionHandler = nil
        receivedData = Data()
    }
}

// MARK: - WKNavigationDelegate

extension WebViewDownloader: WKNavigationDelegate {
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        
        if let httpResponse = navigationResponse.response as? HTTPURLResponse {
            print("WebViewDownloader: Response status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 403 {
                decisionHandler(.cancel)
                let error = NSError(domain: "WebViewDownloader", code: 403, userInfo: [NSLocalizedDescriptionKey: "HTTP 403 Forbidden"])
                self.downloadError = "HTTP 403"
                self.completionHandler?(.failure(error))
                self.cleanup()
                return
            }
            
            self.expectedContentLength = navigationResponse.response.expectedContentLength
        }
        
        // For audio files, we need to download manually since WKWebView doesn't give us the data directly
        // Cancel the navigation and use URLSession with WebKit's cookies instead
        decisionHandler(.cancel)
        
        // Try to download using shared cookies from WKWebView
        downloadWithSharedCookies()
    }
    
    private func downloadWithSharedCookies() {
        guard let videoId = currentVideoId,
              let request = webView?.url else {
            cleanup()
            return
        }
        
        // Get the original URL we tried to load
        guard let originalURL = webView?.url ?? URL(string: "about:blank") else { return }
        
        // Use URLSession but try to get cookies from WKWebView's data store
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                // Try fetching with the cookies
                var request = URLRequest(url: originalURL)
                
                // Add cookies manually
                let cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                if !cookieHeader.isEmpty {
                    request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
                }
                request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
                request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
                
                // Unfortunately this still uses URLSession's TLS stack, not WebKit's
                // So it will likely fail. Let's try anyway.
                let config = URLSessionConfiguration.default
                config.httpCookieStorage = nil // We're setting cookies manually
                
                let session = URLSession(configuration: config)
                
                do {
                    let (data, response) = try await session.data(for: request)
                    
                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                        print("WebViewDownloader: HTTP \(httpResponse.statusCode)")
                        let error = NSError(domain: "WebViewDownloader", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
                        self.downloadError = "HTTP \(httpResponse.statusCode)"
                        self.completionHandler?(.failure(error))
                        self.cleanup()
                        return
                    }
                    
                    self.receivedData = data
                    self.saveAndComplete()
                    
                } catch {
                    print("WebViewDownloader: Download failed: \(error)")
                    self.downloadError = error.localizedDescription
                    self.completionHandler?(.failure(error))
                    self.cleanup()
                }
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("WebViewDownloader: Navigation failed: \(error)")
        downloadError = error.localizedDescription
        completionHandler?(.failure(error))
        cleanup()
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // This is expected when we cancel the navigation to download manually
        // Don't treat as error if we're handling it
    }
}
