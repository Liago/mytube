import SwiftUI

struct PrefetchQueueView: View {
    @ObservedObject private var prefetchService = PrefetchQueueService.shared

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.all)

            if prefetchService.isLoading {
                ProgressView("Caricamento coda...")
            } else if prefetchService.queueItems.isEmpty {
                emptyStateView
            } else {
                queueListView
            }
        }
        .task {
            await prefetchService.fetchQueue()
        }
        .refreshable {
            await prefetchService.fetchQueue()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("Nessun video in coda")
                .font(.title2)
                .fontWeight(.bold)

            Text("Aggiungi video alla coda di prefetch\ndal menu di ogni video.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Aggiorna") {
                Task { await prefetchService.fetchQueue() }
            }
            .padding(.top, 10)
        }
    }

    private var queueListView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(prefetchService.queueItems) { item in
                    queueCard(for: item)
                }
            }
            .padding(.vertical)
        }
    }

    @ViewBuilder
    private func queueCard(for item: PrefetchQueueItem) -> some View {
        VideoCardView(
            videoId: item.videoId,
            title: item.title,
            channelName: item.channelName,
            channelId: item.channelId,
            date: ISO8601DateFormatter().date(from: item.addedAt),
            duration: nil,
            thumbnailURL: URL(string: item.thumbnailURL ?? "")
        ) {
            AudioPlayerService.shared.playVideo(
                videoId: item.videoId,
                title: item.title,
                author: item.channelName,
                thumbnailURL: URL(string: item.thumbnailURL ?? "")
            )
        } onChannelTap: { _ in
            // No channel navigation from queue view
        }
        .padding(.horizontal)
    }
}
