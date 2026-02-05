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
            
            MyPlaylistsView()
                .tabItem {
                    Label("Playlists", systemImage: "music.note.list")
                }
            
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
        }
    }
}
