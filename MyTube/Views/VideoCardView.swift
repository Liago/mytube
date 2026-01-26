import SwiftUI

struct VideoCardView: View {
    let title: String
    let channelName: String
    let date: Date?
    let thumbnailURL: URL?
    let action: () -> Void
    
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
                            Text(date.formatted(date: .numeric, time: .shortened))
                            Text("•")
                        }
                        Text(channelName)
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    
                    // Description/Extra info placeholder (mimicking the "Lost city..." text)
                    // Since we don't have a specific description field in the list item effectively,
                    // we can skip or show a generic "Watch now" call to action styled nicely.
                    
                    HStack {
                        Text("Watch now")
                            .font(.headline)
                            .fontWeight(.bold)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 24)
                            .background(Color.primary)
                            .foregroundColor(Color(UIColor.systemBackground))
                            .cornerRadius(30)
                        
                        Spacer()
                        
                        Image(systemName: "arrow.up.right")
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
                title: "Petra, Jordan - A Journey Through History",
                channelName: "Travel & History",
                date: Date(),
                thumbnailURL: URL(string: "https://example.com/image.jpg"),
                action: {}
            )
            .padding()
        }
    }
}
