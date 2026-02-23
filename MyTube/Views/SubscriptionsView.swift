import SwiftUI
import Combine

struct SubscriptionsView: View {
    @StateObject private var viewModel = SubscriptionsViewModel()
    @ObservedObject private var videoStatusManager = VideoStatusManager.shared
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.all)
                
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                } else if let error = viewModel.errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("Oops! Something went wrong.")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Try Again") {
                            Task { await viewModel.loadData() }
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(sortedSubscriptions) { subscription in
                                NavigationLink(destination: ChannelDetailView(subscription: subscription)) {
                                    HStack(spacing: 16) {
                                        AsyncImage(url: URL(string: subscription.snippet.thumbnails.defaultThumbnail?.url ?? "")) { image in
                                            image.resizable()
                                                .aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            Color(UIColor.secondarySystemBackground)
                                        }
                                        .frame(width: 50, height: 50)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 1))
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(subscription.snippet.title)
                                                .font(.headline) // Uses system design which is naturally nice, can be bold
                                                .foregroundColor(.primary)
                                            
                                            Text(subscription.snippet.description)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                        

                                        
                                        Spacer()
                                        
                                        // Prefetch Toggle
                                        Button(action: {
                                            videoStatusManager.togglePrefetchSubscription(channelId: subscription.snippet.resourceId.channelId ?? "")
                                        }) {
                                            let isPrefetch = videoStatusManager.isPrefetchSubscription(channelId: subscription.snippet.resourceId.channelId ?? "")
                                            Image(systemName: isPrefetch ? "cloud.bolt.fill" : "cloud.bolt")
                                                .font(.body)
                                                .foregroundColor(isPrefetch ? .blue : .gray)
                                                .padding(8)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        
                                        // Home Toggle
                                        Button(action: {
                                            videoStatusManager.toggleHomeSubscription(channelId: subscription.snippet.resourceId.channelId ?? "")
                                        }) {
                                            let isHome = videoStatusManager.isHomeSubscription(channelId: subscription.snippet.resourceId.channelId ?? "")
                                            Image(systemName: isHome ? "house.fill" : "house")
                                                .font(.body)
                                                .foregroundColor(isHome ? .blue : .gray) // Explicit colors
                                                .padding(8)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.gray.opacity(0.5))
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(Color(UIColor.systemBackground))
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Divider()
                                    .padding(.leading, 86) // Aligned with text start
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .refreshable {
                        await viewModel.loadData()
                    }
                }
            }
            .navigationTitle("Subscriptions")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            // Only load if empty to avoid reloading on every appear if staying locally
            if viewModel.subscriptions.isEmpty {
                await viewModel.loadData()
            }
        }
    }
    
    private var sortedSubscriptions: [Subscription] {
        viewModel.subscriptions.sorted { sub1, sub2 in
            let id1 = sub1.snippet.resourceId.channelId ?? ""
            let id2 = sub2.snippet.resourceId.channelId ?? ""
            
            let isHome1 = videoStatusManager.isHomeSubscription(channelId: id1)
            let isHome2 = videoStatusManager.isHomeSubscription(channelId: id2)
            
            if isHome1 != isHome2 {
                return isHome1 // True comes first
            }
            
            let isPrefetch1 = videoStatusManager.isPrefetchSubscription(channelId: id1)
            let isPrefetch2 = videoStatusManager.isPrefetchSubscription(channelId: id2)
            
            if isPrefetch1 != isPrefetch2 {
                return isPrefetch1 // True comes first
            }
            
            return sub1.snippet.title < sub2.snippet.title
        }
    }
}

@MainActor
class SubscriptionsViewModel: ObservableObject {
    @Published var subscriptions: [Subscription] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetchedSubscriptions = try await YouTubeService.shared.fetchSubscriptions()
            
            // Sort: Home subscriptions first, then prefetch, then alphabetical
            self.subscriptions = fetchedSubscriptions.sorted { sub1, sub2 in
                let id1 = sub1.snippet.resourceId.channelId ?? ""
                let id2 = sub2.snippet.resourceId.channelId ?? ""
                
                let isHome1 = VideoStatusManager.shared.isHomeSubscription(channelId: id1)
                let isHome2 = VideoStatusManager.shared.isHomeSubscription(channelId: id2)
                
                if isHome1 != isHome2 {
                    return isHome1 // True comes first
                }
                
                let isPrefetch1 = VideoStatusManager.shared.isPrefetchSubscription(channelId: id1)
                let isPrefetch2 = VideoStatusManager.shared.isPrefetchSubscription(channelId: id2)
                
                if isPrefetch1 != isPrefetch2 {
                    return isPrefetch1 // True comes first
                }
                
                return sub1.snippet.title < sub2.snippet.title
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
