import Foundation
import BackgroundTasks
import UserNotifications
import UIKit

class BackgroundManager {
    static let shared = BackgroundManager()
    
    private let refreshTaskIdentifier = "com.mytube.refresh"
    
    // Track the last video ID or date we notified about to avoid duplicates
    // Saving to UserDefaults for persistence
    private var lastNotifiedVideoIds: [String] {
        get { UserDefaults.standard.stringArray(forKey: "lastNotifiedVideoIds") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "lastNotifiedVideoIds") }
    }
    
    func registerTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskIdentifier, using: nil) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }
    
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // Fetch every 15 mins (system decides actual time)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Background Task Scheduled: \(refreshTaskIdentifier)")
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }
    
    private func handleAppRefresh(task: BGAppRefreshTask) {
        // Schedule next refresh
        scheduleAppRefresh()
        
        // Create an operation queue or Task
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        
        task.expirationHandler = {
            // Cancel operations
            queue.cancelAllOperations()
        }
        
        // Perform the fetch
        Task {
            do {
                print("Background Fetch Started")
                let newVideos = try await fetchNewVideos()
                
                if !newVideos.isEmpty {
                    sendNotification(for: newVideos)
                }
                
                task.setTaskCompleted(success: true)
                print("Background Fetch Completed: Found \(newVideos.count) new videos")
            } catch {
                print("Background Fetch Failed: \(error)")
                task.setTaskCompleted(success: false)
            }
        }
    }
    
    private func fetchNewVideos() async throws -> [Video] {
        // reuse HomeViewModel logic or YouTubeService directly
        // Fetch subscriptions first to get channel IDs?
        // Or simpler: just fetch "Home" videos (which are subscribed channel uploads from today)
        // Replicating Home logic: fetches from 'subsriptions' -> channels -> uploads playlist
        
        // This might be heavy for background.
        // Alternative: Check YouTube Activities for 'home' feed? API doesn't expose "home".
        // We stick to the logic: Get Subscriptions -> Get Uploads.
        // Limit to top 5 subscriptions or so for background efficiency?
        
        let subscriptions = try await YouTubeService.shared.fetchSubscriptions()
        var newVideos: [Video] = []
        
        // Check top 10 subscriptions only to save resources/time
        for sub in subscriptions.prefix(10) {
            let channelId = sub.snippet.resourceId.channelId ?? ""
            if !channelId.isEmpty {
                // Get channel details for uploads playlist
                // This is multiple calls. Could be optimized if we stored playlist IDs.
                // For now, doing it.
                let channel = try await YouTubeService.shared.fetchChannelDetails(channelId: channelId)
                let uploadsId = channel.contentDetails.relatedPlaylists.uploads
                if !uploadsId.isEmpty {
                    let items = try await YouTubeService.shared.fetchPlaylistItems(playlistId: uploadsId, maxResults: 1)
                    if let latest = items.items.first {
                        // Check if published recently (e.g. today or since last check)
                        if let date = DateUtils.parseISOString(latest.snippet.publishedAt ?? ""),
                           Calendar.current.isDateInToday(date) {
                            
                             // Check if we already notified
                             if !lastNotifiedVideoIds.contains(latest.id) {
                                 // Convert PlaylistItem to Video struct properly or just use snippet
                                 // We need a Video object to return. Constructing minimal one.
                                 let video = Video(
                                    id: latest.id,
                                    snippet: latest.snippet,
                                    contentDetails: VideoContentDetails(duration: "PT0S") // Dummy
                                 )
                                 newVideos.append(video)
                                 
                                 // Mark as notified
                                 var notified = lastNotifiedVideoIds
                                 notified.append(latest.id)
                                 if notified.count > 50 { notified.removeFirst(10) } // Keep size managed
                                 lastNotifiedVideoIds = notified
                             }
                        }
                    }
                }
            }
        }
        
        return newVideos
    }
    
    private func sendNotification(for videos: [Video]) {
        let center = UNUserNotificationCenter.current()
        
        for video in videos {
            let content = UNMutableNotificationContent()
            content.title = "New Video from \(video.snippet.channelTitle ?? "Channel")"
            content.body = video.snippet.title
            content.sound = .default
            
            let request = UNNotificationRequest(identifier: video.id, content: content, trigger: nil)
            center.add(request)
        }
    }
    
    func requestPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
}
