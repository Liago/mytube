import Foundation
import Combine

@MainActor
class HomeViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let youtubeService = YouTubeService.shared
    private let videoStatusManager = VideoStatusManager.shared
    private var allVideos: [Video] = []
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        videoStatusManager.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.filterVideos()
                }
            }
            .store(in: &cancellables)
    }
    
    func loadHomeVideos() async {
        isLoading = true
        errorMessage = nil
        videos = []
        allVideos = []
        
        do {
            let subscriptions = try await youtubeService.fetchSubscriptions()
            
            let targetSubscriptions = subscriptions.filter { sub in
                 guard let channelId = sub.snippet.resourceId.channelId else { return false }
                 return videoStatusManager.isHomeSubscription(channelId: channelId)
            }
            
            // Gather all playlist items concurrently
            let allItems = await withTaskGroup(of: [PlaylistItem].self) { group -> [PlaylistItem] in
                for sub in targetSubscriptions {
                    guard let channelId = sub.snippet.resourceId.channelId else { continue }
                    
                    group.addTask {
                        do {
                            // Replace UC with UU to get uploads playlist
                            var uploadsPlaylistId = channelId
                            if uploadsPlaylistId.starts(with: "UC") {
                                uploadsPlaylistId.replaceSubrange(uploadsPlaylistId.startIndex..<uploadsPlaylistId.index(uploadsPlaylistId.startIndex, offsetBy: 2), with: "UU")
                            }
                            
                            // Fetch items from this playlist
                            let (items, _) = try await self.youtubeService.fetchPlaylistItems(playlistId: uploadsPlaylistId, maxResults: 10)
                            
                            // Filter for today
                            let todayItems = items.filter { item in
                                guard let publishedAt = item.snippet.publishedAt else { return false }
                                return DateUtils.isToday(publishedAt)
                            }
                            return todayItems
                        } catch {
                            print("Failed to fetch uploads for \(sub.snippet.title): \(error)")
                            return []
                        }
                    }
                }
                
                var collectedItems: [PlaylistItem] = []
                for await channelVideos in group {
                    collectedItems.append(contentsOf: channelVideos)
                }
                return collectedItems
            }
            
            // Fetch video details for duration (this throws, so must be outside the non-throwing task group)
            let videoIds = allItems.map { $0.snippet.resourceId?.videoId ?? "" }.filter { !$0.isEmpty }
            
            // Since this is an async function on a MainActor class, this runs on MainActor
            self.allVideos = try await youtubeService.fetchVideoDetails(videoIds: videoIds)

            // Sort by date descending
            self.allVideos.sort { (v1, v2) -> Bool in
                guard let d1 = v1.snippet.publishedAt, let d2 = v2.snippet.publishedAt else { return false }
                return d1 > d2
            }
            
            filterVideos()
            
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func filterVideos() {
        self.videos = self.allVideos.filter { item in
            let isWatched = videoStatusManager.getStatus(videoId: item.id)?.isWatched ?? false
            return !isWatched
        }
    }
}
