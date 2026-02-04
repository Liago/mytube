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
            #if targetEnvironment(simulator)
            let baseURL = "http://localhost:8888"
            #else
            let baseURL = "https://mytube-be.netlify.app"
            #endif
            
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
}
