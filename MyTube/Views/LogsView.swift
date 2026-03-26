import SwiftUI
import Combine

// MARK: - Data Models

struct FunctionSummary: Identifiable, Codable {
    var id: String { functionName }
    let functionName: String
    let totalRuns: Int
    let files: [String]
}

struct FunctionSummaryResponse: Codable {
    let functions: [FunctionSummary]
}

struct LogDatesResponse: Codable {
    let dates: [String]
}

struct LogEntry: Identifiable, Codable {
    var id = UUID()
    let timestamp: String
    let level: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case timestamp, level, message
    }
}

struct LogRun: Identifiable, Codable {
    var id: String { startTime }
    let startTime: String
    let durationMs: Int
    let entryCount: Int
    let errorCount: Int
    let warningCount: Int
    let entries: [LogEntry]
}

struct AggregatedLogResponse: Codable {
    let functionName: String
    let date: String
    let runs: [LogRun]
    let totalEntries: Int
    let totalErrors: Int
    let totalWarnings: Int
}

// MARK: - ViewModel

@MainActor
class LogsViewModel: ObservableObject {
    @Published var dates: [String] = []
    @Published var selectedDate: String?
    @Published var functionSummaries: [FunctionSummary] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func fetchDates() async {
        isLoading = true
        errorMessage = nil

        do {
            guard let url = constructURL(path: "/get-logs") else {
                throw URLError(.badURL)
            }

            var request = URLRequest(url: url)
            request.addValue(Secrets.apiSecret, forHTTPHeaderField: "X-Api-Key")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }

            let decoded = try JSONDecoder().decode(LogDatesResponse.self, from: data)
            self.dates = decoded.dates
            if !self.dates.isEmpty && self.selectedDate == nil {
                self.selectedDate = self.dates.first
                await fetchFunctions(for: self.dates.first!)
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func fetchFunctions(for date: String) async {
        isLoading = true
        errorMessage = nil
        self.selectedDate = date

        do {
            guard let url = constructURL(path: "/get-logs", queryItems: [URLQueryItem(name: "date", value: date)]) else {
                throw URLError(.badURL)
            }

            var request = URLRequest(url: url)
            request.addValue(Secrets.apiSecret, forHTTPHeaderField: "X-Api-Key")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }

            let decoded = try JSONDecoder().decode(FunctionSummaryResponse.self, from: data)
            self.functionSummaries = decoded.functions
        } catch {
            self.errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func fetchDailyLogs(date: String, functionName: String) async throws -> AggregatedLogResponse {
        guard let url = constructURL(path: "/get-logs", queryItems: [
            URLQueryItem(name: "date", value: date),
            URLQueryItem(name: "functionName", value: functionName)
        ]) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.addValue(Secrets.apiSecret, forHTTPHeaderField: "X-Api-Key")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(AggregatedLogResponse.self, from: data)
    }

    private func constructURL(path: String, queryItems: [URLQueryItem]? = nil) -> URL? {
        let baseURL = "https://mytube-be.netlify.app/.netlify/functions"
        var components = URLComponents(string: baseURL + path)
        components?.queryItems = queryItems
        return components?.url
    }
}

// MARK: - Main List View

struct LogsView: View {
    @StateObject private var viewModel = LogsViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if viewModel.isLoading && viewModel.dates.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .multilineTextAlignment(.center)
                            .padding()
                        Button("Retry") {
                            Task { await viewModel.fetchDates() }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Date Picker
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.dates, id: \.self) { date in
                                Button(action: {
                                    Task { await viewModel.fetchFunctions(for: date) }
                                }) {
                                    Text(date)
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(viewModel.selectedDate == date ? Color.blue : Color(UIColor.systemGray5))
                                        .foregroundColor(viewModel.selectedDate == date ? .white : .primary)
                                        .cornerRadius(20)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                    }
                    .background(Color(UIColor.systemBackground))

                    Divider()

                    if viewModel.functionSummaries.isEmpty && !viewModel.isLoading {
                        Text("No logs found for this date")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(viewModel.functionSummaries) { summary in
                                NavigationLink(destination: LogDetailView(
                                    viewModel: viewModel,
                                    date: viewModel.selectedDate ?? "",
                                    functionName: summary.functionName
                                )) {
                                    FunctionSummaryRow(summary: summary)
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                        .refreshable {
                            if let date = viewModel.selectedDate {
                                await viewModel.fetchFunctions(for: date)
                            }
                        }
                    }
                }
            }
            .navigationTitle("System Logs")
            .navigationBarItems(trailing: Button(action: {
                Task { await viewModel.fetchDates() }
            }) {
                Image(systemName: "arrow.clockwise")
            })
        }
        .task {
            await viewModel.fetchDates()
        }
    }
}

// MARK: - Function Summary Row

struct FunctionSummaryRow: View {
    let summary: FunctionSummary

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: "terminal")
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.functionName)
                    .font(.headline)

