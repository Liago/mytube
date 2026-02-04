import SwiftUI
import GoogleSignIn

@main
struct MyTubeApp: App {
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
