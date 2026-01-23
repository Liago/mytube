import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case noToken
    case networkError(Error)
    case decodingError(Error)
    case invalidResponse(statusCode: Int, message: String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .noToken: return "No authentication token available"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .decodingError(let error): return "Failed to decode response: \(error.localizedDescription)"
        case .invalidResponse(let statusCode, let message): return "Error \(statusCode): \(message)"
        }
    }
}

struct APIErrorResponse: Codable {
    let error: APIErrorDetail
}

struct APIErrorDetail: Codable {
    let code: Int
    let message: String
}

class YouTubeService {
    static let shared = YouTubeService()
    private let baseURL = "https://www.googleapis.com/youtube/v3"
    
    private init() {}
    
    private func getHeaders() async throws -> [String: String] {
        let token = await AuthManager.shared.accessToken
        guard let token = token, !token.isEmpty else {
             throw APIError.noToken
        }
        return ["Authorization": "Bearer \(token)", "Accept": "application/json"]
    }
    
    // Helper to perform request
    private func performRequest<T: Codable>(endpoint: String, queryItems: [URLQueryItem], retryCount: Int = 0) async throws -> T {
        // We need to access token properly. For now, let's assume AuthManager is accessible
        let token = await AuthManager.shared.accessToken
        guard let token = token else { throw APIError.noToken }
        
        var components = URLComponents(string: baseURL + endpoint)
        var items = queryItems
        // Add common params?
        // Check if these are already added in items to avoid duplicates if we retry
        if !items.contains(where: { $0.name == "part" }) {
             items.append(URLQueryItem(name: "part", value: "snippet,contentDetails"))
        }

        components?.queryItems = items
        
        guard let url = components?.url else { throw APIError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
             throw APIError.networkError(NSError(domain: "Invalid Response", code: 0))
        }
        
        if httpResponse.statusCode == 401 {
            if retryCount < 1 {
                print("Token expired, attempting refresh...")
                do {
                    try await AuthManager.shared.refreshTokens()
                    return try await performRequest(endpoint: endpoint, queryItems: queryItems, retryCount: retryCount + 1)
                } catch {
                    print("Token refresh failed: \(error)")
                    throw APIError.noToken
                }
            } else {
                throw APIError.invalidResponse(statusCode: 401, message: "Unauthorized - Token refresh failed or max retries reached")
            }
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // Attempt to decode error message
            if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw APIError.invalidResponse(statusCode: httpResponse.statusCode, message: errorResponse.error.message)
            } else {
                let rawResponse = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw APIError.invalidResponse(statusCode: httpResponse.statusCode, message: rawResponse)
            }
        }
        
        do {
            let decoded = try JSONDecoder().decode(T.self, from: data)
            return decoded
        } catch {
            print("Decoding error: \(error)")
            throw APIError.decodingError(error)
        }
    }
    
    func fetchMyPlaylists() async throws -> [Playlist] {
        let queryItems = [
            URLQueryItem(name: "mine", value: "true"),
            URLQueryItem(name: "maxResults", value: "50"),
            URLQueryItem(name: "part", value: "snippet")
        ]
        
        let response: YouTubeResponse<Playlist> = try await performRequest(endpoint: "/playlists", queryItems: queryItems)
        return response.items
    }
    
    func fetchPlaylistItems(playlistId: String, pageToken: String? = nil, maxResults: Int = 10) async throws -> (items: [PlaylistItem], nextPageToken: String?) {
        var queryItems = [
            URLQueryItem(name: "playlistId", value: playlistId),
            URLQueryItem(name: "maxResults", value: "\(maxResults)"),
             URLQueryItem(name: "part", value: "snippet,contentDetails")
        ]
        
        if let pageToken = pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        
        let response: YouTubeResponse<PlaylistItem> = try await performRequest(endpoint: "/playlistItems", queryItems: queryItems)
        return (response.items, response.nextPageToken)
    }
    
    func fetchSubscriptions() async throws -> [Subscription] {
        let queryItems = [
            URLQueryItem(name: "mine", value: "true"),
            URLQueryItem(name: "maxResults", value: "50"),
            URLQueryItem(name: "part", value: "snippet,contentDetails")
        ]
        
        let response: YouTubeResponse<Subscription> = try await performRequest(endpoint: "/subscriptions", queryItems: queryItems)
        return response.items
    }
    
    func fetchChannelDetails(channelId: String) async throws -> Channel {
        let queryItems = [
            URLQueryItem(name: "id", value: channelId),
            URLQueryItem(name: "part", value: "contentDetails")
        ]
        
        let response: YouTubeResponse<Channel> = try await performRequest(endpoint: "/channels", queryItems: queryItems)
        guard let channel = response.items.first else {
            throw APIError.invalidResponse(statusCode: 404, message: "Channel not found")
        }
        return channel
    }
}
