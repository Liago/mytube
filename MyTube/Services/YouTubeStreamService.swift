import Foundation
import YouTubeKit

class YouTubeStreamService {
    static let shared = YouTubeStreamService()
    
    private init() {}
    
    /// Extracts a native audio stream URL from a YouTube video ID using YouTubeKit.
    func getAudioStreamURL(videoId: String) async throws -> URL {
        // Create a YouTube object with the video ID
        let video = YouTube(videoID: videoId)
        
        // Fetch streams
        let streams = try await video.streams
        
        // Filter for audio-only streams
        let audioStreams = streams.filterAudioOnly()
        
        // Sort by bitrate (HIGHEST first for best quality) and prefer mp4/m4a containers for better compatibility
        // We revert to high quality to check if low quality streams are causing 403 errors
        let sortedStreams = audioStreams.sorted { stream1, stream2 in
            // Priority 1: Container preference (mp4/m4a > webm)
            let isM4A1 = stream1.fileExtension == .m4a || stream1.fileExtension == .mp4
            let isM4A2 = stream2.fileExtension == .m4a || stream2.fileExtension == .mp4
            
            if isM4A1 != isM4A2 {
                return isM4A1
            }
            
            // Priority 2: Prefer HIGHEST bitrate for best quality
            return (stream1.bitrate ?? 0) > (stream2.bitrate ?? 0)
        }
        
        // Debug: Log all available audio streams
        print("Available audio streams for video \(videoId):")
        for stream in audioStreams {
             print("- itag: \(stream.itag), mime: \(stream.mimeType ?? "nil"), bitrate: \(stream.bitrate ?? 0), url: \(stream.url.absoluteString.prefix(50))...")
        }

        guard let bestStream = sortedStreams.first else {
            throw URLError(.resourceUnavailable, userInfo: [NSLocalizedDescriptionKey: "No suitable audio stream found"])
        }
        
        let url = bestStream.url
        print("YouTubeKit: Selected stream itag: \(bestStream.itag), mime: \(bestStream.mimeType ?? "unknown")")
        print("YouTubeKit: Full URL: \(url.absoluteString)") // Log full URL for debugging
        return url
    }
}
