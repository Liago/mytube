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

// MARK: - Invidious API Response Models

struct InvidiousVideoResponse: Codable {
    let title: String?
    let author: String?
    let adaptiveFormats: [InvidiousFormat]?
}

struct InvidiousFormat: Codable {
    let url: String?
    let type: String?
    let bitrate: String?
    let container: String?
    let encoding: String?
    let audioQuality: String?
}

// MARK: - Stream Extraction Service

class YouTubeStreamService {
    static let shared = YouTubeStreamService()

    private let pipedInstances = [
        "https://pipedapi.kavin.rocks",
        "https://pipedapi-libre.kavin.rocks",
        "https://pipedapi.leptons.xyz",
        "https://api.piped.yt",
        "https://pipedapi.darkness.services",
        "https://pipedapi.drgns.space",
        "https://piped-api.privacy.com.de",
        "https://pipedapi.ducks.party"
    ]

    private let invidiousInstances = [
        "https://invidious.io",
        "https://vid.puffyan.us",
        "https://inv.nadeko.net",
        "https://invidious.nerdvpn.de"
    ]

    private init() {}

    /// Extracts a native audio stream URL from a YouTube video ID.
    /// Tries Piped instances first, then falls back to Invidious.
    func getAudioStreamURL(videoId: String) async throws -> URL {
        var lastError: Error?

        // Phase 1: Try Piped instances
        for instance in pipedInstances {
            do {
                let url = try await fetchFromPiped(instance: instance, videoId: videoId)
                print("Stream resolved via Piped: \(instance)")
                return url
            } catch {
                lastError = error
                print("[Piped \(instance)] \(error.localizedDescription)")
            }
        }

        // Phase 2: Try Invidious instances as fallback
        for instance in invidiousInstances {
            do {
                let url = try await fetchFromInvidious(instance: instance, videoId: videoId)
                print("Stream resolved via Invidious: \(instance)")
                return url
            } catch {
                lastError = error
                print("[Invidious \(instance)] \(error.localizedDescription)")
            }
        }

        throw lastError ?? URLError(.cannotFindHost)
    }

    // MARK: - Piped

    private func fetchFromPiped(instance: String, videoId: String) async throws -> URL {
        guard let apiURL = URL(string: "\(instance)/streams/\(videoId)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 8

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw URLError(.badServerResponse, userInfo: [
                NSLocalizedDescriptionKey: "HTTP \(code)"
            ])
        }

        let streamResponse: PipedStreamResponse
        do {
            streamResponse = try JSONDecoder().decode(PipedStreamResponse.self, from: data)
        } catch {
            // Log first bytes for diagnostics
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "(binary)"
            print("[Piped \(instance)] Invalid JSON response: \(preview)")
            throw error
        }

        guard let audioStreams = streamResponse.audioStreams, !audioStreams.isEmpty else {
            throw URLError(.resourceUnavailable)
        }

        return try selectBestAudioStream(from: audioStreams)
    }

    private func selectBestAudioStream(from streams: [PipedAudioStream]) throws -> URL {
        // Prefer M4A/AAC (natively supported by AVPlayer on iOS)
        let compatible = streams.filter { stream in
            let mime = (stream.mimeType ?? "").lowercased()
            return mime.contains("audio/mp4") || mime.contains("audio/m4a")
        }

        let sorted = (compatible.isEmpty ? streams : compatible)
            .sorted { ($0.bitrate ?? 0) > ($1.bitrate ?? 0) }

        guard let best = sorted.first, let url = URL(string: best.url) else {
            throw URLError(.cannotParseResponse)
        }

        print("Selected: \(best.format ?? "?") \(best.quality ?? "?") \(best.mimeType ?? "?")")
        return url
    }

    // MARK: - Invidious

    private func fetchFromInvidious(instance: String, videoId: String) async throws -> URL {
        guard let apiURL = URL(string: "\(instance)/api/v1/videos/\(videoId)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 8

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw URLError(.badServerResponse, userInfo: [
                NSLocalizedDescriptionKey: "HTTP \(code)"
            ])
        }

        let videoResponse: InvidiousVideoResponse
        do {
            videoResponse = try JSONDecoder().decode(InvidiousVideoResponse.self, from: data)
        } catch {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "(binary)"
            print("[Invidious \(instance)] Invalid JSON response: \(preview)")
            throw error
        }

        guard let formats = videoResponse.adaptiveFormats, !formats.isEmpty else {
            throw URLError(.resourceUnavailable)
        }

        // Filter audio-only M4A/AAC formats
        let audioFormats = formats.filter { fmt in
            let type = (fmt.type ?? "").lowercased()
            return type.contains("audio/mp4") || type.contains("audio/m4a")
        }

        // Fallback: any audio format
        let anyAudio = audioFormats.isEmpty ? formats.filter { ($0.type ?? "").lowercased().contains("audio") } : audioFormats

        guard let best = anyAudio.first, let urlStr = best.url, let url = URL(string: urlStr) else {
            throw URLError(.cannotParseResponse)
        }

        print("Selected (Invidious): \(best.container ?? "?") \(best.audioQuality ?? "?") \(best.type ?? "?")")
        return url
    }
}
