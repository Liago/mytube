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
}
