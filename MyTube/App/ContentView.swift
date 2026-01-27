import SwiftUI

struct ContentView: View {
    @ObservedObject var authManager = AuthManager.shared
    @ObservedObject var playerService = AudioPlayerService.shared
    @State private var isPlayerExpanded = false // State for full player
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Main Application Content
            if authManager.isAuthenticated {
                MainTabView()
                    .padding(.bottom, playerService.currentTitle.isEmpty ? 0 : 60)
            } else {
                LoginView()
            }
            
            // Mini Player Overlay
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
                    if playerService.isLoadingStream {
                        ProgressView()
                            .padding(12)
                    } else {
                        Image(systemName: playerService.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundColor(.primary)
                            .padding(12)
                    }
                }
                .disabled(playerService.isLoadingStream)
                
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
