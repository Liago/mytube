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
            // 1. Fetch all cached IDs
            let cachedIds = try await cacheService.fetchAllCachedIds()
            
            // 2. Filter out watched videos locally
            let unwatchedIds = cachedIds.filter { videoId in
                let isWatched = videoStatusManager.getStatus(videoId: videoId)?.isWatched ?? false
                return !isWatched
            }
            
            if unwatchedIds.isEmpty {
                self.videos = []
                isLoading = false
                return
            }
            
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
            
            // 4. Sort videos (e.g., newest first)
            allFetchedVideos.sort { (v1, v2) -> Bool in
                guard let d1 = v1.snippet.publishedAt, let d2 = v2.snippet.publishedAt else { return false }
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
