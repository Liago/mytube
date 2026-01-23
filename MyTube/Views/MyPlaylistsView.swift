import SwiftUI

struct MyPlaylistsView: View {
    @StateObject var viewModel = HomeViewModel()
    @ObservedObject var authManager = AuthManager.shared
    
    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
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
                        Text("Unable to load playlists")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Retry") {
                            Task { await viewModel.loadData() }
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(viewModel.playlists) { playlist in
                                NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        // Aspect Ratio 16:9 or 1:1? Usually playlists are 16:9 thumbnails
                                        AsyncImage(url: URL(string: playlist.snippet.thumbnails?.high?.url ?? playlist.snippet.thumbnails?.defaultThumbnail?.url ?? "")) { image in
                                            image.resizable()
                                                .aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            ZStack {
                                                Color.gray.opacity(0.3)
                                                Image(systemName: "music.note.list")
                                                    .font(.largeTitle)
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                        .frame(height: 120) // Fixed height for consistency
                                        .clipped()
                                        
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(playlist.snippet.title)
                                                .font(.headline)
                                                .lineLimit(2)
                                                .foregroundColor(.primary)
                                            
                                            Text(playlist.snippet.channelTitle ?? "Unknown")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                        .padding(12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color(UIColor.secondarySystemGroupedBackground))
                                    }
                                    .cornerRadius(12)
                                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(16)
                    }
                    .refreshable {
                        await viewModel.loadData()
                    }
                }
            }
            .navigationTitle("My Playlists")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        authManager.signOut()
                    }) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .task {
            // Avoid unnecessary reloads
            if viewModel.playlists.isEmpty {
                await viewModel.loadData()
            }
        }
    }
}
