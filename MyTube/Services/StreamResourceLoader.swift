import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// Custom resource loader that intercepts AVPlayer requests and adds required HTTP headers
/// Uses streaming download to avoid YouTube's anti-download protection
final class StreamResourceLoader: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate {

    // Custom URL scheme to intercept requests
    static let customScheme = "ytstream"

    // Headers required for YouTube streams (Android client)
    private let headers: [String: String] = [
        "User-Agent": "com.google.android.youtube/19.29.37 (Linux; U; Android 14; en_US) gzip",
        "Accept": "*/*",
        "Accept-Language": "en-US,en;q=0.9",
        "Accept-Encoding": "identity",
        "Origin": "https://www.youtube.com",
        "Referer": "https://www.youtube.com/",
        "Connection": "keep-alive",
        "X-YouTube-Client-Name": "3",
        "X-YouTube-Client-Version": "19.29.37"
    ]

    // Active loading requests
    private var pendingRequests: [URLSessionTask: AVAssetResourceLoadingRequest] = [:]
    private var receivedData: [URLSessionTask: NSMutableData] = [:]
    private let requestQueue = DispatchQueue(label: "StreamResourceLoader.queue")

    // URLSession for streaming
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 1
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    /// Convert a regular HTTPS URL to our custom scheme URL
    static func customURL(from originalURL: URL) -> URL? {
        guard var components = URLComponents(url: originalURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = customScheme
        return components.url
    }

    /// Convert our custom scheme URL back to the original HTTPS URL
    static func originalURL(from customURL: URL) -> URL? {
        guard var components = URLComponents(url: customURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "https"
        return components.url
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {

        guard let requestURL = loadingRequest.request.url,
              let originalURL = StreamResourceLoader.originalURL(from: requestURL) else {
            print("StreamResourceLoader: Invalid URL")
            return false
        }

        return startDataRequest(loadingRequest: loadingRequest, url: originalURL)
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        requestQueue.sync {
            // Find and cancel the associated task
            for (task, request) in pendingRequests where request === loadingRequest {
                task.cancel()
                pendingRequests.removeValue(forKey: task)
                receivedData.removeValue(forKey: task)
                break
            }
        }
    }

    // MARK: - Data Request Handling

    private func startDataRequest(loadingRequest: AVAssetResourceLoadingRequest, url: URL) -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Add all required headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Handle range requests
        if let dataRequest = loadingRequest.dataRequest {
            let start = dataRequest.requestedOffset
            let length = Int64(dataRequest.requestedLength)

            if dataRequest.requestsAllDataToEndOfResource {
                request.setValue("bytes=\(start)-", forHTTPHeaderField: "Range")
                print("StreamResourceLoader: Range request: bytes=\(start)-")
            } else {
                // Request in smaller chunks to avoid 403
                let end = start + min(length, 2 * 1024 * 1024) - 1  // Max 2MB chunks
                request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
                print("StreamResourceLoader: Range request: bytes=\(start)-\(end)")
            }
        } else {
            print("StreamResourceLoader: Full request (no range)")
        }

        print("StreamResourceLoader: Loading \(url.host ?? "unknown")...")

        let task = session.dataTask(with: request)

        requestQueue.sync {
            pendingRequests[task] = loadingRequest
            receivedData[task] = NSMutableData()
        }

        task.resume()
        return true
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {

        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }

        print("StreamResourceLoader: Response status: \(httpResponse.statusCode)")

        // Check for HTTP errors
        guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 206 else {
            print("StreamResourceLoader: HTTP error \(httpResponse.statusCode)")
            completionHandler(.cancel)

            requestQueue.sync {
                if let loadingRequest = pendingRequests[dataTask] {
                    let error = NSError(domain: "StreamResourceLoader",
                                       code: httpResponse.statusCode,
                                       userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
                    loadingRequest.finishLoading(with: error)
                    pendingRequests.removeValue(forKey: dataTask)
                    receivedData.removeValue(forKey: dataTask)
                }
            }
            return
        }

        // Fill content information on first response
        requestQueue.sync {
            if let loadingRequest = pendingRequests[dataTask],
               let contentInfoRequest = loadingRequest.contentInformationRequest {

                // Set content type
                if let mimeType = httpResponse.mimeType {
                    contentInfoRequest.contentType = UTType.fromMIME(mimeType)?.identifier
                }

                // Set content length from Content-Range header
                if let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range"),
                   let totalLength = parseContentLength(from: contentRange) {
                    contentInfoRequest.contentLength = totalLength
                    print("StreamResourceLoader: Total content length: \(totalLength)")
                } else if httpResponse.expectedContentLength > 0 {
                    contentInfoRequest.contentLength = httpResponse.expectedContentLength
                }

                contentInfoRequest.isByteRangeAccessSupported = true
            }
        }

        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        requestQueue.sync {
            // Append data to buffer
            receivedData[dataTask]?.append(data)

            // Stream data to AVPlayer as it arrives
            if let loadingRequest = pendingRequests[dataTask],
               let dataRequest = loadingRequest.dataRequest {
                dataRequest.respond(with: data)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        requestQueue.sync {
            guard let loadingRequest = pendingRequests[task] else { return }

            if let error = error {
                print("StreamResourceLoader: Task error: \(error.localizedDescription)")
                loadingRequest.finishLoading(with: error)
            } else {
                let totalBytes = receivedData[task]?.length ?? 0
                print("StreamResourceLoader: Completed, total bytes: \(totalBytes)")
                loadingRequest.finishLoading()
            }

            pendingRequests.removeValue(forKey: task)
            receivedData.removeValue(forKey: task)
        }
    }

    // MARK: - Helpers

    private func parseContentLength(from contentRange: String) -> Int64? {
        // Parse "bytes 0-999/5000" to get 5000
        let parts = contentRange.split(separator: "/")
        if parts.count == 2, let total = Int64(parts[1]) {
            return total
        }
        return nil
    }

    func cancelAllTasks() {
        requestQueue.sync {
            for task in pendingRequests.keys {
                task.cancel()
            }
            pendingRequests.removeAll()
            receivedData.removeAll()
        }
    }
}

// MARK: - UTType Helper for MIME type conversion

extension UTType {
    /// Create UTType from MIME type string
    static func fromMIME(_ mimeType: String) -> UTType? {
        // Use Apple's API to convert MIME type to UTType
        if let type = UTType(tag: mimeType, tagClass: .mimeType, conformingTo: nil) {
            return type
        }

        // Fallback for common audio types that might not be recognized
        switch mimeType {
        case "audio/mp4", "audio/m4a", "audio/x-m4a":
            return .mpeg4Audio
        case "audio/webm":
            return UTType("org.webmproject.webm") ?? .audio
        case "audio/mpeg", "audio/mp3":
            return .mp3
        case "audio/aac":
            return UTType("public.aac-audio") ?? .mpeg4Audio
        case "audio/ogg":
            return UTType("org.xiph.ogg") ?? .audio
        default:
            return .audio
        }
    }
}
