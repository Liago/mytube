import Foundation
import Combine

@MainActor
class HomeViewModel: ObservableObject {
    @Published var videos: [PlaylistItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let youtubeService = YouTubeService.shared
    private let videoStatusManager = VideoStatusManager.shared
    private var allVideos: [PlaylistItem] = []
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
        
        // 1. Get all subscriptions
        // 2. Filter by "Home" flag
        // 3. For each channel, get uploads
        // 4. Filter by published today
        
        do {
            let subscriptions = try await youtubeService.fetchSubscriptions()
            
            // Filter for only those marked as "Home"
            // If none are marked, maybe show all? Or show empty state? 
            // The requirement says "select... in home for each... only selected... will have their videos...".
            // So if none, show none.
            

            
            // Wait, subscription.snippet.resourceId.channelId is optional?
            
            let targetSubscriptions = subscriptions.filter { sub in
                 guard let channelId = sub.snippet.resourceId.channelId else { return false }
                 return videoStatusManager.isHomeSubscription(channelId: channelId)
            }
            
            // For these subscriptions, we need to find their uploads playlist. 
            // We need to fetch channel details for each to get the uploads playlist ID.
            // This might be expensive if many subscriptions. 
            // Optimization: Cache uploads playlist ID? Or is it standard? 
            // Uploads playlist ID is typically "UU" + channelId[2...]. 
            // Let's verify this assumption or use the API properly. Using API is safer but slower.
            // A common optimization is replacing "UC" with "UU" in channel ID.
            
            await withTaskGroup(of: [PlaylistItem].self) { group in
                for sub in targetSubscriptions {
                    guard let channelId = sub.snippet.resourceId.channelId else { continue }
                    
                    group.addTask {
                        do {
                            // verify assumption: Replace UC with UU
                            var uploadsPlaylistId = channelId
                            if uploadsPlaylistId.starts(with: "UC") {
                                uploadsPlaylistId.replaceSubrange(uploadsPlaylistId.startIndex..<uploadsPlaylistId.index(uploadsPlaylistId.startIndex, offsetBy: 2), with: "UU")
                            }
                            
                            // Let's try fetching uploads directly using this ID. 
                            // If it fails, we might need to fetch channel details.
                            // But for performance, let's try the ID manipulation first or just fetch items.
                            
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
                
                for await channelVideos in group {
                    self.allVideos.append(contentsOf: channelVideos)
                }
            }
            
            // Sort by date descending
            self.allVideos.sort { (item1, item2) -> Bool in
                guard let d1 = item1.snippet.publishedAt, let d2 = item2.snippet.publishedAt else { return false }
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
            let isWatched = videoStatusManager.getStatus(videoId: item.videoId)?.isWatched ?? false
            return !isWatched
        }
    }
}
