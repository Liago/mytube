import SwiftUI
import MediaPlayer

struct PlayerSheetView: View {
    @ObservedObject var playerService = AudioPlayerService.shared
    @ObservedObject var downloadManager = AudioDownloadManager.shared
    @Environment(\.presentationMode) var presentationMode
    
    // For drag gesture to dismiss
    @State private var dragOffset = CGSize.zero
    
    // For progress bar dragging
    @State private var isDraggingSlider: Bool = false
    @State private var draggedProgress: Double = 0.0
    
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
        ZStack {
            // Layer 1: Background Content
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
            
            // Layer 2: Download Progress Overlay
            if downloadManager.isDownloading {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    
                    Text("Downloading...")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    ProgressView(value: downloadManager.downloadProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .yellow))
                        .frame(width: 200)
                    
                    Text("\(Int(downloadManager.downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(32)
                .background(Color.black.opacity(0.7))
                .cornerRadius(16)
            }
            
            // Layer 3: Main UI Content
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
                            .aspectRatio(contentMode: .fit) // Fit aspect ratio
                            .cornerRadius(12)
                            .shadow(radius: 20)
                    } placeholder: {
                        Color.gray
                            .aspectRatio(1, contentMode: .fit)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 24) // Slight padding from edges
                        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                        .frame(maxHeight: UIScreen.main.bounds.height * 0.45) // Limit height for vertical videos
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
                    .fixedSize(horizontal: false, vertical: true) // Force Wrap
                
                // Author/Subtitle
                Text(playerService.currentAuthor)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .frame(maxWidth: UIScreen.main.bounds.width - 64, alignment: .leading) // Explicit width constraint
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            
            // Progress Bar Area
            // Progress Bar Area - RADICAL HEADER
            VStack(spacing: 20) {
                
                // 1. Time Labels - CENTERED and LARGE (User Request)
                HStack(spacing: 20) {
                    Text(formatTime(isDraggingSlider ? draggedProgress * playerService.duration : playerService.currentTime))
                        .fontWeight(.semibold)
                    Text("/")
                        .opacity(0.5)
                    Text(formatTime(playerService.duration.isFinite ? playerService.duration : 0))
                        .fontWeight(.semibold)
                }
                .font(.body) // Larger font
                .foregroundColor(.white)
                .frame(maxWidth: .infinity) // Center in container
                
                // 2. The Slider - EXPLICIT WIDTH (No GeometryReader bugs)
                // We know the padding is 32 on each side, so width is Screen - 64
                let barWidth = UIScreen.main.bounds.width - 64
                let duration = (playerService.duration.isFinite && playerService.duration > 0) ? playerService.duration : 1.0
                let current = playerService.currentTime.isFinite ? playerService.currentTime : 0.0
                // Calculate progress properly
                let rawProgress = current / duration
                let activeProgress = isDraggingSlider ? draggedProgress : rawProgress
                let safeProgress = max(0, min(1, activeProgress))
                
                ZStack(alignment: .leading) {
                    // Touch Area (Transparent)
                    Rectangle()
                        .fill(Color.white.opacity(0.001))
                        .frame(width: barWidth, height: 40)
                    
                    // Track (Gray)
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: barWidth, height: 6)
                        .cornerRadius(3)
                    
                    // Fill (White)
                    
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: max(0, barWidth * CGFloat(safeProgress)), height: 6)
                        .cornerRadius(3)
                    
                    // Knob (Big & Visible)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 20, height: 20)
                        .shadow(radius: 4)
                        .offset(x: (barWidth * CGFloat(safeProgress)) - 10) // Center knob (20/2 = 10)
                }
                .frame(width: barWidth, height: 40)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDraggingSlider = true
                            let newProgress = min(max(0, value.location.x / barWidth), 1.0)
                            draggedProgress = newProgress
                        }
                        .onEnded { value in
                            let newProgress = min(max(0, value.location.x / barWidth), 1.0)
                            playerService.seek(to: newProgress * duration)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                isDraggingSlider = false
                            }
                        }
                )
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            .layoutPriority(100) // Highest priority

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
            
            // Layer 2: Loading Overlay
            if playerService.isLoadingStream {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    
                    Text("Processing...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .padding(32)
                .background(Color.black.opacity(0.7))
                .cornerRadius(16)
            }
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
        } // End of UI VStack
    } // End of body ZStack
    .padding(.top, 40)
    .padding(.bottom, 20)
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

    func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
