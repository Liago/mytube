import Foundation

struct DateUtils {
    static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        return formatter
    }()
    
    static func parseISOString(_ isoString: String) -> Date? {
        // Try standard ISO8601 first
        if let date = isoFormatter.date(from: isoString) {
            return date
        }
        
        // Try with fractional seconds if the standard one failed
        let strategy = Date.ISO8601FormatStyle().year().month().day().time(includingFractionalSeconds: true)
        return try? Date(isoString, strategy: strategy)
    }

    static func formatISOString(_ isoString: String) -> String {
        if let date = parseISOString(isoString) {
            return displayFormatter.string(from: date)
        }
        return isoString
    }
    
    static func isToday(_ isoString: String) -> Bool {
        guard let date = parseISOString(isoString) else { return false }
        return Calendar.current.isDateInToday(date)
    }
}
