import Foundation
import Combine

struct VideoStatus: Codable {
    let videoId: String
    var isWatched: Bool
    var progress: Double // Using 0.0 to 1.0 logic, or just seconds if simpler, but implementation plan said progress
    var lastUpdated: Date
}

struct ChannelStatus: Codable {
    let channelId: String
    var lastVisitDate: Date
}

class VideoStatusManager: ObservableObject {
    static let shared = VideoStatusManager()
    
    private let videoStatusKey = "MyTube_VideoStatus"
    private let channelStatusKey = "MyTube_ChannelStatus"
    
    @Published private var videoStatuses: [String: VideoStatus] = [:]
    private var channelStatuses: [String: ChannelStatus] = [:]
    
    private init() {
        loadData()
    }
    
    private func loadData() {
        if let data = UserDefaults.standard.data(forKey: videoStatusKey),
           let decoded = try? JSONDecoder().decode([String: VideoStatus].self, from: data) {
            videoStatuses = decoded
        }
        
        if let data = UserDefaults.standard.data(forKey: channelStatusKey),
           let decoded = try? JSONDecoder().decode([String: ChannelStatus].self, from: data) {
            channelStatuses = decoded
        }
    }
    
    private func saveData() {
        if let encoded = try? JSONEncoder().encode(videoStatuses) {
            UserDefaults.standard.set(encoded, forKey: videoStatusKey)
        }
        
        if let encoded = try? JSONEncoder().encode(channelStatuses) {
            UserDefaults.standard.set(encoded, forKey: channelStatusKey)
        }
    }
    
    // MARK: - Video Status API
    
    func saveProgress(videoId: String, progress: Double, duration: Double) {
        let ratio = duration > 0 ? progress / duration : 0
        let isWatched = ratio >= 0.90
        
        var status = videoStatuses[videoId] ?? VideoStatus(videoId: videoId, isWatched: false, progress: 0, lastUpdated: Date())
        
        status.progress = ratio
        if isWatched {
            status.isWatched = true
        }
        status.lastUpdated = Date()
        
        videoStatuses[videoId] = status
        saveData()
    }
    
    func markAsWatched(videoId: String) {
        var status = videoStatuses[videoId] ?? VideoStatus(videoId: videoId, isWatched: true, progress: 1.0, lastUpdated: Date())
        
        status.isWatched = true
        status.progress = 1.0
        status.lastUpdated = Date()
        
        videoStatuses[videoId] = status
        saveData()
    }
    
    func markAsUnwatched(videoId: String) {
        var status = videoStatuses[videoId] ?? VideoStatus(videoId: videoId, isWatched: false, progress: 0.0, lastUpdated: Date())
        
        status.isWatched = false
        status.progress = 0.0
        status.lastUpdated = Date()
        
        videoStatuses[videoId] = status
        saveData()
    }
    
    func getStatus(videoId: String) -> VideoStatus? {
        return videoStatuses[videoId]
    }
    
    // MARK: - Channel Status API
    
    func updateLastVisit(channelId: String) {
        var status = channelStatuses[channelId] ?? ChannelStatus(channelId: channelId, lastVisitDate: Date())
        status.lastVisitDate = Date()
        channelStatuses[channelId] = status
        saveData()
    }
    
    func getLastVisit(channelId: String) -> Date? {
        return channelStatuses[channelId]?.lastVisitDate
    }
    
    func isVideoNew(videoId: String, channelId: String, publishedAt: String) -> Bool {
        guard let lastVisit = getLastVisit(channelId: channelId) else {
            // If never visited, everything is new? Or nothing?
            // Usually if never visited, everything is "new" or we just treat it as unseen.
            // Let's say everything is new.
            return true
        }
        
        guard let date = DateUtils.parseISOString(publishedAt) else { return false }
        return date > lastVisit
    }
    
    // Check against a specific reference date (e.g. cached from view load)
    func isVideoNew(publishedAt: String, lastVisit: Date?) -> Bool {
        guard let lastVisit = lastVisit else {
            // If explicit nil passed (never visited), it's new
            return true
        }
        guard let date = DateUtils.parseISOString(publishedAt) else { return false }
        return date > lastVisit
    }
}
