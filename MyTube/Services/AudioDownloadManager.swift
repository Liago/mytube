import Foundation
import Combine

/// Manages downloading audio files locally before playback.
/// This bypasses 403 errors by downloading the entire file first.
@MainActor
class AudioDownloadManager: NSObject, ObservableObject {
    static let shared = AudioDownloadManager()
    
    // Published state for UI
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var currentVideoId: String?
    @Published var downloadError: String?
    
    private var downloadTask: URLSessionDownloadTask?
    private var session: URLSession!
    private var progressObserver: NSKeyValueObservation?
    
    // Callback for completion
    private var completionHandler: ((Result<URL, Error>) -> Void)?
    
    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300 // 5 minutes for large files
        config.timeoutIntervalForResource = 600 // 10 minutes total
        session = URLSession(configuration: config, delegate: nil, delegateQueue: .main)
    }
    
    // MARK: - Cache Management
    
    private var cacheDirectory: URL {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let cacheDir = paths[0].appendingPathComponent("AudioCache", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        
        return cacheDir
    }
    
    /// Returns the local file URL for a video if it exists in cache
    func getCachedFile(for videoId: String) -> URL? {
        let fileURL = cacheDirectory.appendingPathComponent("\(videoId).m4a")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            print("AudioDownloadManager: Cache hit for \(videoId)")
            return fileURL
        }
        return nil
    }
    
    /// Clears old cache files (older than 7 days)
    func clearOldCache() {
        let fileManager = FileManager.default
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return
        }
        
        for file in files {
            guard let attributes = try? fileManager.attributesOfItem(atPath: file.path),
                  let modDate = attributes[.modificationDate] as? Date else {
                continue
            }
            
            if modDate < sevenDaysAgo {
                try? fileManager.removeItem(at: file)
                print("AudioDownloadManager: Removed old cache file: \(file.lastPathComponent)")
            }
        }
    }
    
    /// Returns total cache size in bytes
    func getCacheSize() -> Int64 {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        for file in files {
            if let attributes = try? fileManager.attributesOfItem(atPath: file.path),
               let size = attributes[.size] as? Int64 {
                totalSize += size
            }
        }
        return totalSize
    }
    
    /// Clears entire cache
    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        print("AudioDownloadManager: Cache cleared")
    }
    
    // MARK: - Download
    
    /// Downloads audio from the given URL and saves it locally
    /// - Parameters:
    ///   - remoteURL: The YouTube audio stream URL
    ///   - videoId: The video ID for cache naming
    ///   - completion: Called with the local file URL on success, or error on failure
    func downloadAudio(from remoteURL: URL, videoId: String, completion: @escaping (Result<URL, Error>) -> Void) {
        // Check cache first
        if let cachedURL = getCachedFile(for: videoId) {
            completion(.success(cachedURL))
            return
        }
        
        // Cancel any existing download
        cancelDownload()
        
        self.currentVideoId = videoId
        self.isDownloading = true
        self.downloadProgress = 0.0
        self.downloadError = nil
        self.completionHandler = completion
        
        // Create request with headers to mimic Safari on iOS (matches iOS TLS fingerprint)
        var request = URLRequest(url: remoteURL)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        
        print("AudioDownloadManager: Starting download for \(videoId)")
        
        let task = session.downloadTask(with: request) { [weak self] tempURL, response, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                self.isDownloading = false
                self.progressObserver?.invalidate()
                self.progressObserver = nil
                
                if let error = error {
                    print("AudioDownloadManager: Download failed: \(error)")
                    self.downloadError = error.localizedDescription
                    self.completionHandler?(.failure(error))
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    let error = NSError(domain: "AudioDownloadManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                    self.downloadError = "Invalid response"
                    self.completionHandler?(.failure(error))
                    return
                }
                
                guard httpResponse.statusCode == 200 else {
                    let error = NSError(domain: "AudioDownloadManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
                    print("AudioDownloadManager: HTTP error \(httpResponse.statusCode)")
                    self.downloadError = "HTTP \(httpResponse.statusCode)"
                    self.completionHandler?(.failure(error))
                    return
                }
                
                guard let tempURL = tempURL else {
                    let error = NSError(domain: "AudioDownloadManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "No file downloaded"])
                    self.downloadError = "No file downloaded"
                    self.completionHandler?(.failure(error))
                    return
                }
                
                // Move to cache directory
                let destURL = self.cacheDirectory.appendingPathComponent("\(videoId).m4a")
                
                do {
                    // Remove existing file if any
                    try? FileManager.default.removeItem(at: destURL)
                    try FileManager.default.moveItem(at: tempURL, to: destURL)
                    
                    print("AudioDownloadManager: Download complete, saved to \(destURL.lastPathComponent)")
                    self.completionHandler?(.success(destURL))
                } catch {
                    print("AudioDownloadManager: Failed to save file: \(error)")
                    self.downloadError = "Failed to save file"
                    self.completionHandler?(.failure(error))
                }
            }
        }
        
        // Observe progress
        progressObserver = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Task { @MainActor [weak self] in
                self?.downloadProgress = progress.fractionCompleted
            }
        }
        
        downloadTask = task
        task.resume()
    }
    
    /// Cancels the current download
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        progressObserver?.invalidate()
        progressObserver = nil
        isDownloading = false
        downloadProgress = 0.0
        currentVideoId = nil
        completionHandler = nil
    }
}
