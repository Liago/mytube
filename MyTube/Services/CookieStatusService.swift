import Foundation
import Combine
import UserNotifications

/// Model for Cookie Status Response
struct CookieStatus: Decodable {
    let totalCookies: Int
    let validCookies: Int
    let earliestExpiration: Double?
    let lastUploaded: String?
    let status: String
}

/// Service to check the status of YouTube cookies on the backend.
@MainActor
class CookieStatusService: ObservableObject {
    static let shared = CookieStatusService()
    
    @Published var status: CookieStatus?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private init() {
        requestNotificationPermission()
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
    
    private func checkAndNotifyExpiration(_ status: CookieStatus) {
        guard let expiration = status.earliestExpiration else { return }
        
        let now = Date().timeIntervalSince1970
        let daysLeft = (expiration - now) / 86400
        
        if daysLeft < 3 {
            let content = UNMutableNotificationContent()
            content.title = "Cookies in scadenza"
            content.body = daysLeft < 0 ? "I cookies di YouTube sono scaduti! Ricaricali ora." : "I cookies di YouTube scadono tra \(Int(daysLeft)) giorni. Preparati a ricaricarli."
            content.sound = .default
            
            let request = UNNotificationRequest(identifier: "cookie-expiration", content: content, trigger: nil) // Deliver immediately
            UNUserNotificationCenter.current().add(request)
        }
    }
    
    func fetchStatus() async {
        isLoading = true
        errorMessage = nil
        
        do {
            #if targetEnvironment(simulator)
            let baseURL = "http://localhost:8888"
            #else
            let baseURL = "https://mytube-be.netlify.app"
            #endif
            
            let url = URL(string: "\(baseURL)/.netlify/functions/cookie-status")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET" // Or POST if you prefer, but GET is fine here
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !Secrets.apiSecret.isEmpty {
                request.setValue(Secrets.apiSecret, forHTTPHeaderField: "x-api-key")
            }
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "Invalid response"
                isLoading = false
                return
            }
            
            if httpResponse.statusCode == 200 {
                let result = try JSONDecoder().decode(CookieStatus.self, from: data)
                self.status = result
                checkAndNotifyExpiration(result)
            } else {
                errorMessage = "Server error: \(httpResponse.statusCode)"
            }
            
        } catch {
            print("CookieStatusService: Error fetching status: \(error)")
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}
