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
            
            // Log videos lost between R2 and YouTube API
            let fetchedIds = Set(allFetchedVideos.map { $0.id })
            let missingIds = unwatchedIds.filter { !fetchedIds.contains($0) }
            if !missingIds.isEmpty {
                print("CachedPlaylistViewModel: \(missingIds.count) videos not found by YouTube API: \(missingIds)")
            }

            // 4. Sort videos by publish date (oldest first)
            allFetchedVideos.sort { (v1, v2) -> Bool in
                let p1 = DateUtils.parseISOString(v1.snippet.publishedAt ?? "") ?? Date.distantPast
                let p2 = DateUtils.parseISOString(v2.snippet.publishedAt ?? "") ?? Date.distantPast
                return p1 < p2
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
