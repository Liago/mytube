import Foundation
import Combine

@MainActor
class CachedPlaylistViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let youtubeService = YouTubeService.shared
    private let videoStatusManager = VideoStatusManager.shared
    private let cacheService = CacheStatusService.shared
    
    func loadPlaylist() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // 1. Fetch all cached items (with download timestamps)
            let cachedItems = try await cacheService.fetchAllCachedItems()
            
            // 2. Filter out watched videos locally
            let unwatchedItems = cachedItems.filter { item in
                let isWatched = videoStatusManager.getStatus(videoId: item.id)?.isWatched ?? false
                return !isWatched
            }
            
            if unwatchedItems.isEmpty {
                self.videos = []
                isLoading = false
                return
            }
            
            let unwatchedIds = unwatchedItems.map { $0.id }
            
            // 3. Fetch video details for unwatched IDs
            // YouTube API allows maximum 50 IDs per request for videos list.
            // If there are more than 50, chunk them.
            var allFetchedVideos: [Video] = []
            let chunkSize = 50
            for i in stride(from: 0, to: unwatchedIds.count, by: chunkSize) {
                let end = min(i + chunkSize, unwatchedIds.count)
                let chunk = Array(unwatchedIds[i..<end])
                let fetchedChunk = try await youtubeService.fetchVideoDetails(videoIds: chunk)
                allFetchedVideos.append(contentsOf: fetchedChunk)
            }
            
            // 4. Sort videos by Download Date (newest first)
            let cacheDateDict: [String: Date] = unwatchedItems.reduce(into: [:]) { result, item in
                if let dateStr = item.cachedAt, let date = DateUtils.parseISOString(dateStr) {
                    result[item.id] = date
                }
            }
            
            allFetchedVideos.sort { (v1, v2) -> Bool in
                let d1 = cacheDateDict[v1.id] ?? Date.distantPast
                let d2 = cacheDateDict[v2.id] ?? Date.distantPast
                
                // Fallback to publishedAt if download dates are exactly identical (or missing)
                if d1 == d2 {
                    let p1 = DateUtils.parseISOString(v1.snippet.publishedAt ?? "") ?? Date.distantPast
                    let p2 = DateUtils.parseISOString(v2.snippet.publishedAt ?? "") ?? Date.distantPast
                    return p1 > p2
                }
                
                return d1 > d2
            }
            
            self.videos = allFetchedVideos
            
        } catch {
            self.errorMessage = error.localizedDescription
            print("CachedPlaylistViewModel: Error loading playlist - \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    func removeVideoLocally(videoId: String) {
        videos.removeAll { $0.id == videoId }
    }
}
