import SwiftUI
import Combine

struct ChannelDetailView: View {
    let subscription: Subscription
    @StateObject private var viewModel = ChannelDetailViewModel()
    @ObservedObject private var videoStatusManager = VideoStatusManager.shared
    @ObservedObject private var cacheService = CacheStatusService.shared
    
    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Oops! Something went wrong.")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("Retry") {
                        Task { await viewModel.loadData(channelId: subscription.snippet.resourceId.channelId ?? "") }
                    }
                    .buttonStyle(.bordered)
                }

            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.videos) { video in
                            let videoStatus = videoStatusManager.getStatus(videoId: video.videoId)
                            let isNew = videoStatusManager.isVideoNew(
                                publishedAt: video.snippet.publishedAt ?? "",
                                lastVisit: viewModel.previousVisitDate
                            )
                            let isPublishedToday = DateUtils.isToday(video.snippet.publishedAt ?? "")
                            
                            Button(action: {
                                AudioPlayerService.shared.playVideo(
                                    videoId: video.videoId,
                                    title: video.snippet.title,
                                    author: video.snippet.channelTitle ?? "",
                                    thumbnailURL: URL(string: video.snippet.thumbnails?.high?.url ?? ""),
                                    publishedAt: video.snippet.publishedAt // Pass date
                                )
                            }) {
                                HStack(spacing: 16) {
                                    // Thumbnail with Progress
                                    ZStack(alignment: .bottom) {
                                        AsyncImage(url: URL(string: video.snippet.thumbnails?.medium?.url ?? video.snippet.thumbnails?.defaultThumbnail?.url ?? "")) { image in
                                            image.resizable()
                                                .aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            ZStack {
                                                Color.gray.opacity(0.3)
                                                Image(systemName: "play.rectangle.fill")
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        .frame(width: 120, height: 68) // 16:9
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                                        )
                                        
                                        // Progress Bar
                                        if let status = videoStatus, status.progress > 0 && !status.isWatched {
                                            GeometryReader { geo in
                                                ZStack(alignment: .leading) {
                                                    Rectangle()
                                                        .foregroundColor(Color.black.opacity(0.5))
                                                    Rectangle()
                                                        .foregroundColor(.red)
                                                        .frame(width: geo.size.width * status.progress)
                                                }
                                            }
                                            .frame(height: 4)
                                            .cornerRadius(2)
                                            .padding(.horizontal, 4)
                                            .padding(.bottom, 4)
                                        }
                                        
                                        // Watched Overlay
                                        if let status = videoStatus, status.isWatched {
                                            ZStack {
                                                Color.black.opacity(0.6)
                                                Image(systemName: "checkmark")
                                                    .foregroundColor(.white)
                                                    .font(.caption)
                                            }
                                            .frame(width: 120, height: 68)
                                            .cornerRadius(8)
                                        }
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(alignment: .top) {
                                            let isPlayed = (videoStatus?.progress ?? 0) > 0 || (videoStatus?.isWatched ?? false)
                                            if isNew && !isPlayed {
                                                Circle()
                                                    .fill(Color.blue)
                                                    .frame(width: 8, height: 8)
                                                    .padding(.top, 4)
                                            }
                                            Text(video.snippet.title)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .lineLimit(2)
                                                .foregroundColor(videoStatus?.isWatched == true ? .secondary : .primary)
                                        }
                                        
                                        HStack(spacing: 4) {
                                            if isPublishedToday {
                                                Text("TODAY")
                                                    .font(.caption2)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(.blue)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 2)
                                                    .background(Color.blue.opacity(0.1))
                                                    .cornerRadius(4)
                                            }
                                            Text(DateUtils.formatISOString(video.snippet.publishedAt ?? ""))
                                                .font(.caption2)
                                                .foregroundColor(isPublishedToday ? .primary : .secondary)
                                            
                                            if CacheStatusService.shared.isCached(video.videoId) {
                                                Image(systemName: "checkmark.icloud.fill")
                                                    .font(.caption2)
                                                    .foregroundColor(.green)
                                                Text("Cached")
                                                    .font(.caption2)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(.green)
                                            }
                                        }
                                        .task {
                                            CacheStatusService.shared.checkStatus(for: video.videoId)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Menu {
                                        if videoStatus?.isWatched == true {
                                            Button(action: {
                                                videoStatusManager.markAsUnwatched(videoId: video.videoId)
                                            }) {
                                                Label("Mark as Unread", systemImage: "envelope.badge")
                                            }
                                        } else {
                                            Button(action: {
                                                videoStatusManager.markAsWatched(videoId: video.videoId)
                                            }) {
                                                Label("Mark as Watched", systemImage: "checkmark.circle")
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .rotationEffect(.degrees(90))
                                            .foregroundColor(.secondary)
                                            .padding(8) // Increased touch area
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(isPublishedToday ? Color.blue.opacity(0.05) : Color(UIColor.systemBackground))
                                .onAppear {
                                    if video.id == viewModel.videos.last?.id {
                                        Task {
                                            await viewModel.loadMore(channelId: subscription.snippet.resourceId.channelId ?? "")
                                        }
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Divider()
                                .padding(.leading, 152)
                        }
                        
                        if viewModel.isLoadingMore {
                            ProgressView()
                                .padding()
                        }
                    }
                    .padding(.vertical, 10)
                }
                .refreshable {
                     await viewModel.loadData(channelId: subscription.snippet.resourceId.channelId ?? "")
                }
            }
        }
        .navigationTitle(subscription.snippet.title)
        .navigationBarTitleDisplayMode(.large)
        .task {
            // Only load if not already loaded or if different channel?
            // For simplicity, load every time view appears or use state to track loaded channel
            if viewModel.videos.isEmpty {
                 await viewModel.loadData(channelId: subscription.snippet.resourceId.channelId ?? "")
            }
        }
    }
}

@MainActor
class ChannelDetailViewModel: ObservableObject {
    @Published var videos: [PlaylistItem] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    
    @Published var previousVisitDate: Date? // Capture when view loads
    
    private var nextPageToken: String?
    private var uploadsPlaylistId: String?
    
    func loadData(channelId: String) async {
        guard !channelId.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        nextPageToken = nil
        videos = [] // Reset
        
        // Capture previous visit BEFORE updating it
        // This ensures 'New' indicators work for this session
        self.previousVisitDate = VideoStatusManager.shared.getLastVisit(channelId: channelId)
        
        do {
            // 1. Get Channel Details to find "uploads" playlist ID
            let channel = try await YouTubeService.shared.fetchChannelDetails(channelId: channelId)
            self.uploadsPlaylistId = channel.contentDetails.relatedPlaylists.uploads
            
            // 2. Fetch Items from that playlist
            if let playlistId = uploadsPlaylistId {
                let result = try await YouTubeService.shared.fetchPlaylistItems(playlistId: playlistId, maxResults: 10)
                self.videos = result.items
                self.nextPageToken = result.nextPageToken
                
                // Update last visit AFTER fetching - REMOVED to persist unread status
                // VideoStatusManager.shared.updateLastVisit(channelId: channelId)
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    func loadMore(channelId: String) async {
        guard !isLoadingMore, let token = nextPageToken, let playlistId = uploadsPlaylistId else { return }
        
        isLoadingMore = true
        do {
            let result = try await YouTubeService.shared.fetchPlaylistItems(playlistId: playlistId, pageToken: token, maxResults: 10)
            self.videos.append(contentsOf: result.items)
            self.nextPageToken = result.nextPageToken
        } catch {
            print("Error loading more videos: \(error.localizedDescription)")
        }
        isLoadingMore = false
    }
}
