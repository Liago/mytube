import SwiftUI

struct CachedPlaylistView: View {
    @StateObject private var viewModel = CachedPlaylistViewModel()
    @Environment(\.presentationMode) var presentationMode
    
    // Optional parameter to differentiate if presented from tab or player
    var isPresentedAsSheet: Bool = false
    
    var body: some View {
        Group {
            if isPresentedAsSheet {
                NavigationView {
                    content
                        .navigationTitle("Up Next")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Close") {
                                    presentationMode.wrappedValue.dismiss()
                                }
                            }
                        }
                }
            } else {
                NavigationView {
                    content
                        .navigationTitle("Playlist")
                }
            }
        }
    }
    
    @ViewBuilder
    private var content: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.all)
            
            if viewModel.isLoading {
                ProgressView("Loading Playlist...")
            } else if let error = viewModel.errorMessage {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                        .padding()
                    Text("Error loading playlist")
                        .font(.headline)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    
                    Button("Retry") {
                        Task { await viewModel.loadPlaylist() }
                    }
                    .padding()
                }
            } else if viewModel.videos.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    
                    Text("All caught up!")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("There are no new downloaded episodes.")
                        .foregroundColor(.secondary)
                    
                    Button("Refresh") {
                        Task { await viewModel.loadPlaylist() }
                    }
                    .padding(.top, 10)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.videos) { video in
                            VideoCardView(
                                videoId: video.id,
                                title: video.snippet.title,
                                channelName: video.snippet.channelTitle ?? "Unknown",
                                channelId: video.snippet.channelId ?? "",
                                date: DateUtils.parseISOString(video.snippet.publishedAt ?? ""),
                                duration: DateUtils.formatISO8601Duration(video.contentDetails.duration),
                                thumbnailURL: URL(string: video.snippet.thumbnails?.high?.url ?? video.snippet.thumbnails?.medium?.url ?? "")
                            ) {
                                // Action: play video
                                AudioPlayerService.shared.playVideo(
                                    videoId: video.id,
                                    title: video.snippet.title,
                                    author: video.snippet.channelTitle ?? "Unknown",
                                    thumbnailURL: URL(string: video.snippet.thumbnails?.high?.url ?? ""),
                                    publishedAt: video.snippet.publishedAt
                                )
                                
                                // Remove from local view immediately if played
                                // (Actually, the video won't be marked as watched immediately, but it's playing)
                                if isPresentedAsSheet {
                                    presentationMode.wrappedValue.dismiss()
                                }
                            } onChannelTap: { _ in
                                // Optional: navigate to channel (might need routing context)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
                .refreshable {
                    await viewModel.loadPlaylist()
                }
            }
        }
        .task {
            // Load only if empty, or force reload on appear
            await viewModel.loadPlaylist()
        }
        // Observe VideoStatusManager changes to automatically sync watched state
        .onReceive(VideoStatusManager.shared.objectWillChange) { _ in
            Task { @MainActor in
                // Minimal refresh if an item became watched
                let currentIds = viewModel.videos.map { $0.id }
                for id in currentIds {
                    if VideoStatusManager.shared.getStatus(videoId: id)?.isWatched == true {
                        viewModel.removeVideoLocally(videoId: id)
                    }
                }
            }
        }
    }
}
