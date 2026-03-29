import SwiftUI

/// Wrapper view that displays the appropriate content list based on sidebar selection.
/// Shows ArticleListView for feeds/lists/categories or RadioStationListView for radio stations.
struct ContentListView: View {
    @EnvironmentObject private var feedStore: FeedStore

    var body: some View {
        Group {
            switch contentType {
            case .articles:
                ArticleListView()
            case .radio:
                RadioStationListView()
            }
        }
    }

    private enum ContentType {
        case articles
        case radio
    }

    private var contentType: ContentType {
        guard let selection = feedStore.selectedSidebarItem else { return .articles }
        switch selection {
        case .radioBrowse, .radioStation, .radioCategory, .radioFavorites:
            return .radio
        default:
            return .articles
        }
    }
}
