import Foundation
import Combine

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var notifications: [AppNotification] = []
    @Published var unreadCount: Int = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Store read IDs locally to compute unread notifications
    private let readNotificationsKey = "ReadNotificationIDs"
    
    private init() {
        // Load initial state
        Task {
            await fetchNotifications()
        }
    }
    
    func fetchNotifications() async {
        isLoading = true
        errorMessage = nil
        
        do {
            guard let url = constructURL(path: "/notifications") else {
                throw URLError(.badURL)
            }
            
            var request = URLRequest(url: url)
            request.addValue(Secrets.apiSecret, forHTTPHeaderField: "X-Api-Key")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            
            self.notifications = try JSONDecoder().decode([AppNotification].self, from: data)
            updateUnreadCount()
            
        } catch {
            self.errorMessage = error.localizedDescription
            print("Notification fetch error: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    func markAllAsRead() {
        let allIds = notifications.map { "\($0.id)_\($0.timestamp)" }
        UserDefaults.standard.set(allIds, forKey: readNotificationsKey)
        unreadCount = 0
    }
    
    private func updateUnreadCount() {
        let readIds = UserDefaults.standard.stringArray(forKey: readNotificationsKey) ?? []
        // we use a composite of id+timestamp as unique key because a video might be prefetched multiple times over months if deleted
        let unread = notifications.filter { !readIds.contains("\($0.id)_\($0.timestamp)") }
        self.unreadCount = unread.count
    }
    
    private func constructURL(path: String) -> URL? {
        let baseURL = "https://mytube-be.netlify.app/.netlify/functions"
        var components = URLComponents(string: baseURL + path)
        return components?.url
    }
}
