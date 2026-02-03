import Foundation
import Network

/// Local HTTP proxy server that streams YouTube audio with proper headers
/// This bypasses YouTube's anti-download protection by streaming data progressively
final class LocalStreamProxy: NSObject, @unchecked Sendable {
    static let shared = LocalStreamProxy()

    private var listener: NWListener?
    private let port: UInt16 = 8765
    private let queue = DispatchQueue(label: "LocalStreamProxy.queue", qos: .userInitiated)

    private var currentRemoteURL: URL?
    private var isServerRunning = false

    // Headers for YouTube requests
    private let youtubeHeaders: [String: String] = [
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

    override private init() {
        super.init()
    }

    // MARK: - Server Management

    func startServer() async throws {
        guard !isServerRunning else {
            print("LocalStreamProxy: Server already running")
            return
        }

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let parameters = NWParameters.tcp
                    parameters.allowLocalEndpointReuse = true

                    self.listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: self.port))

                    self.listener?.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            self.isServerRunning = true
                            print("LocalStreamProxy: Server listening on port \(self.port)")
                            continuation.resume()
                        case .failed(let error):
                            self.isServerRunning = false
                            print("LocalStreamProxy: Server failed: \(error)")
                            continuation.resume(throwing: error)
                        case .cancelled:
                            self.isServerRunning = false
                            print("LocalStreamProxy: Server cancelled")
                        default:
                            break
                        }
                    }

                    self.listener?.newConnectionHandler = { [weak self] connection in
                        self?.handleConnection(connection)
                    }

                    self.listener?.start(queue: self.queue)

                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stopServer() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            self.isServerRunning = false
            print("LocalStreamProxy: Server stopped")
        }
    }

    func setRemoteURL(_ url: URL) {
        self.currentRemoteURL = url
        print("LocalStreamProxy: Set remote URL")
    }

    func getLocalURL() -> URL? {
        guard isServerRunning else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/audio.m4a")
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                self.receiveRequest(on: connection)
            case .failed(let error):
                print("LocalStreamProxy: Connection failed: \(error)")
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                print("LocalStreamProxy: Receive error: \(error)")
                connection.cancel()
                return
            }

            guard let data = data, !data.isEmpty else {
                if isComplete {
                    connection.cancel()
                }
                return
            }

            // Parse HTTP request
            if let requestString = String(data: data, encoding: .utf8) {
                self.handleHTTPRequest(requestString, on: connection)
            }
        }
    }

    private func handleHTTPRequest(_ request: String, on connection: NWConnection) {
        // Parse Range header if present
        var rangeStart: Int64 = 0
        var rangeEnd: Int64? = nil

        let lines = request.components(separatedBy: "\r\n")
        for line in lines {
            if line.lowercased().hasPrefix("range:") {
                let rangeValue = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                if rangeValue.hasPrefix("bytes=") {
                    let rangeSpec = String(rangeValue.dropFirst(6))
                    let parts = rangeSpec.split(separator: "-", omittingEmptySubsequences: false)
                    if parts.count >= 1, let start = Int64(parts[0]) {
                        rangeStart = start
                    }
                    if parts.count >= 2, !parts[1].isEmpty, let end = Int64(parts[1]) {
                        rangeEnd = end
                    }
                }
                break
            }
        }

        print("LocalStreamProxy: Request received, range: \(rangeStart)-\(rangeEnd?.description ?? "end")")

        // Stream from YouTube
        guard let remoteURL = currentRemoteURL else {
            sendErrorResponse(connection: connection, statusCode: 503, message: "No remote URL configured")
            return
        }

        streamFromYouTube(url: remoteURL, rangeStart: rangeStart, rangeEnd: rangeEnd, to: connection)
    }

    // MARK: - YouTube Streaming

    private func streamFromYouTube(url: URL, rangeStart: Int64, rangeEnd: Int64?, to connection: NWConnection) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Add YouTube headers
        for (key, value) in youtubeHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Add Range header
        if let end = rangeEnd {
            request.setValue("bytes=\(rangeStart)-\(end)", forHTTPHeaderField: "Range")
        } else {
            request.setValue("bytes=\(rangeStart)-", forHTTPHeaderField: "Range")
        }

        print("LocalStreamProxy: Requesting from YouTube with range: bytes=\(rangeStart)-\(rangeEnd?.description ?? "")")

        // Use streaming delegate
        let delegate = StreamingDelegate(connection: connection, rangeStart: rangeStart)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: request)
        delegate.task = task
        task.resume()
    }

    private func sendErrorResponse(connection: NWConnection, statusCode: Int, message: String) {
        let response = """
        HTTP/1.1 \(statusCode) \(message)\r
        Content-Type: text/plain\r
        Content-Length: \(message.count)\r
        Connection: close\r
        \r
        \(message)
        """

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

// MARK: - Streaming Delegate

private class StreamingDelegate: NSObject, URLSessionDataDelegate {
    let connection: NWConnection
    let rangeStart: Int64
    weak var task: URLSessionTask?

    private var totalBytesReceived: Int64 = 0
    private var headersSent = false
    private var contentLength: Int64 = 0

    init(connection: NWConnection, rangeStart: Int64) {
        self.connection = connection
        self.rangeStart = rangeStart
        super.init()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {

        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            sendErrorAndClose(statusCode: 502, message: "Invalid response")
            return
        }

        print("LocalStreamProxy: YouTube response: \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 206 else {
            completionHandler(.cancel)
            sendErrorAndClose(statusCode: httpResponse.statusCode, message: "YouTube error")
            return
        }

        // Parse content info
        var totalSize: Int64 = 0
        if let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range") {
            // Parse "bytes 0-999/5000"
            if let slashIndex = contentRange.lastIndex(of: "/"),
               let total = Int64(contentRange[contentRange.index(after: slashIndex)...]) {
                totalSize = total
            }
        }

        contentLength = httpResponse.expectedContentLength
        if contentLength < 0 {
            contentLength = totalSize - rangeStart
        }

        // Send HTTP response headers to AVPlayer
        var headers = "HTTP/1.1 \(httpResponse.statusCode == 206 ? "206 Partial Content" : "200 OK")\r\n"
        headers += "Content-Type: audio/mp4\r\n"
        headers += "Accept-Ranges: bytes\r\n"

        if totalSize > 0 {
            let endByte = rangeStart + contentLength - 1
            headers += "Content-Range: bytes \(rangeStart)-\(endByte)/\(totalSize)\r\n"
            headers += "Content-Length: \(contentLength)\r\n"
        } else if contentLength > 0 {
            headers += "Content-Length: \(contentLength)\r\n"
        }

        headers += "Connection: keep-alive\r\n"
        headers += "\r\n"

        connection.send(content: headers.data(using: .utf8), completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("LocalStreamProxy: Header send error: \(error)")
                self?.task?.cancel()
            } else {
                self?.headersSent = true
            }
        })

        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard headersSent else { return }

        totalBytesReceived += Int64(data.count)

        // Stream data to AVPlayer
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("LocalStreamProxy: Data send error: \(error)")
                self?.task?.cancel()
            }
        })

        // Log progress periodically
        if totalBytesReceived % (512 * 1024) < Int64(data.count) {
            print("LocalStreamProxy: Streamed \(totalBytesReceived / 1024)KB")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("LocalStreamProxy: Stream error: \(error.localizedDescription)")
        } else {
            print("LocalStreamProxy: Stream completed, total: \(totalBytesReceived) bytes")
        }

        // Close connection after a small delay to ensure all data is flushed
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.connection.cancel()
        }
        session.invalidateAndCancel()
    }

    private func sendErrorAndClose(statusCode: Int, message: String) {
        let response = "HTTP/1.1 \(statusCode) \(message)\r\nConnection: close\r\n\r\n"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { [weak self] _ in
            self?.connection.cancel()
        })
    }
}
