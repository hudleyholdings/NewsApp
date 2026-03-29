import SwiftUI

/// Wrapper view that displays the appropriate reader/viewer based on sidebar selection.
/// Shows ReaderView for articles or RadioPlayerView for radio stations.
struct ContentReaderView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @StateObject private var radioStore = RadioStore.shared
    let onExpand: (() -> Void)?
    let onClose: (() -> Void)?

    init(onExpand: (() -> Void)? = nil, onClose: (() -> Void)? = nil) {
        self.onExpand = onExpand
        self.onClose = onClose
    }

    var body: some View {
        Group {
            switch contentType {
            case .article:
                ReaderView(onExpand: onExpand, onClose: onClose)
            case .radio(let station):
                RadioPlayerView(station: station)
            case .none:
                emptyState
            }
        }
    }

    private enum ContentType {
        case article
        case radio(RadioStation)
        case none
    }

    private var contentType: ContentType {
        guard let selection = feedStore.selectedSidebarItem else { return .none }
        switch selection {
        case .radioStation(let id):
            if let station = radioStore.stations.first(where: { $0.id == id }) {
                return .radio(station)
            }
            return .none
        case .radioBrowse, .radioCategory, .radioFavorites:
            // Show instruction to select a station
            return .none
        default:
            // For feeds, lists, categories - show article reader
            if feedStore.selectedArticleID != nil {
                return .article
            }
            return .none
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: emptyStateIcon)
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text(emptyStateTitle)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(emptyStateSubtitle)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateIcon: String {
        guard let selection = feedStore.selectedSidebarItem else { return "newspaper" }
        switch selection {
        case .radioBrowse, .radioStation, .radioCategory, .radioFavorites:
            return "radio"
        default:
            return "newspaper"
        }
    }

    private var emptyStateTitle: String {
        guard let selection = feedStore.selectedSidebarItem else { return "Select a Story" }
        switch selection {
        case .radioBrowse, .radioCategory, .radioFavorites:
            return "Select a Station"
        default:
            return "Select a Story"
        }
    }

    private var emptyStateSubtitle: String {
        guard let selection = feedStore.selectedSidebarItem else { return "Choose an article from the list to read it here." }
        switch selection {
        case .radioBrowse, .radioCategory, .radioFavorites:
            return "Choose a station from the list to listen."
        default:
            return "Choose an article from the list to read it here."
        }
    }
}
