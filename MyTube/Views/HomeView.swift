import SwiftUI

struct HomeView: View {
    var body: some View {
        TabView {
            MyPlaylistsView()
                .tabItem {
                    Label("Playlists", systemImage: "music.note.list")
                }
            
            SubscriptionsView()
                .tabItem {
                    Label("Subscriptions", systemImage: "person.2.fill")
                }
        }
    }
}

// Simple Detail View placeholder

