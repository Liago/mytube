import SwiftUI
import MediaPlayer

struct PlayerSheetView: View {
    @ObservedObject var playerService = AudioPlayerService.shared
    @Environment(\.presentationMode) var presentationMode
    
    // For drag gesture to dismiss
    @State private var dragOffset = CGSize.zero
    
    // Formatting for date
    private var dateString: String {
        guard let isoDate = playerService.currentVideoDate,
              let date = DateUtils.parseISOString(isoDate) else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d" // e.g., January 21
        return formatter.string(from: date)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Drag Indicator / Top Bar
            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 40)) // Large tap area visual
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 16)
                    .padding(.bottom, 20)
            }
            
            Spacer()
            
            // Artwork
            if let url = playerService.coverArtURL {
                AsyncImage(url: url) { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray
                }
                .frame(width: 320, height: 320) // Adjust based on screen?
                .cornerRadius(16)
                .shadow(radius: 10, y: 10)
            } else {
                Rectangle()
                    .fill(Color.gray)
                    .frame(width: 320, height: 320)
                    .cornerRadius(16)
            }
            
            Spacer()
            
            // Info Area
            VStack(alignment: .leading, spacing: 8) {
                // Date
                if !dateString.isEmpty {
                    Text(dateString)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .textCase(.uppercase)
                }
                
                // Title
                Text(playerService.currentTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                // Author/Subtitle
                Text(playerService.currentAuthor)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
            
            // Progress Bar
            VStack(spacing: 8) {
                Slider(value: Binding(get: {
                    playerService.currentTime
                }, set: { newValue in
                    playerService.seek(to: newValue)
                }), in: 0...max(1.0, playerService.duration))
                .accentColor(.yellow) // Matching screenshot
                
                HStack {
                     Text(formatTime(playerService.currentTime))
                     Spacer()
                     Text(formatTime(playerService.duration - playerService.currentTime))
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
            
            // Controls Row
            HStack(spacing: 40) {
                // Speed
                Menu {
                    Picker("Playback Speed", selection: Binding(
                        get: { playerService.playbackRate },
                        set: { playerService.setPlaybackRate($0) }
                    )) {
                        Text("1x").tag(Float(1.0))
                        Text("1.25x").tag(Float(1.25))
                        Text("1.5x").tag(Float(1.5))
                        Text("1.75x").tag(Float(1.75))
                        Text("2x").tag(Float(2.0))
                    }
                } label: {
                    Text("\(playerService.playbackRate.formatted())x")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                
                // Rewind 15
                Button(action: {
                    playerService.seek(to: playerService.currentTime - 15)
                }) {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
                
                // Play/Pause
                Button(action: {
                    playerService.togglePlayPause()
                }) {
                    if playerService.isLoadingStream {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                            .frame(width: 48, height: 48)
                    } else {
                        Image(systemName: playerService.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.white)
                    }
                }
                .disabled(playerService.isLoadingStream)
                
                // Forward 30
                Button(action: {
                    playerService.seek(to: playerService.currentTime + 30)
                }) {
                    Image(systemName: "goforward.30")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
                
                // Sleep Timer (Placeholder)
                Button(action: {
                    // Sleep timer action
                }) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(.bottom, 48)
            
            // Bottom Actions (Placeholder)
            HStack(spacing: 60) {
                Button(action: {}) {
                    Image(systemName: "quote.bubble")
                        .foregroundColor(.white.opacity(0.6))
                }
                Button(action: {}) {
                    Image(systemName: "airplayaudio")
                        .foregroundColor(.white.opacity(0.6))
                }
                Button(action: {}) {
                    Image(systemName: "list.bullet")
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .font(.system(size: 22))
            .padding(.bottom, 32)
        }
        .padding(.top, 40) // Add some top padding for status bar if not ignoring safe area
        .padding(.bottom, 20)
        .background(
            ZStack {
                if let url = playerService.coverArtURL {
                    AsyncImage(url: url) { image in
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .ignoresSafeArea()
                            .blur(radius: 60)
                            .overlay(Color.black.opacity(0.4))
                    } placeholder: {
                        Color.black.ignoresSafeArea()
                    }
                } else {
                    Color.black.ignoresSafeArea()
                }
            }
        )
        .offset(y: dragOffset.height)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    if gesture.translation.height > 0 {
                        self.dragOffset = gesture.translation
                    }
                }
                .onEnded { _ in
                    if self.dragOffset.height > 150 {
                        presentationMode.wrappedValue.dismiss()
                    } else {
                        self.dragOffset = .zero
                    }
                }
        )
        .animation(.spring(), value: dragOffset)
    }
    
    // Speed Toggle Logic

    
    func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
