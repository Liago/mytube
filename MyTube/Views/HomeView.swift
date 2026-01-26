import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    
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
                                Button(action: {
                                    AudioPlayerService.shared.playVideo(
                                        videoId: item.videoId,
                                        title: item.snippet.title,
                                        author: item.snippet.channelTitle ?? "",
                                        thumbnailURL: URL(string: item.snippet.thumbnails?.high?.url ?? ""),
                                        publishedAt: item.snippet.publishedAt
                                    )
                                }) {
                                    HStack(spacing: 16) {
                                        AsyncImage(url: URL(string: item.snippet.thumbnails?.medium?.url ?? item.snippet.thumbnails?.defaultThumbnail?.url ?? "")) { image in
                                            image.resizable()
                                                .aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            ZStack {
                                                Color.gray.opacity(0.3)
                                                Image(systemName: "play.rectangle.fill")
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                        .frame(width: 120, height: 68)
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                                        )
                                        
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(item.snippet.title)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .lineLimit(2)
                                                .foregroundColor(.primary)
                                            
                                            HStack(spacing: 4) {
                                                Text(item.snippet.channelTitle ?? "")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                
                                                if let date = item.snippet.publishedAt {
                                                    Text("• \(DateUtils.formatISOString(date))")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(UIColor.systemBackground))
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Divider()
                                    .padding(.leading, 152)
                            }
                        }
                        .padding(.vertical, 10)
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
