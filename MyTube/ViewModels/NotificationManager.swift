import Foundation
import Combine
import UserNotifications

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var notifications: [AppNotification] = []
    @Published var unreadCount: Int = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Store read IDs locally to compute unread notifications
    private let readNotificationsKey = "ReadNotificationIDs"
    // Store already prompted notifications
    private let notifiedKey = "NotifiedNotificationIDs"
    
    private init() {
        // Request Permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        
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
            
            // Trigger Local System Notifications for new items
            triggerLocalNotificationsForNewItems()
            updateUnreadCount()
            
        } catch {
            self.errorMessage = error.localizedDescription
            print("Notification fetch error: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    private func triggerLocalNotificationsForNewItems() {
        let notifiedIds = UserDefaults.standard.stringArray(forKey: notifiedKey) ?? []
        var newNotifiedIds = notifiedIds
        var hasNew = false
        
        // Walk from oldest to newest to throw notifications sequentially
        for notif in self.notifications.reversed() {
            let key = "\(notif.id)_\(notif.timestamp)"
            if !notifiedIds.contains(key) {
                scheduleLocalNotification(for: notif)
                newNotifiedIds.append(key)
                hasNew = true
            }
        }
        
        if hasNew {
            if newNotifiedIds.count > 200 { newNotifiedIds.removeFirst(100) }
            UserDefaults.standard.set(newNotifiedIds, forKey: notifiedKey)
        }
    }
    
    private func scheduleLocalNotification(for notif: AppNotification) {
        let content = UNMutableNotificationContent()
        content.title = "Prefetch Completato"
        content.body = "\(notif.title) da \(notif.channelInfo)"
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: "prefetch_\(notif.id)_\(notif.timestamp)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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
