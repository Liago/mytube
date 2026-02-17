import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @State private var selectedChannel: (id: String, title: String)?
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.all)
                
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                } else if let error = viewModel.errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("Unable to load feed")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Retry") {
                            Task { await viewModel.loadHomeVideos() }
                        }
                        .buttonStyle(.bordered)
                    }
                } else if viewModel.videos.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "film.stack")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No videos found")
                            .font(.title2)
                        Text("Select channels in Subscriptions tab to see their videos here. Only videos published today will appear.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Refresh") {
                            Task { await viewModel.loadHomeVideos() }
                        }
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.videos) { item in
                                VideoCardView(
                                    videoId: item.id,
                                    title: item.snippet.title,
                                    channelName: item.snippet.channelTitle ?? "",
                                    channelId: item.snippet.channelId ?? "",
                                    date: item.snippet.publishedAt.flatMap { DateUtils.parseISOString($0) } ?? (item.snippet.publishedAt != nil ? Date() : nil),
                                    duration: DateUtils.formatDuration(item.contentDetails.duration),
                                    thumbnailURL: URL(string: item.snippet.thumbnails?.high?.url ?? item.snippet.thumbnails?.medium?.url ?? ""),
                                    action: {
                                        AudioPlayerService.shared.playVideo(
                                            videoId: item.id,
                                            title: item.snippet.title,
                                            author: item.snippet.channelTitle ?? "",
                                            thumbnailURL: URL(string: item.snippet.thumbnails?.high?.url ?? ""),
                                            publishedAt: item.snippet.publishedAt
                                        )
                                    },
                                    onChannelTap: { channelId in
                                        if let channelName = item.snippet.channelTitle {
                                            selectedChannel = (channelId, channelName)
                                        }
                                    }
                                )
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                        }
                        .padding(.vertical, 16)
                        
                        // Hidden Navigation Link
                        NavigationLink(
                            isActive: Binding(
                                get: { selectedChannel != nil },
                                set: { if !$0 { selectedChannel = nil } }
                            ),
                            destination: {
                                if let channel = selectedChannel {
                                    ChannelDetailView(channelId: channel.id, channelTitle: channel.title)
                                } else {
                                    EmptyView()
                                }
                            }
                        ) {
                            EmptyView()
                        }
                        }
                        .padding(.vertical, 16)
                    }
                    .refreshable {
                        await viewModel.loadHomeVideos()
                    }
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            await viewModel.loadHomeVideos()
        }
    }
}
