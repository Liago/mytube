import Foundation
import Combine

/// Service to check if audio files are already cached on the backend (R2).
@MainActor
class CacheStatusService: ObservableObject {
    static let shared = CacheStatusService()
    
    @Published var cachedVideoIds: Set<String> = []
    
    private var pendingCheckIds: Set<String> = []
    private var checkTask: Task<Void, Never>?
    
    private init() {}
    
    /// Checks status for a single video (queues it for batch processing)
    func checkStatus(for videoId: String) {
        guard !cachedVideoIds.contains(videoId) else { return }
        
        pendingCheckIds.insert(videoId)
        scheduleBatchCheck()
    }
    
    /// Checks status for multiple videos
    func checkStatus(for videoIds: [String]) {
        let newIds = videoIds.filter { !cachedVideoIds.contains($0) }
        guard !newIds.isEmpty else { return }
        
        newIds.forEach { pendingCheckIds.insert($0) }
        scheduleBatchCheck()
    }
    
    private func scheduleBatchCheck() {
        // Debounce requests
        checkTask?.cancel()
        checkTask = Task {
            do {
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
                
                // Execute in a new Task to avoid cancellation if checkTask is cancelled
                // (e.g. by a subsequent scheduleBatchCheck call) while the request is running.
                Task {
                    await performBatchCheck()
                }
            } catch {
                // Task cancelled during sleep, do nothing
            }
        }
    }
    
    private func performBatchCheck() async {
        let idsToCheck = Array(pendingCheckIds.prefix(50)) // Limit batch size
        guard !idsToCheck.isEmpty else { return }
        
        // Clear them from pending immediately so we don't re-check if call fails (retry logic could be added)
        idsToCheck.forEach { pendingCheckIds.remove($0) }
        
        do {
            let baseURL = "https://mytube-be.netlify.app"
            
            let url = URL(string: "\(baseURL)/.netlify/functions/check-cache")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(Secrets.apiSecret, forHTTPHeaderField: "x-api-key")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["ids": idsToCheck])
            
            let (data, _) = try await URLSession.shared.data(for: request)
            
            struct CacheResponse: Decodable {
                let found: [String]
                let missing: [String]
            }
            
            let result = try JSONDecoder().decode(CacheResponse.self, from: data)
            
            // Update Published property on MainActor
            result.found.forEach { self.cachedVideoIds.insert($0) }
            print("CacheStatusService: Found \(result.found.count) cached videos")
            
        } catch {
            print("CacheStatusService: Error checking cache status: \(error)")
            // Re-queue on failure? For now, just ignore.
        }
        
        // If there are more pending, schedule another run
        if !pendingCheckIds.isEmpty {
            scheduleBatchCheck()
        }
    }
    
    func isCached(_ videoId: String) -> Bool {
        return cachedVideoIds.contains(videoId)
    }
    
    struct CachedItem: Decodable {
        let id: String
        let cachedAt: String?
    }

    /// Fetches all cached IDs from the backend
    func fetchAllCachedIds() async throws -> [String] {
        let baseURL = "https://mytube-be.netlify.app"
        
        let url = URL(string: "\(baseURL)/.netlify/functions/check-cache")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Secrets.apiSecret, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["ids": []]) // Empty ids triggers fetch all
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("CacheStatusService: Error. Server returned \(String(data: data, encoding: .utf8) ?? "nil")")
            throw URLError(.badServerResponse)
        }
        
        struct CacheResponse: Decodable {
            let found: [String]
        }
        
        let result = try JSONDecoder().decode(CacheResponse.self, from: data)
        
        // Update local cache state just in case
        result.found.forEach { self.cachedVideoIds.insert($0) }
        
        return result.found
    }

    /// Fetches all cached items from the backend, including download timestamps
    func fetchAllCachedItems() async throws -> [CachedItem] {
        let baseURL = "https://mytube-be.netlify.app"
        
        let url = URL(string: "\(baseURL)/.netlify/functions/check-cache")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Secrets.apiSecret, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["ids": []])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("CacheStatusService: Error. Server returned \(String(data: data, encoding: .utf8) ?? "nil")")
            throw URLError(.badServerResponse)
        }
        
        struct CacheItemsResponse: Decodable {
            let found: [String]
            let cachedItems: [CachedItem]?
        }
        
        let result = try JSONDecoder().decode(CacheItemsResponse.self, from: data)
        
        // Update local cache state just in case
        result.found.forEach { self.cachedVideoIds.insert($0) }
        
        // Return parsed objects if available (new backend), otherwise fallback to strings
        if let items = result.cachedItems {
            return items
        } else {
            return result.found.map { CachedItem(id: $0, cachedAt: nil) }
        }
    }
}
