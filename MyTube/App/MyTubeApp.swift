import SwiftUI
import GoogleSignIn
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // This allows the notification to show as a banner even if the app is currently in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}

@main
struct MyTubeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        BackgroundManager.shared.registerTasks()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                .onAppear {
                    // CRITICAL: Remote controls
                    UIApplication.shared.beginReceivingRemoteControlEvents()
                    print("Remote Control Events Enabled")
                    
                    // Request Notification Permissions
                    BackgroundManager.shared.requestPermissions()
                }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                BackgroundManager.shared.scheduleAppRefresh()
            }
        }
    }
}
