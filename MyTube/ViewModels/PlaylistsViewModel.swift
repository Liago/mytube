import Foundation
import Combine

@MainActor
class PlaylistsViewModel: ObservableObject {
    @Published var playlists: [Playlist] = []
    @Published var favoriteVideos: [PlaylistItem] = [] // Assuming one of the playlists is favorites
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let youtubeService = YouTubeService.shared
    
    func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            self.playlists = try await youtubeService.fetchMyPlaylists()
            // Optionally fetch items for the first playlist or a specific "Favorites" one if identified
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
