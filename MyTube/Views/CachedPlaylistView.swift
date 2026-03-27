import SwiftUI
import Combine

struct CachedPlaylistView: View {
    @StateObject private var viewModel = CachedPlaylistViewModel()
    @Environment(\.presentationMode) var presentationMode
    
    // Optional parameter to differentiate if presented from tab or player
    var isPresentedAsSheet: Bool = false
    
    var body: some View {
        Group {
            if isPresentedAsSheet {
                NavigationView {
                    mainContent
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
                    mainContent
                        .navigationTitle("Playlist")
                }
            }
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.all)
            
            if viewModel.isLoading {
                ProgressView("Loading Playlist...")
            } else if let error = viewModel.errorMessage {
                errorView(error)
            } else if viewModel.videos.isEmpty {
                emptyStateView
            } else {
                videoListView
            }
        }
        .task {
            await viewModel.loadPlaylist()
        }
        .onReceive(VideoStatusManager.shared.objectWillChange) { _ in
            syncWatchedState()
        }
    }
    
    @ViewBuilder
    private func errorView(_ error: String) -> some View {
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
    }
    
    private var emptyStateView: some View {
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
    }
    
    private var videoListView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(viewModel.videos) { video in
                    videoCard(for: video)
                }
            }
            .padding(.vertical)
        }
        .refreshable {
            await viewModel.loadPlaylist()
        }
    }
    
    @ViewBuilder
    private func videoCard(for video: Video) -> some View {
        VideoCardView(
            videoId: video.id,
            title: video.snippet.title,
            channelName: video.snippet.channelTitle ?? "Unknown",
            channelId: video.snippet.channelId ?? "",
            date: DateUtils.parseISOString(video.snippet.publishedAt ?? ""),
            duration: DateUtils.formatDuration(video.contentDetails.duration),
            thumbnailURL: URL(string: video.snippet.thumbnails?.high?.url ?? video.snippet.thumbnails?.medium?.url ?? "")
        ) {
            playVideo(video)
        } onChannelTap: { _ in
            // Optional: navigate to channel
        }
        .padding(.horizontal)
    }
    
    private func playVideo(_ video: Video) {
        AudioPlayerService.shared.playVideo(
            videoId: video.id,
            title: video.snippet.title,
            author: video.snippet.channelTitle ?? "Unknown",
            thumbnailURL: URL(string: video.snippet.thumbnails?.high?.url ?? ""),
            publishedAt: video.snippet.publishedAt
        )
        
        if isPresentedAsSheet {
            presentationMode.wrappedValue.dismiss()
        }
    }
    
    private func syncWatchedState() {
        Task { @MainActor in
            let currentIds = viewModel.videos.map { $0.id }
            for id in currentIds {
                if VideoStatusManager.shared.getStatus(videoId: id)?.isWatched == true {
                    viewModel.removeVideoLocally(videoId: id)
                }
            }
        }
    }
}
