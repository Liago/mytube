import Foundation

struct YouTubeResponse<T: Codable>: Codable {
    let items: [T]
    let nextPageToken: String?
}

struct Snippet: Codable {
    let title: String
    let description: String
    let thumbnails: Thumbnails?
    let resourceId: ResourceId?
    let channelTitle: String?
    let publishedAt: String?
}

struct ResourceId: Codable {
    let videoId: String?
    let channelId: String?
}

struct Subscription: Codable, Identifiable {
    let id: String
    let snippet: SubscriptionSnippet
    let contentDetails: SubscriptionContentDetails?
}

struct SubscriptionContentDetails: Codable {
    let totalItemCount: Int?
    let newItemCount: Int?
}
struct SubscriptionSnippet: Codable {
    let title: String
    let description: String
    let resourceId: ResourceId
    let thumbnails: Thumbnails
}

struct Thumbnails: Codable {
    let defaultThumbnail: Thumbnail?
    let medium: Thumbnail?
    let high: Thumbnail?
    
    enum CodingKeys: String, CodingKey {
        case defaultThumbnail = "default"
        case medium
        case high
    }
}

struct Thumbnail: Codable {
    let url: String
    let width: Int?
    let height: Int?
}

struct Playlist: Codable, Identifiable {
    let id: String
    let snippet: Snippet
}

struct PlaylistItem: Codable, Identifiable {
    let id: String // This is the ID of the item in the playlist, not the video ID itself necessarily
    let snippet: Snippet
    
    var videoId: String {
        return snippet.resourceId?.videoId ?? ""
    }
}

struct VideoConfig: Codable, Identifiable {
    let id: String
    let snippet: Snippet
}

struct Channel: Codable, Identifiable {
    let id: String
    let contentDetails: ChannelContentDetails
}

struct ChannelContentDetails: Codable {
    let relatedPlaylists: RelatedPlaylists
}

struct RelatedPlaylists: Codable {
    let uploads: String
}
