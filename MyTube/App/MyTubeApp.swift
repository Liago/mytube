import SwiftUI
import GoogleSignIn

@main
struct MyTubeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                .onAppear {
                    // CRITICAL: Explicitly tell the system we want to handle remote controls
                    // This is often required for background audio to work reliably on physical devices
                    UIApplication.shared.beginReceivingRemoteControlEvents()
                    print("Remote Control Events Enabled")
                }
        }
    }
}
