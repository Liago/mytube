import SwiftUI

struct NotificationsView: View {
    @ObservedObject var manager = NotificationManager.shared
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.all)
                
                if manager.isLoading && manager.notifications.isEmpty {
                    ProgressView()
                        .scaleEffect(1.5)
                } else if let error = manager.errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("Unable to load notifications")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Retry") {
                            Task { await manager.fetchNotifications() }
                        }
                        .buttonStyle(.bordered)
                    }
                } else if manager.notifications.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No notifications yet")
                            .font(.title2)
                        Text("When the server prefetcher downloads new videos, they will appear here.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    List {
                        ForEach(manager.notifications) { notif in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(notif.channelInfo)
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.blue)
                                    Spacer()
                                    Text(notif.formattedDate)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                Text(notif.title)
                                    .font(.subheadline)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 4)
                            .swipeActions(edge: .trailing) {
                                Button {
                                    UIPasteboard.general.string = notif.id
                                } label: {
                                    Label("Copy ID", systemImage: "doc.on.doc")
                                }
                                .tint(.green)
                            }
                        }
                    }
                    .refreshable {
                        await manager.fetchNotifications()
                    }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                manager.markAllAsRead()
            }
        }
    }
}
