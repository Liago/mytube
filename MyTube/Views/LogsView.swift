import SwiftUI

struct LogFile: Identifiable, Codable {
    var id: String { key }
    let filename: String
    let key: String
    let functionName: String
    let timestamp: Int
    let size: Int
    
    var formattedTime: String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct LogDatesResponse: Codable {
    let dates: [String]
}

struct LogFilesResponse: Codable {
    let files: [LogFile]
}

struct LogEntry: Identifiable, Codable {
    let id = UUID()
    let timestamp: String
    let level: String
    let message: String
}

struct LogDetail: Codable {
    let functionName: String
    let startTime: String
    let durationMs: Int
    let logs: [LogEntry]
}

@MainActor
class LogsViewModel: ObservableObject {
    @Published var dates: [String] = []
    @Published var selectedDate: String?
    @Published var files: [LogFile] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Group files by function name for the current date
    var groupedFiles: [String: [LogFile]] {
        Dictionary(grouping: files, by: { $0.functionName })
    }
    
    func fetchDates() async {
        isLoading = true
        errorMessage = nil
        
        do {
            guard let url = constructURL(path: "/get-logs") else {
                throw URLError(.badURL)
            }
            
            var request = URLRequest(url: url)
            request.addValue(AppConfig.apiSecret, forHTTPHeaderField: "X-Api-Key")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            
            let decoded = try JSONDecoder().decode(LogDatesResponse.self, from: data)
            self.dates = decoded.dates
            if !self.dates.isEmpty && self.selectedDate == nil {
                self.selectedDate = self.dates.first
                await fetchFiles(for: self.dates.first!)
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func fetchFiles(for date: String) async {
        isLoading = true
        errorMessage = nil
        self.selectedDate = date
        
        do {
            guard let url = constructURL(path: "/get-logs", queryItems: [URLQueryItem(name: "date", value: date)]) else {
                throw URLError(.badURL)
            }
            
            var request = URLRequest(url: url)
            request.addValue(AppConfig.apiSecret, forHTTPHeaderField: "X-Api-Key")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            
            let decoded = try JSONDecoder().decode(LogFilesResponse.self, from: data)
            self.files = decoded.files
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func fetchLogContent(date: String, filename: String) async throws -> LogDetail {
        guard let url = constructURL(path: "/get-logs", queryItems: [
            URLQueryItem(name: "date", value: date),
            URLQueryItem(name: "logFile", value: filename)
        ]) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.addValue(AppConfig.apiSecret, forHTTPHeaderField: "X-Api-Key")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        return try JSONDecoder().decode(LogDetail.self, from: data)
    }
    
    private func constructURL(path: String, queryItems: [URLQueryItem]? = nil) -> URL? {
        var components = URLComponents(string: AppConfig.apiBaseURL + path)
        components?.queryItems = queryItems
        return components?.url
    }
}

struct LogsView: View {
    @StateObject private var viewModel = LogsViewModel()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if viewModel.isLoading && viewModel.dates.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage {
                    VStack {
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
                    // Date Picker ScrollView
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(viewModel.dates, id: \.self) { date in
                                Button(action: {
                                    Task { await viewModel.fetchFiles(for: date) }
                                }) {
                                    Text(date)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(viewModel.selectedDate == date ? Color.blue : Color(UIColor.systemGray5))
                                        .foregroundColor(viewModel.selectedDate == date ? .white : .primary)
                                        .cornerRadius(20)
                                }
                            }
                        }
                        .padding()
                    }
                    .background(Color(UIColor.systemBackground))
                    
                    Divider()
                    
                    if viewModel.files.isEmpty && !viewModel.isLoading {
                        Text("No logs found for this date")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(Array(viewModel.groupedFiles.keys.sorted()), id: \.self) { functionName in
                                Section(header: Text(functionName.capitalized)) {
                                    ForEach(viewModel.groupedFiles[functionName] ?? []) { file in
                                        NavigationLink(destination: LogDetailView(viewModel: viewModel, date: viewModel.selectedDate ?? "", file: file)) {
                                            HStack {
                                                Image(systemName: "doc.text")
                                                    .foregroundColor(.gray)
                                                VStack(alignment: .leading) {
                                                    Text(file.formattedTime)
                                                        .font(.headline)
                                                    Text("\(file.size / 1024) KB")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .refreshable {
                            if let date = viewModel.selectedDate {
                                await viewModel.fetchFiles(for: date)
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

struct LogDetailView: View {
    @ObservedObject var viewModel: LogsViewModel
    let date: String
    let file: LogFile
    
    @State private var detail: LogDetail?
    @State private var isLoading = true
    @State private var error: String?
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let error = error {
                Text(error).foregroundColor(.red).padding()
            } else if let detail = detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Duration")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(detail.durationMs) ms")
                                    .font(.headline)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("Total Entries")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(detail.logs.count)")
                                    .font(.headline)
                            }
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(10)
                        
                        ForEach(detail.logs) { log in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .top) {
                                    Text(levelIcon(log.level))
                                        .foregroundColor(levelColor(log.level))
                                        .frame(width: 24)
                                    
                                    VStack(alignment: .leading) {
                                        Text(log.message)
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(.primary)
                                        
                                        Text(formatLogTime(log.timestamp))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(file.formattedTime)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                detail = try await viewModel.fetchLogContent(date: date, filename: file.filename)
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
    
    private func levelIcon(_ level: String) -> String {
        switch level {
        case "INFO": return "ℹ️"
        case "WARN": return "⚠️"
        case "ERROR": return "❌"
        default: return "📄"
        }
    }
    
    private func levelColor(_ level: String) -> Color {
        switch level {
        case "INFO": return .blue
        case "WARN": return .orange
        case "ERROR": return .red
        default: return .primary
        }
    }
    
    private func formatLogTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString) else {
            return isoString
        }
        let output = DateFormatter()
        output.timeStyle = .medium
        return output.string(from: date)
    }
}
