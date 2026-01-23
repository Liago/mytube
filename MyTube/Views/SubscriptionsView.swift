import SwiftUI
import Combine

struct SubscriptionsView: View {
    @StateObject private var viewModel = SubscriptionsViewModel()
    
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
                            ForEach(viewModel.subscriptions) { subscription in
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
            self.subscriptions = try await YouTubeService.shared.fetchSubscriptions()
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
