import Foundation

// MARK: - Piped API Response Models

struct PipedStreamResponse: Codable {
    let title: String?
    let uploader: String?
    let duration: Int?
    let thumbnailUrl: String?
    let audioStreams: [PipedAudioStream]?
}

struct PipedAudioStream: Codable {
    let url: String
    let format: String?
    let quality: String?
    let mimeType: String?
    let codec: String?
    let bitrate: Int?
    let contentLength: Int?
}

// MARK: - Stream Extraction Service

class YouTubeStreamService {
    static let shared = YouTubeStreamService()

    private let pipedInstances = [
        "https://pipedapi.kavin.rocks",
        "https://pipedapi.adminforge.de",
        "https://pipedapi.in.projectsegfau.lt"
    ]

    private init() {}

    /// Extracts a native audio stream URL from a YouTube video ID using Piped API.
    /// Tries multiple Piped instances with fallback.
    func getAudioStreamURL(videoId: String) async throws -> URL {
        var lastError: Error?

        for instance in pipedInstances {
            do {
                let url = try await fetchAudioStream(from: instance, videoId: videoId)
                print("Stream resolved via \(instance)")
                return url
            } catch {
                lastError = error
                print("[\(instance)] failed: \(error.localizedDescription)")
            }
        }

        throw lastError ?? URLError(.cannotFindHost)
    }

    private func fetchAudioStream(from instance: String, videoId: String) async throws -> URL {
        guard let apiURL = URL(string: "\(instance)/streams/\(videoId)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let streamResponse = try JSONDecoder().decode(PipedStreamResponse.self, from: data)

        guard let audioStreams = streamResponse.audioStreams, !audioStreams.isEmpty else {
            throw URLError(.resourceUnavailable)
        }

        // Prefer M4A/AAC streams (natively supported by AVPlayer on iOS)
        let compatibleStreams = audioStreams.filter { stream in
            let mime = (stream.mimeType ?? "").lowercased()
            return mime.contains("audio/mp4") || mime.contains("audio/m4a")
        }

        // Sort by bitrate descending (best quality first)
        let sorted = (compatibleStreams.isEmpty ? audioStreams : compatibleStreams)
            .sorted { ($0.bitrate ?? 0) > ($1.bitrate ?? 0) }

        guard let best = sorted.first, let streamURL = URL(string: best.url) else {
            throw URLError(.cannotParseResponse)
        }

        print("Selected: \(best.format ?? "?") \(best.quality ?? "?") \(best.mimeType ?? "?")")
        return streamURL
    }
}
