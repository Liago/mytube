import Foundation

struct DateUtils {
    // ISO8601DateFormatter is thread-safe
    static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    // DateFormatter is NOT thread-safe, so we make it a computed property to return a new instance,
    // or we could use a thread-local approach, but creating one for display is usually fine performance-wise for UI.
    // However, for lists, it might be slow.
    // Better approach for iOS 15+: Use .formatted() API.
    // Assuming iOS 15+ for SwiftUI, we can use the new API or just create new formatters.
    
    static func parseISOString(_ isoString: String) -> Date? {
        // Try standard ISO8601 first
        if let date = isoFormatter.date(from: isoString) {
            return date
        }
        
        // Try with fractional seconds
        // Date.ISO8601FormatStyle is thread-safe
        let strategy = Date.ISO8601FormatStyle().year().month().day().time(includingFractionalSeconds: true)
        return try? Date(isoString, strategy: strategy)
    }

    static func formatISOString(_ isoString: String) -> String {
        guard let date = parseISOString(isoString) else { return isoString }
        return date.formatted(date: .numeric, time: .shortened)
    }
    
    static func isToday(_ isoString: String) -> Bool {
        guard let date = parseISOString(isoString) else { return false }
        return Calendar.current.isDateInToday(date)
    }

    static func formatDuration(_ isoDuration: String) -> String {
        // PT5M30S -> 5:30
        // PT1H2M3S -> 1:02:03
        
        let pattern = "PT(?:(\\d+)H)?(?:(\\d+)M)?(?:(\\d+)S)?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
        
        let nsString = isoDuration as NSString
        let results = regex.matches(in: isoDuration, range: NSRange(location: 0, length: nsString.length))
        
        guard let match = results.first else { return "" }
        
        var hours = 0
        var minutes = 0
        var seconds = 0
        
        if let hRange = Range(match.range(at: 1), in: isoDuration) {
            hours = Int(isoDuration[hRange]) ?? 0
        }
        
        if let mRange = Range(match.range(at: 2), in: isoDuration) {
            minutes = Int(isoDuration[mRange]) ?? 0
        }
        
        if let sRange = Range(match.range(at: 3), in: isoDuration) {
            seconds = Int(isoDuration[sRange]) ?? 0
        }
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
