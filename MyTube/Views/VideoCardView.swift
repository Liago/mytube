import SwiftUI

struct VideoCardView: View {
    let videoId: String
    let title: String
    let channelName: String
    let channelId: String // Added
    let date: Date?
    let duration: String?
    let thumbnailURL: URL?
    let action: () -> Void
    let onChannelTap: (String) -> Void // Added
    
    @ObservedObject private var cacheService = CacheStatusService.shared
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                // Large Thumbnail
                AsyncImage(url: thumbnailURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        Color.gray.opacity(0.3)
                        Image(systemName: "play.rectangle.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 50)
                            .foregroundColor(.gray)
                    }
                }
                .frame(height: 220)
                .clipped()
                
                // Content
                VStack(alignment: .leading, spacing: 12) {
                    // Title and Rating/More Icon
                    HStack(alignment: .top) {
                        Text(title)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        Spacer()
                        
                        // Placeholder for "Top rated" or similar badge/menu from design
                        // For now using a generic menu icon or similar visual
                        Image(systemName: "ellipsis")
                            .foregroundColor(.primary)
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(Circle())
                    }
                    
                    // Metadata line
                    HStack {
                        if let date = date {
                            Text("Pubblicato il \(date.formatted(date: .numeric, time: .omitted))")
                        }
                        if let duration = duration {
                            Text("•")
                            Text(duration)
                        }
                        
                        if cacheService.isCached(videoId) {
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.icloud.fill")
                                Text("Cached")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .task {
                        cacheService.checkStatus(for: videoId)
                    }
                    
                    // Description/Extra info placeholder (mimicking the "Lost city..." text)
                    // Since we don't have a specific description field in the list item effectively,
                    // we can skip or show a generic "Watch now" call to action styled nicely.
                    
                    HStack {
                        // Channel Label Button - navigates to channel
                        Button(action: {
                            onChannelTap(channelId)
                        }) {
                            Text(channelName)
                                .font(.headline)
                                .fontWeight(.bold)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 24)
                                .background(Color.primary)
                                .foregroundColor(Color(UIColor.systemBackground))
                                .cornerRadius(30)
                        }
                        .buttonStyle(PlainButtonStyle()) // Important to nest inside another button
                        
                        Spacer()
                        
                        Image(systemName: "headphones")
                            .font(.system(size: 20, weight: .bold))
                            .padding(12)
                            .background(Color.primary)
                            .foregroundColor(Color(UIColor.systemBackground))
                            .clipShape(Circle())
                    }
                    .padding(.top, 8)
                }
                .padding(20)
                .background(Color(UIColor.systemBackground))
            }
            .cornerRadius(24) // Large corner radius as per design
            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Preview helper
struct VideoCardView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.all)
            
            VideoCardView(
                videoId: "test_id",
                title: "Petra, Jordan - A Journey Through History",
                channelName: "Travel & History",
                channelId: "UC_test",
                date: Date(),
                duration: "10:05",
                thumbnailURL: URL(string: "https://example.com/image.jpg"),
                action: {},
                onChannelTap: { _ in }
            )
            .padding()
        }
    }
}
