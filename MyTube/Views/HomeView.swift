import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @State private var selectedChannel: (id: String, title: String)?
    
    @ObservedObject var notifManager = NotificationManager.shared
    @State private var showingNotifications = false
    
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
                    videosList
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingNotifications = true
                    }) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell.fill")
                                .font(.body)
                                .foregroundColor(.primary)
                            
                            if notifManager.unreadCount > 0 {
                                Text("\(notifManager.unreadCount)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.red)
                                    .clipShape(Capsule())
                                    .offset(x: 8, y: -6)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingNotifications) {
                NotificationsView()
            }
        }
        .task {
            await viewModel.loadHomeVideos()
            await notifManager.fetchNotifications()
        }
    }
    
    @ViewBuilder
    private var videosList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.videos) { item in
                    videoCard(for: item)
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
        .refreshable {
            await viewModel.loadHomeVideos()
        }
    }
    }
    
    @ViewBuilder
    private func videoCard(for item: Video) -> some View {
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
