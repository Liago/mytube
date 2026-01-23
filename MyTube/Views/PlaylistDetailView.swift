import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist
    @State private var items: [PlaylistItem] = []
    
    var body: some View {
        Group {
            if items.isEmpty { // Assuming loading if empty initially for this simple view
                 ProgressView()
                     .scaleEffect(1.5)
                     .onAppear {
                         // Fallback trigger if task doesn't catch it or for refresh logic
                     }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
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
                                            Image(systemName: "music.note")
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
                                            
                                            // Playlist items might store original publish date in contentDetails or snippet.publishedAt (when added to playlist)
                                            // Usually snippet.publishedAt is when it was ADDED to playlist. 
                                            // contentDetails.videoPublishedAt is usually what we want if available.
                                            // The PlaylistItem model needs checking. Assuming snippet.publishedAt for now or similar.
                                            if let date = item.snippet.publishedAt {
                                                 Text("• \(DateUtils.formatISOString(date))")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "ellipsis")
                                        .rotationEffect(.degrees(90))
                                        .foregroundColor(.secondary)
                                        .padding(.trailing, 4)
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
            }
        }
        .navigationTitle(playlist.snippet.title)
        .navigationBarTitleDisplayMode(.large)
        .task {
            do {
                if items.isEmpty {
                     items = try await YouTubeService.shared.fetchPlaylistItems(playlistId: playlist.id).items
                }
            } catch {
                print("Error loading items: \(error)")
            }
        }
    }
}
