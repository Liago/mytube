import Foundation

struct AppNotification: Identifiable, Codable {
    let id: String // videoId
    let title: String
    let channelInfo: String
    let timestamp: String
    
    var date: Date? {
        // Parse ISO8601 string
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp)
    }
    
    var formattedDate: String {
        guard let d = date else { return timestamp }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: d)
    }
}
