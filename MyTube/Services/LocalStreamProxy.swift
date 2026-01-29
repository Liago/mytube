import Foundation
import Network

/// A lightweight local HTTP proxy server that relays YouTube audio streams to AVPlayer.
/// This bypasses YouTube's connection throttling for large files by handling the connection ourselves.
/// Uses streaming to forward data in real-time as it's downloaded.
final class LocalStreamProxy: NSObject, @unchecked Sendable {
    static let shared = LocalStreamProxy()
    
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let port: UInt16 = 8765
    private let queue = DispatchQueue(label: "com.mytube.streamproxy")
    private let lock = NSLock()
    
    private(set) var isRunning = false
    private var currentRemoteURL: URL?
    private var expectedHeaders: [String: String] = [:]
    
    private override init() {
        super.init()
    }
    
    /// Start the local proxy server
    func startServer() async throws {
        guard !isRunning else { return }
        
        let parameters = NWParameters.tcp
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port))
        
        listener?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                print("LocalStreamProxy: Server listening on port \(self.port)")
                self.lock.lock()
                self.isRunning = true
                self.lock.unlock()
            case .failed(let error):
                print("LocalStreamProxy: Server failed: \(error)")
                self.lock.lock()
                self.isRunning = false
                self.lock.unlock()
            case .cancelled:
                print("LocalStreamProxy: Server cancelled")
                self.lock.lock()
                self.isRunning = false
                self.lock.unlock()
            default:
                break
            }
        }
        
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        
        listener?.start(queue: queue)
        
        // Wait a bit for server to be ready
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
    }
    
    /// Stop the proxy server
    func stopServer() {
        listener?.cancel()
        listener = nil
        
        lock.lock()
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()
        isRunning = false
        lock.unlock()
        
        print("LocalStreamProxy: Server stopped")
    }
    
    /// Set the remote URL that the proxy will serve
    func setRemoteURL(_ url: URL, headers: [String: String] = [:]) {
        lock.lock()
        currentRemoteURL = url
        expectedHeaders = headers
        lock.unlock()
        print("LocalStreamProxy: Set remote URL to \(url.absoluteString.prefix(100))...")
    }
    
    /// Get the local URL that AVPlayer should use
    func getLocalURL() -> URL? {
        lock.lock()
        let running = isRunning
        lock.unlock()
        guard running else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/stream")
    }
    
    // MARK: - Connection Handling
    
    private func handleNewConnection(_ connection: NWConnection) {
        lock.lock()
        connections.append(connection)
        lock.unlock()
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveRequest(on: connection)
            case .failed(let error):
                print("LocalStreamProxy: Connection failed: \(error)")
                connection.cancel()
            case .cancelled:
                self?.lock.lock()
                self?.connections.removeAll { $0 === connection }
                self?.lock.unlock()
            default:
                break
            }
        }
        
        connection.start(queue: queue)
    }
    
    private func receiveRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self = self, let data = data else {
                if let error = error {
                    print("LocalStreamProxy: Receive error: \(error)")
                }
                connection.cancel()
                return
            }
            
            // Parse HTTP request to get Range header if present
            let requestString = String(data: data, encoding: .utf8) ?? ""
            let rangeHeader = self.parseRangeHeader(from: requestString)
            
            // Get current URL and headers
            self.lock.lock()
            let remoteURL = self.currentRemoteURL
            let headers = self.expectedHeaders
            self.lock.unlock()
            
            // Use streaming proxy for the request
            self.streamProxyRequest(to: connection, remoteURL: remoteURL, headers: headers, rangeHeader: rangeHeader)
        }
    }
    
    private func parseRangeHeader(from request: String) -> String? {
        let lines = request.components(separatedBy: "\r\n")
        for line in lines {
            if line.lowercased().hasPrefix("range:") {
                return String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
    
    // MARK: - Streaming Proxy
    
    private func streamProxyRequest(to connection: NWConnection, remoteURL: URL?, headers: [String: String], rangeHeader: String?) {
        guard let remoteURL = remoteURL else {
            sendErrorResponse(to: connection, statusCode: 500, message: "No remote URL configured")
            return
        }
        
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 300  // 5 minutes for large files
        
        // Add required headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Forward Range header if present
        if let rangeHeader = rangeHeader {
            request.setValue(rangeHeader, forHTTPHeaderField: "Range")
            print("LocalStreamProxy: Forwarding Range: \(rangeHeader)")
        }
        
        // Create a streaming delegate
        let delegate = StreamingDelegate(connection: connection, queue: queue)
        
        // Create a session with our delegate for streaming
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        
        let task = session.dataTask(with: request)
        task.resume()
    }
    
    private func sendErrorResponse(to connection: NWConnection, statusCode: Int, message: String) {
        let response = """
        HTTP/1.1 \(statusCode) Error\r
        Content-Type: text/plain\r
        Content-Length: \(message.count)\r
        Connection: close\r
        \r
        \(message)
        """
        
        if let data = response.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}

// MARK: - Streaming Delegate

/// Delegate that streams data from URLSession to NWConnection in real-time
private class StreamingDelegate: NSObject, URLSessionDataDelegate {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var headersSent = false
    private var totalBytesReceived = 0
    
    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
        super.init()
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }
        
        print("LocalStreamProxy: Upstream response: \(httpResponse.statusCode)")
        
        // Check for error status codes
        if httpResponse.statusCode >= 400 {
            print("LocalStreamProxy: Upstream error \(httpResponse.statusCode)")
            sendError(statusCode: httpResponse.statusCode)
            completionHandler(.cancel)
            return
        }
        
        // Build and send response headers immediately
        let statusText = httpResponse.statusCode == 206 ? "Partial Content" : "OK"
        var responseHeaders = "HTTP/1.1 \(httpResponse.statusCode) \(statusText)\r\n"
        responseHeaders += "Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "audio/mp4")\r\n"
        
        // Forward Content-Length if present
        if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length") {
            responseHeaders += "Content-Length: \(contentLength)\r\n"
        }
        
        responseHeaders += "Accept-Ranges: bytes\r\n"
        
        // Forward Content-Range if present (for partial content)
        if let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range") {
            responseHeaders += "Content-Range: \(contentRange)\r\n"
        }
        
        responseHeaders += "Connection: close\r\n\r\n"
        
        // Send headers
        if let headerData = responseHeaders.data(using: .utf8) {
            connection.send(content: headerData, completion: .contentProcessed { [weak self] error in
                if let error = error {
                    print("LocalStreamProxy: Header send error: \(error)")
                } else {
                    self?.headersSent = true
                }
            })
        }
        
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        totalBytesReceived += data.count
        
        // Stream data to connection immediately as it arrives
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("LocalStreamProxy: Data send error: \(error)")
            }
        })
        
        // Log progress periodically
        if totalBytesReceived % (1024 * 1024) < data.count {  // Every ~1MB
            print("LocalStreamProxy: Streamed \(totalBytesReceived / 1024)KB so far...")
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("LocalStreamProxy: Stream error: \(error)")
            sendError(statusCode: 502)
        } else {
            print("LocalStreamProxy: Stream completed, total: \(totalBytesReceived) bytes")
        }
        
        // Close connection
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
            self?.connection.cancel()
        })
        
        session.invalidateAndCancel()
    }
    
    private func sendError(statusCode: Int) {
        let message = "Upstream error: \(statusCode)"
        let response = """
        HTTP/1.1 \(statusCode) Error\r
        Content-Type: text/plain\r
        Content-Length: \(message.count)\r
        Connection: close\r
        \r
        \(message)
        """
        
        if let data = response.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed { [weak self] _ in
                self?.connection.cancel()
            })
        }
    }
}
