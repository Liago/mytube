import AVFoundation
import Foundation

/// Custom resource loader that intercepts AVPlayer requests and adds required HTTP headers
/// This is necessary because AVURLAsset doesn't reliably support custom HTTP headers
final class StreamResourceLoader: NSObject, AVAssetResourceLoaderDelegate {

    // Custom URL scheme to intercept requests
    static let customScheme = "ytstream"

    // Headers required for YouTube streams
    private let headers: [String: String] = [
        "User-Agent": "com.google.android.youtube/19.29.37 (Linux; U; Android 14; en_US) gzip",
        "Accept": "*/*",
        "Accept-Language": "en-US,en;q=0.9",
        "Origin": "https://www.youtube.com",
        "Referer": "https://www.youtube.com/"
    ]

    // Active data tasks for cancellation
    private var activeTasks: [Int: URLSessionDataTask] = [:]
    private let taskQueue = DispatchQueue(label: "StreamResourceLoader.taskQueue")

    // Lazy URLSession with custom configuration
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = headers
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    /// Convert a regular HTTPS URL to our custom scheme URL
    static func customURL(from originalURL: URL) -> URL? {
        guard var components = URLComponents(url: originalURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        // Store original scheme in a query parameter for later restoration
        let originalScheme = components.scheme ?? "https"
        components.scheme = customScheme

        // Add original scheme as query param if not already https
        if originalScheme != "https" {
            var queryItems = components.queryItems ?? []
            queryItems.append(URLQueryItem(name: "_originalScheme", value: originalScheme))
            components.queryItems = queryItems
        }

        return components.url
    }

    /// Convert our custom scheme URL back to the original HTTPS URL
    static func originalURL(from customURL: URL) -> URL? {
        guard var components = URLComponents(url: customURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        // Check for stored original scheme
        var originalScheme = "https"
        if let queryItems = components.queryItems,
           let schemeItem = queryItems.first(where: { $0.name == "_originalScheme" }),
           let scheme = schemeItem.value {
            originalScheme = scheme
            // Remove the _originalScheme parameter
            components.queryItems = queryItems.filter { $0.name != "_originalScheme" }
            if components.queryItems?.isEmpty == true {
                components.queryItems = nil
            }
        }

        components.scheme = originalScheme
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

        print("StreamResourceLoader: Loading \(originalURL.absoluteString.prefix(80))...")

        // Create request with headers
        var request = URLRequest(url: originalURL)
        request.httpMethod = "GET"

        // Add all required headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Handle range requests if present
        if let dataRequest = loadingRequest.dataRequest {
            let start = dataRequest.requestedOffset
            let length = dataRequest.requestedLength

            if dataRequest.requestsAllDataToEndOfResource {
                request.setValue("bytes=\(start)-", forHTTPHeaderField: "Range")
            } else {
                request.setValue("bytes=\(start)-\(start + Int64(length) - 1)", forHTTPHeaderField: "Range")
            }
            print("StreamResourceLoader: Range request: bytes=\(start)-\(start + Int64(length) - 1)")
        }

        // Create and start data task
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            self?.handleResponse(loadingRequest: loadingRequest, data: data, response: response, error: error)
        }

        // Store task for potential cancellation
        let taskId = task.taskIdentifier
        taskQueue.sync {
            activeTasks[taskId] = task
        }

        task.resume()
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        // Cancel any active tasks associated with this request
        taskQueue.sync {
            // We can't easily map loadingRequest to task, so this is a simple cleanup
            // In a more complex implementation, you'd track this mapping
        }
    }

    // MARK: - Response Handling

    private func handleResponse(loadingRequest: AVAssetResourceLoadingRequest,
                                data: Data?,
                                response: URLResponse?,
                                error: Error?) {

        // Check for errors
        if let error = error {
            print("StreamResourceLoader: Error - \(error.localizedDescription)")
            loadingRequest.finishLoading(with: error)
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            print("StreamResourceLoader: Invalid response type")
            loadingRequest.finishLoading(with: URLError(.badServerResponse))
            return
        }

        print("StreamResourceLoader: Response status: \(httpResponse.statusCode)")

        // Check for HTTP errors
        guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 206 else {
            print("StreamResourceLoader: HTTP error \(httpResponse.statusCode)")
            let error = NSError(domain: "StreamResourceLoader",
                               code: httpResponse.statusCode,
                               userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
            loadingRequest.finishLoading(with: error)
            return
        }

        // Fill in content information
        if let contentInfoRequest = loadingRequest.contentInformationRequest {
            // Set content type
            if let mimeType = httpResponse.mimeType {
                let uti = UTType(mimeType: mimeType)
                contentInfoRequest.contentType = uti?.identifier
            }

            // Set content length
            if let contentRangeHeader = httpResponse.value(forHTTPHeaderField: "Content-Range") {
                // Parse "bytes 0-999/5000" format
                if let totalSize = parseContentLength(from: contentRangeHeader) {
                    contentInfoRequest.contentLength = totalSize
                }
            } else if httpResponse.expectedContentLength > 0 {
                contentInfoRequest.contentLength = httpResponse.expectedContentLength
            }

            contentInfoRequest.isByteRangeAccessSupported = true
        }

        // Provide the data
        if let data = data, let dataRequest = loadingRequest.dataRequest {
            dataRequest.respond(with: data)
            print("StreamResourceLoader: Provided \(data.count) bytes")
        }

        loadingRequest.finishLoading()
    }

    private func parseContentLength(from contentRange: String) -> Int64? {
        // Parse "bytes 0-999/5000" to get 5000
        let parts = contentRange.split(separator: "/")
        if parts.count == 2, let total = Int64(parts[1]) {
            return total
        }
        return nil
    }

    // MARK: - Cleanup

    func cancelAllTasks() {
        taskQueue.sync {
            activeTasks.values.forEach { $0.cancel() }
            activeTasks.removeAll()
        }
    }
}

// MARK: - UTType Extension for MIME type conversion
import UniformTypeIdentifiers

extension UTType {
    init?(mimeType: String) {
        if let type = UTType(mimeType: mimeType) {
            self = type
        } else {
            // Fallback for common audio types
            switch mimeType {
            case "audio/mp4", "audio/m4a":
                self = .mpeg4Audio
            case "audio/webm":
                self = UTType("org.webmproject.webm") ?? .audio
            case "audio/mpeg", "audio/mp3":
                self = .mp3
            default:
                return nil
            }
        }
    }
}
