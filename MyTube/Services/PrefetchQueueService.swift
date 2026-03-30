import Foundation
import Combine

struct PrefetchQueueItem: Codable, Identifiable {
    var id: String { videoId }
    let videoId: String
    let title: String
    let channelName: String
    let channelId: String
    let thumbnailURL: String?
    let addedAt: String
}

@MainActor
class PrefetchQueueService: ObservableObject {
    static let shared = PrefetchQueueService()

    @Published var queueItems: [PrefetchQueueItem] = []
    @Published var queuedVideoIds: Set<String> = []
    @Published var isLoading = false

    private var hasFetched = false

    private var baseURL: String {
        #if targetEnvironment(simulator)
        return "http://localhost:8888"
        #else
        return "https://mytube-be.netlify.app"
        #endif
    }

    private init() {}

    func fetchQueue() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let url = URL(string: "\(baseURL)/.netlify/functions/sync-prefetch-queue")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(Secrets.apiSecret, forHTTPHeaderField: "x-api-key")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("PrefetchQueueService: Server error fetching queue")
                return
            }

            struct QueueResponse: Decodable {
                let items: [PrefetchQueueItem]
            }

            let result = try JSONDecoder().decode(QueueResponse.self, from: data)
            self.queueItems = result.items
            self.queuedVideoIds = Set(result.items.map { $0.videoId })
            self.hasFetched = true
            print("PrefetchQueueService: Fetched \(result.items.count) queue items")

        } catch {
            print("PrefetchQueueService: Error fetching queue: \(error)")
        }
    }

    func fetchQueueIfNeeded() async {
        guard !hasFetched else { return }
        await fetchQueue()
    }

    func addToQueue(item: PrefetchQueueItem) async {
        // Update locally first
        guard !queuedVideoIds.contains(item.videoId) else { return }
        queueItems.append(item)
        queuedVideoIds.insert(item.videoId)

        // Sync to backend
        await syncQueue()
    }

    func removeFromQueue(videoId: String) async {
        queueItems.removeAll { $0.videoId == videoId }
        queuedVideoIds.remove(videoId)

        await syncQueue()
    }

    func isQueued(_ videoId: String) -> Bool {
        return queuedVideoIds.contains(videoId)
    }

    private func syncQueue() async {
        do {
            let url = URL(string: "\(baseURL)/.netlify/functions/sync-prefetch-queue")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(Secrets.apiSecret, forHTTPHeaderField: "x-api-key")

            let payload: [String: Any] = [
                "items": queueItems.map { item in
                    [
                        "videoId": item.videoId,
                        "title": item.title,
                        "channelName": item.channelName,
                        "channelId": item.channelId,
                        "thumbnailURL": item.thumbnailURL ?? "",
                        "addedAt": item.addedAt
                    ] as [String: String]
                },
                "lastUpdated": ISO8601DateFormatter().string(from: Date())
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("PrefetchQueueService: Server error syncing queue")
                return
            }

            print("PrefetchQueueService: Queue synced successfully (\(queueItems.count) items)")

        } catch {
            print("PrefetchQueueService: Error syncing queue: \(error)")
        }
    }
}
