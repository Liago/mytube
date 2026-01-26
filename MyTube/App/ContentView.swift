import SwiftUI

struct ContentView: View {
    @ObservedObject var authManager = AuthManager.shared
    @ObservedObject var playerService = AudioPlayerService.shared
    @State private var isPlayerExpanded = false // State for full player
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // 1. YouTube Player (Background Layer)
            // CRITICAL: Must be fully "visible" to the view hierarchy (no opacity < 0.1, no hidden)
            // to prevent OS suspension. We rely on the HomeView appearing *over* it.
            if let videoId = playerService.currentVideoId {
                YouTubePlayerView(videoId: videoId)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false) // Pass touches to views above
                    .ignoresSafeArea() 
            }
            
            // 2. Main Application Content (Occludes the player)
            if authManager.isAuthenticated {
                MainTabView()
                    .background(Color(UIColor.systemBackground)) // Solid background is MANDATORY to hide player
                    .padding(.bottom, playerService.currentTitle.isEmpty ? 0 : 60) // Space for mini player
            } else {
                LoginView()
                    .background(Color(UIColor.systemBackground))
            }
            
            // 3. Mini Player Overlay
            if !playerService.currentTitle.isEmpty {
                MiniPlayerView(isExpanded: $playerService.isPlayerPresented)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.spring(), value: playerService.currentTitle.isEmpty)
        .fullScreenCover(isPresented: $playerService.isPlayerPresented) {
            PlayerSheetView()
        }
    }
}

struct MiniPlayerView: View {
    @ObservedObject var playerService = AudioPlayerService.shared
    @Binding var isExpanded: Bool // Binding to control expansion
    
    // Helper for formatting time
    func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main Content Area (Tappable for expansion)
            HStack {
                if let url = playerService.coverArtURL {
                    AsyncImage(url: url) { image in
                        image.resizable()
                    } placeholder: {
                        Color.gray
                    }
                    .frame(width: 50, height: 50)
                    .cornerRadius(5)
                } else {
                    Rectangle().fill(Color.gray).frame(width: 50, height: 50)
                }
                
                VStack(alignment: .leading) {
                    Text(playerService.currentTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Text(playerService.currentAuthor)
                        .font(.caption)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Play/Pause Button
                Button(action: {
                    playerService.togglePlayPause()
                }) {
                    Image(systemName: playerService.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .padding(12)
                }
                
                // Expand Button (Chevron) - VISUAL CUE
                Button(action: {
                    isExpanded = true
                }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.gray)
                        .padding(12)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle()) // Make entire area tappable
            .onTapGesture {
                isExpanded = true
            }
            .gesture(DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.height < 0 {
                        // Swipe Up
                        isExpanded = true
                    }
                }
            )
            
            // Progress Bar (Bottom Line)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                    
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: geometry.size.width * CGFloat(playerService.duration > 0 ? playerService.currentTime / playerService.duration : 0))
                }
            }
            .frame(height: 2)
        }
        .background(Color(UIColor.secondarySystemBackground))
        .shadow(radius: 2)
    }
}