                HStack(spacing: 12) {
                    Label("\(summary.totalRuns) runs", systemImage: "play.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Log Detail View (GCP-Style)

struct LogDetailView: View {
    @ObservedObject var viewModel: LogsViewModel
    let date: String
    let functionName: String

    @State private var aggregated: AggregatedLogResponse?
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedLevel: String = "ALL"
    @State private var selectedEntry: LogEntry?

    private let darkBg = Color(red: 0.10, green: 0.10, blue: 0.18)
    private let darkRowEven = Color(red: 0.12, green: 0.12, blue: 0.20)
    private let darkRowOdd = Color(red: 0.11, green: 0.11, blue: 0.19)
    private let errorRowBg = Color(red: 0.25, green: 0.08, blue: 0.08)
    private let warnRowBg = Color(red: 0.25, green: 0.20, blue: 0.05)

    private let severityLevels = ["ALL", "INFO", "WARN", "ERROR"]

    var allEntries: [(entry: LogEntry, runIndex: Int)] {
        guard let agg = aggregated else { return [] }
        var result: [(LogEntry, Int)] = []
        for (runIdx, run) in agg.runs.enumerated() {
            for entry in run.entries {
                result.append((entry, runIdx))
            }
        }
        return result.reversed()
    }

    var filteredEntries: [(entry: LogEntry, runIndex: Int)] {
        if selectedLevel == "ALL" { return allEntries }
        return allEntries.filter { $0.entry.level == selectedLevel }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(darkBg)
            } else if let error = error {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.white)
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(darkBg)
            } else if let agg = aggregated {
                VStack(spacing: 0) {
                    // Header
                    logHeader(agg)

                    // Severity Filter
                    severityFilter(agg)

                    // Log entries
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredEntries.enumerated()), id: \.offset) { index, item in
                                logRow(entry: item.entry, index: index, runIndex: item.runIndex)
                                    .onTapGesture {
                                        selectedEntry = item.entry
                                    }
                            }
                        }
                    }
                }
                .background(darkBg)
            }
        }
        .navigationTitle(functionName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color(red: 0.10, green: 0.10, blue: 0.18), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(item: $selectedEntry) { entry in
            LogEntryDetailSheet(entry: entry)
        }
        .task {
            do {
                aggregated = try await viewModel.fetchDailyLogs(date: date, functionName: functionName)
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func logHeader(_ agg: AggregatedLogResponse) -> some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(agg.functionName)
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(.white)
                    Text(agg.date)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(agg.totalEntries) entries")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.gray)
                    Text("\(agg.runs.count) runs")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            HStack(spacing: 16) {
                statBadge(value: "\(agg.totalErrors)", label: "errors", color: agg.totalErrors > 0 ? .red : .gray)
                statBadge(value: "\(agg.totalWarnings)", label: "warnings", color: agg.totalWarnings > 0 ? .yellow : .gray)

                Spacer()

                let totalDuration = agg.runs.reduce(0) { $0 + $1.durationMs }
                Text("Total: \(formattedDuration(totalDuration))")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(red: 0.08, green: 0.08, blue: 0.14))
    }

    @ViewBuilder
    private func statBadge(value: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(color.opacity(0.7))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .cornerRadius(4)
    }

    // MARK: - Severity Filter

    @ViewBuilder
    private func severityFilter(_ agg: AggregatedLogResponse) -> some View {
        HStack(spacing: 0) {
            Text("Severity")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.leading, 16)

            Spacer()

            HStack(spacing: 4) {
                ForEach(severityLevels, id: \.self) { level in
                    Button(action: { selectedLevel = level }) {
                        Text(level)
                            .font(.system(.caption2, design: .monospaced).weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(selectedLevel == level ? filterColor(level) : Color.clear)
                            .foregroundColor(selectedLevel == level ? .white : filterColor(level))
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(filterColor(level).opacity(0.4), lineWidth: selectedLevel == level ? 0 : 1)
                            )
                    }
                }
            }
            .padding(.trailing, 16)
        }
        .padding(.vertical, 8)
        .background(Color(red: 0.09, green: 0.09, blue: 0.16))
    }

    // MARK: - Log Row

    @ViewBuilder
    private func logRow(entry: LogEntry, index: Int, runIndex: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Severity badge
            Text(entry.level)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(badgeTextColor(entry.level))
                .frame(width: 42)
                .padding(.vertical, 2)
                .background(badgeColor(entry.level))
                .cornerRadius(3)

            // Timestamp
            Text(formatLogTimestamp(entry.timestamp))
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Color(white: 0.5))
                .frame(width: 78, alignment: .leading)

            // Message
            Text(entry.message)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(messageColor(entry.level))
                .lineLimit(3)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(rowBackground(level: entry.level, index: index))
    }

    // MARK: - Helpers

    private func rowBackground(level: String, index: Int) -> Color {
        switch level {
        case "ERROR": return errorRowBg
        case "WARN": return warnRowBg
        default: return index % 2 == 0 ? darkRowEven : darkRowOdd
        }
    }

    private func badgeColor(_ level: String) -> Color {
        switch level {
        case "INFO": return Color(red: 0.15, green: 0.40, blue: 0.25)
        case "WARN": return Color(red: 0.55, green: 0.45, blue: 0.10)
        case "ERROR": return Color(red: 0.60, green: 0.15, blue: 0.15)
        default: return .gray
        }
    }

    private func badgeTextColor(_ level: String) -> Color {
        switch level {
        case "INFO": return Color(red: 0.4, green: 0.9, blue: 0.5)
        case "WARN": return Color(red: 1.0, green: 0.85, blue: 0.3)
        case "ERROR": return Color(red: 1.0, green: 0.4, blue: 0.4)
        default: return .white
        }
    }

    private func messageColor(_ level: String) -> Color {
        switch level {
        case "ERROR": return Color(red: 1.0, green: 0.5, blue: 0.5)
        case "WARN": return Color(red: 1.0, green: 0.9, blue: 0.5)
        default: return Color(white: 0.85)
        }
    }

    private func filterColor(_ level: String) -> Color {
        switch level {
        case "ALL": return .blue
        case "INFO": return .green
        case "WARN": return .yellow
        case "ERROR": return .red
        default: return .gray
        }
    }

    private func formatLogTimestamp(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString) else {
            return isoString
        }
        let output = DateFormatter()
        output.dateFormat = "HH:mm:ss"
        return output.string(from: date)
    }

    private func formattedDuration(_ ms: Int) -> String {
        if ms < 1000 {
            return "\(ms)ms"
        } else {
            let seconds = Double(ms) / 1000.0
            return String(format: "%.1fs", seconds)
        }
    }
}

