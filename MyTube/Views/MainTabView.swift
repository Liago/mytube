import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            
            SubscriptionsView()
                .tabItem {
                    Label("Subscriptions", systemImage: "person.2.fill")
                }
            
            LogsView()
                .tabItem {
                    Label("Logs", systemImage: "doc.text.fill")
                }
            
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
        }
    }
}
