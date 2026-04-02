import SwiftUI
import Combine

enum PlaylistTab: String, CaseIterable {
    case cached = "Cached"
    case queue = "Coda"
}

struct CachedPlaylistView: View {
    @StateObject private var viewModel = CachedPlaylistViewModel()
    @ObservedObject private var prefetchService = PrefetchQueueService.shared
    @Environment(\.presentationMode) var presentationMode

    // Optional parameter to differentiate if presented from tab or player
    var isPresentedAsSheet: Bool = false

    @State private var selectedTab: PlaylistTab = .cached

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
        VStack(spacing: 0) {
            if !isPresentedAsSheet {
                Picker("View", selection: $selectedTab) {
                    ForEach(PlaylistTab.allCases, id: \.self) { tab in
                        if tab == .queue {
                            Text("\(tab.rawValue) (\(prefetchService.queueItems.count))").tag(tab)
                        } else {
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }

            if selectedTab == .cached || isPresentedAsSheet {
                cachedContent
            } else {
                PrefetchQueueView()
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .task {
            await prefetchService.fetchQueueIfNeeded()
        }
    }

    @ViewBuilder
    private var cachedContent: some View {
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
            LazyVStack(spacing: 0) {
                ForEach(viewModel.videos) { video in
                    Button(action: { playVideo(video) }) {
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: video.snippet.thumbnails?.medium?.url ?? video.snippet.thumbnails?.defaultThumbnail?.url ?? "")) { image in
                                image.resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                ZStack {
                                    Color.gray.opacity(0.3)
                                    Image(systemName: "music.note")
                                        .foregroundColor(.gray)
                                }
                            }
                            .frame(width: 100, height: 56)
                            .cornerRadius(6)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(video.snippet.title)
                                    .font(.footnote)
                                    .fontWeight(.semibold)
                                    .lineLimit(2)
                                    .foregroundColor(.primary)

                                HStack(spacing: 4) {
                                    Text(video.snippet.channelTitle ?? "")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    if let date = video.snippet.publishedAt {
                                        Text("• \(DateUtils.formatISOString(date))")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Divider()
                        .padding(.leading, 128)
                }
            }
        }
        .refreshable {
            await viewModel.loadPlaylist()
        }
    }
    
    private func playVideo(_ video: Video) {
        let queueItems = viewModel.videos.map { v in
            QueueItem(
                videoId: v.id,
                title: v.snippet.title,
                author: v.snippet.channelTitle ?? "Unknown",
                thumbnailURL: URL(string: v.snippet.thumbnails?.high?.url ?? ""),
                publishedAt: v.snippet.publishedAt
            )
        }
        if let index = viewModel.videos.firstIndex(where: { $0.id == video.id }) {
            AudioPlayerService.shared.setQueue(items: queueItems, startIndex: index)
        }

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