// MARK: - Log Entry Detail Sheet

struct LogEntryDetailSheet: View {
    let entry: LogEntry
    @Environment(\.dismiss) private var dismiss

    private let darkBg = Color(red: 0.10, green: 0.10, blue: 0.18)

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Level + Timestamp
                    HStack(spacing: 12) {
                        Text(entry.level)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(badgeTextColor(entry.level))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(badgeColor(entry.level))
                            .cornerRadius(4)

                        Text(entry.timestamp)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(Color(white: 0.5))
                    }

                    // Full message
                    Text(entry.message)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(Color(white: 0.9))
                        .textSelection(.enabled)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(darkBg)
            .navigationTitle("Log Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color(red: 0.08, green: 0.08, blue: 0.14), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func badgeColor(_ level: String) -> Color {
        switch level {
        case "INFO": return Color(red: 0.15, green: 0.40, blue: 0.25)
        case "WARN": return Color(red: 0.55, green: 0.45, blue: 0.10)
        case "ERROR": return Color(red: 0.60, green: 0.15, blue: 0.15)
        default: return .gray
        }
    }

    private func badgeTextColor(_ level: String) -> Color {
        switch level {
        case "INFO": return Color(red: 0.4, green: 0.9, blue: 0.5)
        case "WARN": return Color(red: 1.0, green: 0.85, blue: 0.3)
        case "ERROR": return Color(red: 1.0, green: 0.4, blue: 0.4)
        default: return .white
        }
    }
}
