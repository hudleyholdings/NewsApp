import SwiftUI
import AppKit

struct MainSplitView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var settings: SettingsStore
    @State private var showingFeedManager = false
    @State private var showingNewspaper = false
    @State private var showingTVView = false
    @State private var showReaderPane = true
    @State private var isReaderExpanded = false
    @State private var focusedPane: FocusedPane = .sidebar
    @State private var previewImageURL: URL?
    @State private var keyMonitor: Any?
    @State private var pendingMarkAllScope: SidebarSelection?
    @State private var pendingMarkAllCount: Int = 0

    /// Show a confirmation dialog when Mark All as Read would affect more than this many articles.
    private let markAllConfirmThreshold = 25

    enum FocusedPane: Equatable {
        case sidebar, articleList, reader
    }

    private var isMainView: Bool {
        !showingTVView && !showingNewspaper && !isReaderExpanded
    }

    // MARK: - Unified Toolbar (structurally stable: always 2 ToolbarItems)

    // MARK: - Header title (based on sidebar selection)

    private var headerTitle: String {
        guard let selection = feedStore.selectedSidebarItem else { return "All Feeds" }
        switch selection {
        case .feed(let id):
            return feedStore.feedName(for: id) ?? "Feed"
        case .list(let id):
            if id == FeedStore.allFeedsID { return "All Feeds" }
            if id == FeedStore.favoritesID { return "Bookmarks" }
            return feedStore.listName(for: id) ?? "Feeds"
        case .category(let name):
            return name
        case .radioBrowse:
            return "Radio"
        case .radioFavorites:
            return "Favorite Stations"
        case .radioStation:
            return "Radio"
        case .radioCategory:
            return "Radio"
        case .radioUserStations:
            return "My Stations"
        }
    }

    // MARK: - Main toolbar (all controls in native toolbar = single row)

    @ToolbarContentBuilder
    private var unifiedToolbarContent: some ToolbarContent {
        // Toolbar content is always the same — never changes structurally.
        // Overlay views live OUTSIDE NavigationStack so they can't disrupt it.
        ToolbarItem(placement: .navigation) {
            mainToolbarLeadingContent
        }

        ToolbarItem(placement: .primaryAction) {
            mainToolbarTrailingContent
        }
    }

    // Extracted to avoid type-checker timeouts
    private var mainToolbarLeadingContent: some View {
        HStack(spacing: 8) {
            Text(headerTitle)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .allowsHitTesting(false)

            Divider().frame(height: 16)

            MainWeatherWidget()

            HStack(spacing: 2) {
                HeaderBarButton(
                    icon: "rectangle.split.3x1",
                    label: "Columns",
                    isActive: !showingNewspaper && !showingTVView
                ) {
                    showingNewspaper = false
                    showingTVView = false
                }

                HeaderBarButton(
                    icon: "square.grid.2x2",
                    label: cardsButtonLabel,
                    isActive: showingNewspaper && !isRadioSelected
                ) {
                    showingTVView = false
                    showingNewspaper = true
                }
                .disabled(isRadioSelected)
                .opacity(isRadioSelected ? 0.35 : 1)

                HeaderBarButton(
                    icon: "tv",
                    label: tvButtonLabel,
                    isActive: showingTVView && !isRadioSelected
                ) {
                    showingNewspaper = false
                    showingTVView = true
                }
                .disabled(isRadioSelected)
                .opacity(isRadioSelected ? 0.35 : 1)
            }
            .padding(2)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HeaderBarButton(icon: "plus", label: "Add Feed") {
                NotificationCenter.default.post(name: .openFeedManager, object: nil)
            }

            if feedStore.isRefreshing {
                RefreshProgressChip(
                    completed: feedStore.refreshCompletedCount,
                    total: feedStore.refreshTotalCount
                )
            } else {
                HeaderBarButton(
                    icon: "arrow.clockwise",
                    label: "Refresh"
                ) {
                    // User-initiated refresh = hard refresh (ignore stored
                    // etag / last-modified) so 304-stuck feeds recover.
                    Task { await feedStore.refreshAll(force: true) }
                }
            }

            HeaderBarButton(
                icon: "checkmark.circle",
                label: markAllAsReadTooltip
            ) {
                requestMarkAllAsRead()
            }
            .disabled(markAllAsReadDisabled)
        }
    }

    // MARK: - Mark All as Read

    /// Cards and TV layouts only make sense for article feeds. Radio selections
    /// don't have articles to render, so we disable those toggles outright.
    private var isRadioSelected: Bool {
        guard let selection = feedStore.selectedSidebarItem else { return false }
        switch selection {
        case .radioBrowse, .radioStation, .radioCategory, .radioFavorites, .radioUserStations:
            return true
        default:
            return false
        }
    }

    private var cardsButtonLabel: String {
        isRadioSelected ? "Cards view isn't available for radio" : "Cards"
    }

    private var tvButtonLabel: String {
        isRadioSelected ? "TV view isn't available for radio" : "TV"
    }

    private var markAllAsReadUnreadCount: Int {
        feedStore.badgeCount(for: feedStore.selectedSidebarItem, mode: .unread)
    }

    private var markAllAsReadDisabled: Bool {
        markAllAsReadUnreadCount == 0
    }

    private var markAllAsReadTooltip: String {
        let count = markAllAsReadUnreadCount
        guard count > 0 else { return "Mark All as Read" }
        let scope = scopeName(for: feedStore.selectedSidebarItem) ?? "this view"
        let noun = count == 1 ? "article" : "articles"
        return "Mark all \(count) \(noun) in \(scope) as read"
    }

    private func requestMarkAllAsRead() {
        let scope = feedStore.selectedSidebarItem
        let count = feedStore.badgeCount(for: scope, mode: .unread)
        guard count > 0 else { return }
        if count > markAllConfirmThreshold {
            pendingMarkAllScope = scope
            pendingMarkAllCount = count
        } else {
            feedStore.markAllAsRead(for: scope)
        }
    }

    private var markAllConfirmationTitle: String {
        let scope = scopeName(for: pendingMarkAllScope) ?? "this view"
        let noun = pendingMarkAllCount == 1 ? "article" : "articles"
        return "Mark \(pendingMarkAllCount) \(noun) in \(scope) as read?"
    }

    private func scopeName(for selection: SidebarSelection?) -> String? {
        guard let selection else { return "All Feeds" }
        switch selection {
        case .feed(let id):
            return feedStore.feedName(for: id)
        case .list(let id):
            return feedStore.listName(for: id)
        case .category(let name):
            return name
        case .radioBrowse, .radioStation, .radioCategory, .radioFavorites, .radioUserStations:
            return nil
        }
    }

    private var mainToolbarTrailingContent: some View {
        HStack(spacing: 8) {
            HeaderSearchField(text: $feedStore.searchText)

            SettingsLink(label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            })
            .buttonStyle(.borderless)
            .help("Settings")

            if !showReaderPane {
                HeaderBarButton(
                    icon: "sidebar.trailing",
                    label: "Show Reader"
                ) {
                    withAnimation { showReaderPane = true }
                }
            }
        }
    }

    // Stable content for NavigationStack — NEVER changes structurally.
    // Overlay views (Cards, TV, Expanded Reader) live OUTSIDE NavigationStack
    // so they cannot disrupt macOS NSToolbar item reconciliation.
    private var stableMainContent: some View {
        MainPanesView(
            showReaderPane: $showReaderPane,
            isReaderExpanded: $isReaderExpanded
        )
    }

    // MARK: - Keyboard Navigation

    private var hasLocation: Bool {
        settings.weatherLatitude != 0 && settings.weatherLongitude != 0
    }

    private var hasRadioFavorites: Bool {
        !RadioStore.shared.favorites.isEmpty
    }
    private var hasUserStations: Bool {
        !RadioStore.shared.userStations.isEmpty
    }

    /// When focus enters the article-list pane, make sure a row is selected so the user
    /// gets immediate visual feedback that keyboard input is now driving this column.
    /// Skip if the existing selection is still valid for the current filtered list.
    private func ensureArticleSelected() {
        let articles = feedStore.filteredSortedArticles()
        guard !articles.isEmpty else { return }
        if let id = feedStore.selectedArticleID, articles.contains(where: { $0.id == id }) {
            return
        }
        feedStore.selectedArticleID = articles.first?.id
    }

    private func moveFocusLeft() {
        switch focusedPane {
        case .reader:
            focusedPane = .articleList
        case .articleList:
            focusedPane = .sidebar
        case .sidebar:
            break
        }
    }

    private func moveFocusRight() {
        switch focusedPane {
        case .sidebar:
            // Don't move focus into an empty article list — the user would be "in" the
            // middle column with nothing to act on and no visual cue that pressing right
            // again won't help. Keep focus on the sidebar so up/down can find content.
            guard !feedStore.filteredSortedArticles().isEmpty else { return }
            focusedPane = .articleList
            ensureArticleSelected()
        case .articleList:
            if showReaderPane {
                focusedPane = .reader
            } else if feedStore.selectedArticleID != nil {
                withAnimation { showReaderPane = true }
                focusedPane = .reader
            }
        case .reader:
            break
        }
    }

    private func navigateUp() {
        switch focusedPane {
        case .sidebar:
            feedStore.navigateSidebar(direction: -1, settings: settings, radioEnabled: settings.radioEnabled, hasRadioFavorites: hasRadioFavorites, hasUserStations: hasUserStations)
        case .articleList:
            feedStore.navigateArticle(direction: -1)
        case .reader:
            NotificationCenter.default.post(name: .scrollReader, object: nil, userInfo: ["direction": -1])
        }
    }

    private func navigateDown() {
        switch focusedPane {
        case .sidebar:
            feedStore.navigateSidebar(direction: 1, settings: settings, radioEnabled: settings.radioEnabled, hasRadioFavorites: hasRadioFavorites, hasUserStations: hasUserStations)
        case .articleList:
            feedStore.navigateArticle(direction: 1)
        case .reader:
            NotificationCenter.default.post(name: .scrollReader, object: nil, userInfo: ["direction": 1])
        }
    }

    private func handleEnter() {
        switch focusedPane {
        case .sidebar:
            focusedPane = .articleList
        case .articleList:
            if feedStore.selectedArticleID != nil {
                if showReaderPane {
                    focusedPane = .reader
                }
            }
        case .reader:
            if feedStore.selectedArticleID != nil {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isReaderExpanded = true
                }
            }
        }
    }

    private func handleEscape() {
        switch focusedPane {
        case .sidebar:
            break
        case .articleList:
            feedStore.selectedArticleID = nil
            focusedPane = .sidebar
        case .reader:
            focusedPane = .articleList
        }
    }

    private func handleSpace() {
        switch focusedPane {
        case .sidebar:
            focusedPane = .articleList
        case .articleList:
            if feedStore.selectedArticleID != nil && showReaderPane {
                focusedPane = .reader
            }
        case .reader:
            // Pass to content (scroll) — return without handling
            break
        }
    }

    private func handleKeyboardEvent(_ event: NSEvent) -> Bool {
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            return false
        }

        if previewImageURL != nil {
            if event.keyCode == 53 {
                previewImageURL = nil
                return true
            }
            return false
        }

        // ESC closes the Newspaper / TV / expanded reader overlays. We handle
        // it here (above the `isMainView` gate) instead of via `.focusable() +
        // .onKeyPress` on those views because focusable wraps an NSResponder
        // that on macOS 26 absorbs mouse-wheel events meant for the inner
        // ScrollView.
        if event.keyCode == 53 {
            if isReaderExpanded {
                isReaderExpanded = false
                return true
            }
            if showingNewspaper {
                showingNewspaper = false
                return true
            }
            if showingTVView {
                showingTVView = false
                return true
            }
        }

        guard isMainView else { return false }

        switch event.keyCode {
        case 48: // tab
            if event.modifierFlags.contains(.shift) {
                moveFocusLeft()
            } else {
                moveFocusRight()
            }
            return true
        case 36, 76: // return, keypad enter
            handleEnter()
            return true
        case 53: // escape
            handleEscape()
            return true
        case 49: // space
            handleSpace()
            return true
        case 123: // left arrow
            moveFocusLeft()
            return true
        case 124: // right arrow
            moveFocusRight()
            return true
        case 125: // down arrow
            navigateDown()
            return true
        case 126: // up arrow
            navigateUp()
            return true
        default:
            break
        }

        let char = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if char == "a", event.modifierFlags.contains(.shift) {
            feedStore.markAllAsRead(for: feedStore.selectedSidebarItem)
            return true
        }

        switch char {
        case "k":
            navigateUp()
        case "j":
            navigateDown()
        case "h":
            moveFocusLeft()
        case "l":
            moveFocusRight()
        case "s":
            feedStore.toggleStarCurrentArticle()
        case "u":
            feedStore.toggleReadCurrentArticle()
        case "o":
            feedStore.openCurrentArticleInBrowser()
        case "r":
            Task { await feedStore.refreshAll(force: true) }
        case "1":
            showingNewspaper = false
            showingTVView = false
        case "2":
            showingTVView = false
            showingNewspaper = true
        case "3":
            showingNewspaper = false
            showingTVView = true
        default:
            return false
        }
        return true
    }

    // Overlay views rendered outside NavigationStack
    @ViewBuilder
    private var overlayViews: some View {
        if showingTVView {
            TVView(isPresented: $showingTVView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if showingNewspaper {
            MasonryCardsView(isPresented: $showingNewspaper)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if isReaderExpanded {
            ExpandedReaderView(
                isExpanded: $isReaderExpanded,
                showReaderPane: $showReaderPane
            )
            .frame(minWidth: 800, minHeight: 600)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var feedManagerOverlay: some View {
        Group {
            if showingFeedManager {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showingFeedManager = false
                        }

                    FeedManagementView(isPresented: $showingFeedManager)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
                }
            }
        }
    }

    @ViewBuilder
    private var imagePreviewOverlay: some View {
        if let previewImageURL {
            FullWindowImagePreview(url: previewImageURL) {
                self.previewImageURL = nil
            }
            .transition(.opacity)
        }
    }

    private var hasOverlay: Bool {
        showingTVView || showingNewspaper || isReaderExpanded
    }

    var body: some View {
        // NavigationStack is ALWAYS fully visible (opacity 1).
        // Setting opacity(0) on NavigationStack causes macOS to
        // garbage-collect NSToolbar items permanently.
        // Overlay views use .overlay modifier (not ZStack siblings)
        // so they don't change the NavigationStack's structural content.
        NavigationStack {
            stableMainContent
                .allowsHitTesting(!hasOverlay)
                .overlay {
                    if hasOverlay {
                        overlayViews
                            .background(Color(nsColor: .windowBackgroundColor))
                    }
                }
                .overlay { feedManagerOverlay }
                .overlay { imagePreviewOverlay }
                .toolbar { unifiedToolbarContent }
                .modifier(ToolbarBackgroundModifier())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .task {
                    feedStore.loadIfNeeded()
                    feedStore.configureAutoRefresh(enabled: settings.autoRefreshEnabled, intervalMinutes: settings.refreshIntervalMinutes)
                    Task { await ContentBlockerStore.shared.load() }
                }
                .onChange(of: settings.autoRefreshEnabled) { _, newValue in
                    feedStore.configureAutoRefresh(enabled: newValue, intervalMinutes: settings.refreshIntervalMinutes)
                }
                .onChange(of: settings.refreshIntervalMinutes) { _, newValue in
                    feedStore.configureAutoRefresh(enabled: settings.autoRefreshEnabled, intervalMinutes: newValue)
                }
                .onChange(of: feedStore.selectedArticleID) { _, newValue in
                    if newValue != nil && !showReaderPane {
                        withAnimation { showReaderPane = true }
                    }
                    // Stop any in-flight YouTube playback when the user jumps
                    // to a different article so audio doesn't bleed across.
                    NotificationCenter.default.post(name: .pauseAllYouTubePlayers, object: nil)
                }
                .onChange(of: isReaderExpanded) { _, _ in
                    // Fullscreen toggle creates a second YouTubeEmbedPlayer in the
                    // overlay; the underlying one is hidden but still playing audio.
                    // Pause both so the user controls playback explicitly.
                    NotificationCenter.default.post(name: .pauseAllYouTubePlayers, object: nil)
                }
                .onChange(of: feedStore.selectedSidebarItem) { _, _ in
                    // Mouse-clicking a sidebar row never updated `focusedPane`, so the
                    // stored focus would drift away from where the user thinks they are
                    // and right-arrow would silently no-op. Sync focus on any selection
                    // change — keyboard sidebar nav is already in `.sidebar`, so this is
                    // idempotent there.
                    focusedPane = .sidebar
                    // Cards / TV overlays render articles. Switching into a radio
                    // selection while one of those overlays is up would leave the user
                    // looking at stale article cards with no obvious way back, so
                    // collapse to the standard three-pane layout.
                    if isRadioSelected, showingNewspaper || showingTVView {
                        showingNewspaper = false
                        showingTVView = false
                    }
                }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFeedManager)) { _ in
            showingFeedManager = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshAllFeeds)) { _ in
            Task { await feedStore.refreshAll(force: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .previewReaderImage)) { notification in
            guard let url = notification.object as? URL else { return }
            previewImageURL = url
        }
        .onReceive(NotificationCenter.default.publisher(for: .increaseFontSize)) { _ in
            settings.typeScale = min(settings.typeScale + 0.1, 3.5)
        }
        .onReceive(NotificationCenter.default.publisher(for: .decreaseFontSize)) { _ in
            settings.typeScale = max(settings.typeScale - 0.1, 0.75)
        }
        .onReceive(NotificationCenter.default.publisher(for: .markAllAsRead)) { _ in
            requestMarkAllAsRead()
        }
        .confirmationDialog(
            markAllConfirmationTitle,
            isPresented: Binding(
                get: { pendingMarkAllScope != nil },
                set: { if !$0 { pendingMarkAllScope = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Mark as Read") {
                if let scope = pendingMarkAllScope {
                    feedStore.markAllAsRead(for: scope)
                }
                pendingMarkAllScope = nil
            }
            Button("Cancel", role: .cancel) {
                pendingMarkAllScope = nil
            }
        } message: {
            Text("This will mark every unread article in this view as read. You can't undo this.")
        }
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // Don't intercept when a text field or search field has focus
                if let responder = event.window?.firstResponder,
                   responder is NSTextView || responder is NSTextField {
                    return event
                }
                return handleKeyboardEvent(event) ? nil : event
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
    }
}

/// Three-column split view backed by `NSSplitView` directly so we can pin the sidebar's
/// width across every relayout. SwiftUI's `HSplitView` re-runs proportional redistribution
/// whenever its inner subviews re-render (which happens on every `feedStore` change), and
/// the sidebar would creep wider on every story or category click. Using a custom
/// `NSSplitViewDelegate` we hold the sidebar's exact pixel width and let only the
/// article-list / reader columns absorb size changes.
private struct MainPanesView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var settings: SettingsStore
    @Binding var showReaderPane: Bool
    @Binding var isReaderExpanded: Bool

    var body: some View {
        PinnedSidebarSplitView(detailVisible: $showReaderPane) {
            FeedListView()
                .environmentObject(feedStore)
                .environmentObject(settings)
        } content: {
            ContentListView()
                .environmentObject(feedStore)
                .environmentObject(settings)
        } detail: {
            ReaderPaneView(
                showReaderPane: $showReaderPane,
                isExpanded: $isReaderExpanded
            )
            .environmentObject(feedStore)
            .environmentObject(settings)
        }
        .frame(minWidth: showReaderPane ? 1180 : 720, minHeight: 680)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Column-width constants for `PinnedSidebarSplitView`. Lifted out of the generic
/// `Coordinator` class because Swift does not allow static stored properties on nested
/// types of generic types.
private enum SplitViewMetrics {
    static let minSidebarWidth: CGFloat = 240
    static let maxSidebarWidth: CGFloat = 500
    static let defaultSidebarWidth: CGFloat = 420
    static let minContentWidth: CGFloat = 340
    static let defaultContentWidth: CGFloat = 480
    static let minDetailWidth: CGFloat = 460
}

/// NSViewRepresentable wrapping `NSSplitView` with custom delegate logic that pins the
/// sidebar to its current pixel width. The middle and trailing columns absorb all
/// resizing — both window resizes and the detail pane appearing/disappearing.
///
/// Why not SwiftUI's `HSplitView`? When any subview re-renders (which SwiftUI does
/// constantly via @Published observation), HSplitView invalidates its layout and
/// redistributes proportionally, walking the sidebar's width away from the user's
/// dragged position. `NSSplitView` with a delegate that overrides
/// `splitView(_:resizeSubviewsWithOldSize:)` keeps the sidebar fixed.
private struct PinnedSidebarSplitView<Sidebar: View, Content: View, Detail: View>: NSViewRepresentable {
    @Binding var detailVisible: Bool
    let sidebar: Sidebar
    let content: Content
    let detail: Detail

    init(
        detailVisible: Binding<Bool>,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content,
        @ViewBuilder detail: () -> Detail
    ) {
        self._detailVisible = detailVisible
        self.sidebar = sidebar()
        self.content = content()
        self.detail = detail()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = context.coordinator
        splitView.translatesAutoresizingMaskIntoConstraints = true
        splitView.autoresizesSubviews = false

        let sidebarHost = NSHostingView(rootView: AnyView(sidebar))
        let contentHost = NSHostingView(rootView: AnyView(content))
        let detailHost = NSHostingView(rootView: AnyView(detail))
        context.coordinator.sidebarHost = sidebarHost
        context.coordinator.contentHost = contentHost
        context.coordinator.detailHost = detailHost

        splitView.addArrangedSubview(sidebarHost)
        splitView.addArrangedSubview(contentHost)
        if detailVisible {
            splitView.addArrangedSubview(detailHost)
        }

        // Seed initial divider positions on the next layout pass.
        DispatchQueue.main.async {
            let totalWidth = splitView.bounds.width
            guard totalWidth > 0 else { return }
            splitView.setPosition(SplitViewMetrics.defaultSidebarWidth, ofDividerAt: 0)
            if splitView.arrangedSubviews.count >= 3 {
                let contentTrailing = SplitViewMetrics.defaultSidebarWidth + SplitViewMetrics.defaultContentWidth
                splitView.setPosition(contentTrailing, ofDividerAt: 1)
            }
        }

        return splitView
    }

    func updateNSView(_ nsView: NSSplitView, context: Context) {
        // Propagate SwiftUI re-renders into each NSHostingView. These rootView
        // assignments do not trigger NSSplitView layout invalidation, so the sidebar
        // width survives every selection / refresh tick.
        context.coordinator.sidebarHost?.rootView = AnyView(sidebar)
        context.coordinator.contentHost?.rootView = AnyView(content)
        context.coordinator.detailHost?.rootView = AnyView(detail)

        // Add or remove the detail column without disturbing the sidebar's width.
        let hasDetail = nsView.arrangedSubviews.count == 3
        if detailVisible && !hasDetail, let detailHost = context.coordinator.detailHost {
            // Flag a one-shot restoration so the upcoming layout pass uses the user's
            // last detail-column width instead of the proportional fallback.
            context.coordinator.shouldRestoreDetailWidth = context.coordinator.rememberedDetailWidth != nil
            nsView.addArrangedSubview(detailHost)
        } else if !detailVisible && hasDetail {
            if let detailView = nsView.arrangedSubviews.last {
                context.coordinator.rememberedDetailWidth = detailView.frame.width
                detailView.removeFromSuperview()
            }
        }
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        var sidebarHost: NSHostingView<AnyView>?
        var contentHost: NSHostingView<AnyView>?
        var detailHost: NSHostingView<AnyView>?
        /// Last detail-column width before the user closed the reader pane. Restored
        /// on the next reopen so the column doesn't snap back to a default size.
        var rememberedDetailWidth: CGFloat?
        /// Set to true for the single resize pass that follows re-adding the detail
        /// column; tells the layout to apply `rememberedDetailWidth` instead of the
        /// proportional content/detail redistribution.
        var shouldRestoreDetailWidth = false

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMin: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            switch dividerIndex {
            case 0:
                return SplitViewMetrics.minSidebarWidth
            case 1:
                let sidebarTrailing = splitView.arrangedSubviews.first?.frame.maxX ?? SplitViewMetrics.minSidebarWidth
                return sidebarTrailing + SplitViewMetrics.minContentWidth
            default:
                return proposedMin
            }
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMax: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            switch dividerIndex {
            case 0:
                return min(SplitViewMetrics.maxSidebarWidth, proposedMax)
            case 1:
                // Reserve at least minDetailWidth for the detail column.
                return proposedMax - SplitViewMetrics.minDetailWidth
            default:
                return proposedMax
            }
        }

        /// Hand-roll subview resizing so the sidebar holds its current pixel width and
        /// only the article list / reader absorb the change. NSSplitView's default
        /// implementation redistributes proportionally to all subviews' ranges, which is
        /// what made the sidebar grow on every inner state change.
        func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
            let subviews = splitView.arrangedSubviews
            guard !subviews.isEmpty else { return }

            let totalWidth = splitView.bounds.width
            let totalHeight = splitView.bounds.height
            let dividerThickness = splitView.dividerThickness

            // Sidebar holds its current width, clamped to the allowed range.
            var sidebarWidth = subviews[0].frame.width
            if sidebarWidth <= 0 { sidebarWidth = SplitViewMetrics.defaultSidebarWidth }
            sidebarWidth = max(SplitViewMetrics.minSidebarWidth, min(SplitViewMetrics.maxSidebarWidth, sidebarWidth))

            // Don't let the sidebar squeeze the trailing columns below their minimums.
            let trailingCount = subviews.count - 1
            let trailingMin: CGFloat
            switch trailingCount {
            case 1: trailingMin = SplitViewMetrics.minContentWidth
            case 2: trailingMin = SplitViewMetrics.minContentWidth + SplitViewMetrics.minDetailWidth + dividerThickness
            default: trailingMin = 0
            }
            let maxAllowedSidebar = totalWidth - trailingMin - dividerThickness * CGFloat(trailingCount)
            if sidebarWidth > maxAllowedSidebar {
                sidebarWidth = max(SplitViewMetrics.minSidebarWidth, maxAllowedSidebar)
            }

            subviews[0].frame = NSRect(x: 0, y: 0, width: sidebarWidth, height: totalHeight)

            if subviews.count == 2 {
                let contentX = sidebarWidth + dividerThickness
                let contentWidth = max(SplitViewMetrics.minContentWidth, totalWidth - contentX)
                subviews[1].frame = NSRect(x: contentX, y: 0, width: contentWidth, height: totalHeight)
                return
            }

            if subviews.count == 3 {
                let availableWidth = totalWidth - sidebarWidth - dividerThickness * 2

                var contentWidth: CGFloat
                var detailWidth: CGFloat

                if shouldRestoreDetailWidth, let remembered = rememberedDetailWidth {
                    // The reader pane was just reopened — restore the user's last
                    // detail width and give whatever's left to the content column,
                    // clamped to the per-column minimums.
                    detailWidth = remembered
                    detailWidth = min(detailWidth, availableWidth - SplitViewMetrics.minContentWidth)
                    detailWidth = max(SplitViewMetrics.minDetailWidth, detailWidth)
                    contentWidth = availableWidth - detailWidth
                    shouldRestoreDetailWidth = false
                } else {
                    let oldContentWidth = subviews[1].frame.width
                    let oldDetailWidth = subviews[2].frame.width
                    let oldTrailingTotal = oldContentWidth + oldDetailWidth
                    if oldTrailingTotal > 1 {
                        let contentRatio = oldContentWidth / oldTrailingTotal
                        contentWidth = availableWidth * contentRatio
                        detailWidth = availableWidth - contentWidth
                    } else {
                        contentWidth = SplitViewMetrics.defaultContentWidth
                        detailWidth = availableWidth - contentWidth
                    }

                    if contentWidth < SplitViewMetrics.minContentWidth {
                        contentWidth = SplitViewMetrics.minContentWidth
                        detailWidth = availableWidth - contentWidth
                    }
                    if detailWidth < SplitViewMetrics.minDetailWidth {
                        detailWidth = SplitViewMetrics.minDetailWidth
                        contentWidth = availableWidth - detailWidth
                    }
                }

                let contentX = sidebarWidth + dividerThickness
                let detailX = contentX + contentWidth + dividerThickness
                subviews[1].frame = NSRect(x: contentX, y: 0, width: contentWidth, height: totalHeight)
                subviews[2].frame = NSRect(x: detailX, y: 0, width: detailWidth, height: totalHeight)
            }
        }
    }
}

private struct FullWindowImagePreview: View {
    let url: URL
    let onClose: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let horizontalInset = min(max(proxy.size.width * 0.03, 24), 56)
            let verticalInset = min(max(proxy.size.height * 0.035, 24), 48)
            let imageWidth = max(160, proxy.size.width - horizontalInset * 2)
            let imageHeight = max(160, proxy.size.height - verticalInset * 2)

            ZStack {
                Color.black.opacity(0.96)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)

                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: imageWidth, maxHeight: imageHeight)
                            .contentShape(Rectangle())
                            .onTapGesture { }
                    case .failure:
                        VStack(spacing: 10) {
                            Image(systemName: "photo")
                                .font(.system(size: 40, weight: .regular))
                            Text("Failed to load image")
                                .font(.headline)
                        }
                        .foregroundStyle(.white.opacity(0.72))
                    case .empty:
                        ProgressView()
                            .tint(.white)
                            .controlSize(.large)
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)

                VStack {
                    HStack {
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 30, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.escape, modifiers: [])
                        .padding(.top, 18)
                        .padding(.trailing, 20)
                    }
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.96))
    }
}

private struct ToolbarBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .toolbarBackground(Color(nsColor: .windowBackgroundColor), for: .windowToolbar)
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        } else {
            content
        }
    }
}

private struct ReaderPaneView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @Binding var showReaderPane: Bool
    @Binding var isExpanded: Bool

    var body: some View {
        ContentReaderView(
            onExpand: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded = true
                }
            },
            onClose: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showReaderPane = false
                }
            }
        )
    }
}


// MARK: - Weather Widget for Main View

private struct MainWeatherWidget: View {
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var weather = SharedWeatherService.shared
    @State private var showingPopover = false

    var body: some View {
        Group {
            if settings.weatherEnabled && hasLocation {
                Button {
                    showingPopover.toggle()
                } label: {
                    HStack(spacing: 4) {
                        if let data = weather.current {
                            Image(systemName: data.icon)
                                .font(.system(size: 12))
                                .foregroundStyle(data.iconColor)
                            Text("\(data.temperature)°")
                                .font(.system(size: 12, weight: .medium))
                            Text(data.city)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else if weather.isLoading {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                }
                .buttonStyle(.borderless)
                .help(weather.current.map { data in
                    let tempSym = data.units.temperatureSymbol
                    let wind = data.units.windSpeedLabel
                    return "\(data.description) in \(data.city)\n\(data.temperature)\(tempSym) • Feels like \(data.feelsLike)\(tempSym)\nWind: \(data.windSpeed) \(wind)"
                } ?? "Weather")
                .popover(isPresented: $showingPopover) {
                    WeatherPopover(data: weather.current, city: displayCity)
                }
                .task {
                    weather.configure(
                        city: displayCity,
                        lat: settings.weatherLatitude,
                        lon: settings.weatherLongitude,
                        units: settings.weatherUnits
                    )
                    weather.fetchIfNeeded()
                }
                .onChange(of: settings.weatherLatitude) { _, _ in
                    weather.configure(
                        city: displayCity,
                        lat: settings.weatherLatitude,
                        lon: settings.weatherLongitude,
                        units: settings.weatherUnits
                    )
                    weather.forceRefresh()
                }
                .onChange(of: settings.weatherUnits) { _, _ in
                    weather.configure(
                        city: displayCity,
                        lat: settings.weatherLatitude,
                        lon: settings.weatherLongitude,
                        units: settings.weatherUnits
                    )
                    weather.forceRefresh()
                }
            }
        }
    }

    private var hasLocation: Bool {
        settings.weatherLatitude != 0 && settings.weatherLongitude != 0
    }

    private var displayCity: String {
        let full = settings.weatherCity
        if let comma = full.firstIndex(of: ",") {
            return String(full[..<comma])
        }
        return full.isEmpty ? "" : full
    }
}

// MARK: - Weather Popover

private struct WeatherPopover: View {
    let data: SharedWeatherService.WeatherData?
    let city: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let data = data {
                let tempSym = data.units.temperatureSymbol
                // Header
                HStack {
                    Image(systemName: data.icon)
                        .font(.system(size: 32))
                        .foregroundStyle(data.iconColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(data.temperature)\(tempSym)")
                            .font(.system(size: 28, weight: .medium, design: .rounded))
                        Text(data.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Divider()

                // Location
                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(.blue)
                    Text(city)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }

                // Details grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    WeatherDetailRow(icon: "thermometer.medium", label: "Feels Like", value: "\(data.feelsLike)\(tempSym)")
                    WeatherDetailRow(icon: "wind", label: "Wind", value: "\(data.windSpeed) \(data.units.windSpeedLabel)")
                    WeatherDetailRow(icon: "humidity.fill", label: "Humidity", value: "\(data.humidity)%")
                    WeatherDetailRow(icon: "arrow.up.arrow.down", label: "High/Low", value: "\(data.high)\(tempSym) / \(data.low)\(tempSym)")
                }

                // Updated time
                Text("Updated \(data.updatedAt, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("Loading weather...")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}

private struct WeatherDetailRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
        }
    }
}

// MARK: - Refresh Progress Chip

/// Small toolbar chip shown while a multi-feed refresh is in flight. Replaces the bare
/// spinner with concrete progress ("423 / 1,104") so users with many feeds can see how
/// far along they are. Backed by `FeedStore.refreshCompletedCount` /
/// `refreshTotalCount`, both of which are throttled (~5/sec) by the refresh batcher.
private struct RefreshProgressChip: View {
    let completed: Int
    let total: Int

    var body: some View {
        HStack(spacing: 5) {
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.85)
                .frame(width: 12, height: 12)
            if total > 0 {
                Text(progressLabel)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
        .fixedSize(horizontal: true, vertical: false)
        .help(tooltipLabel)
    }

    /// Compact form ("72/1104") so the chip stays narrow enough to coexist with the
    /// rest of the leading toolbar without forcing macOS to truncate it. Full count
    /// with comma-formatted thousands separator lives in the hover tooltip.
    private var progressLabel: String { "\(completed)/\(total)" }

    private var tooltipLabel: String {
        if total == 0 { return "Refreshing\u{2026}" }
        let percent = Int((Double(completed) / Double(total)) * 100)
        return "Refreshing \(completed.formatted(.number)) of \(total.formatted(.number)) feeds (\(percent)%)"
    }
}

// MARK: - Header Bar Button

private struct HeaderBarButton: View {
    let icon: String?
    let label: String
    var isActive: Bool = false
    var showProgress: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if showProgress {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .frame(width: 28, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive ? Color.accentColor.opacity(0.15) : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(isActive ? Color.accentColor : .secondary)
        .help(label)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Header Search Field

private struct HeaderSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .frame(width: 180)
    }
}

// MARK: - Overlay Close Button (for Cards/TV views, replacing toolbar close buttons)

private struct OverlayCloseButton: View {
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.borderless)
        .onHover { isHovered = $0 }
        .padding(.leading, 12)
        .padding(.top, 8)
    }
}

// MARK: - Shared Weather Service

@MainActor
final class SharedWeatherService: ObservableObject {
    static let shared = SharedWeatherService()

    @Published var current: WeatherData?
    @Published var isLoading = false

    private var lastFetch: Date?
    private let cacheMinutes: TimeInterval = 30

    private var configuredCity = ""
    private var configuredLat: Double = 0
    private var configuredLon: Double = 0
    private var configuredUnits: WeatherUnits = .fahrenheit

    struct WeatherData {
        let temperature: Int
        let feelsLike: Int
        let humidity: Int
        let windSpeed: Int
        let high: Int
        let low: Int
        let weatherCode: Int
        let isDay: Bool
        let city: String
        let updatedAt: Date
        /// Units this data was fetched in — drives display symbols (°F vs °C, mph vs km/h).
        let units: WeatherUnits

        var icon: String {
            switch weatherCode {
            case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
            case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
            case 3: return "cloud.fill"
            case 45, 48: return "cloud.fog.fill"
            case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
            case 61, 63, 65, 66, 67: return "cloud.rain.fill"
            case 71, 73, 75, 77: return "cloud.snow.fill"
            case 80, 81, 82: return "cloud.heavyrain.fill"
            case 85, 86: return "cloud.snow.fill"
            case 95, 96, 99: return "cloud.bolt.rain.fill"
            default: return "cloud.fill"
            }
        }

        var iconColor: Color {
            switch weatherCode {
            case 0: return isDay ? .yellow : .indigo
            case 1, 2: return isDay ? .orange : .purple
            case 61...67, 80...82: return .blue
            case 71...77, 85, 86: return .cyan
            case 95, 96, 99: return .purple
            default: return .gray
            }
        }

        var description: String {
            switch weatherCode {
            case 0: return "Clear sky"
            case 1: return "Mainly clear"
            case 2: return "Partly cloudy"
            case 3: return "Overcast"
            case 45, 48: return "Foggy"
            case 51, 53, 55: return "Drizzle"
            case 56, 57: return "Freezing drizzle"
            case 61, 63, 65: return "Rain"
            case 66, 67: return "Freezing rain"
            case 71, 73, 75: return "Snow"
            case 77: return "Snow grains"
            case 80, 81, 82: return "Rain showers"
            case 85, 86: return "Snow showers"
            case 95: return "Thunderstorm"
            case 96, 99: return "Thunderstorm with hail"
            default: return "Unknown"
            }
        }
    }

    private init() {}

    func configure(city: String, lat: Double, lon: Double, units: WeatherUnits) {
        let unitsChanged = units != configuredUnits
        configuredCity = city
        configuredLat = lat
        configuredLon = lon
        configuredUnits = units
        if unitsChanged {
            // Invalidate cache so the next fetch hits the API with the new unit params.
            lastFetch = nil
            current = nil
        }
    }

    func forceRefresh() {
        lastFetch = nil
        current = nil
        fetchIfNeeded()
    }

    func fetchIfNeeded() {
        if let last = lastFetch, Date().timeIntervalSince(last) < cacheMinutes * 60 {
            return
        }
        guard configuredLat != 0 && configuredLon != 0 else { return }
        guard !isLoading else { return }
        isLoading = true

        Task {
            await fetchWeather()
        }
    }

    private func fetchWeather() async {
        let lat = configuredLat
        let lon = configuredLon
        let city = configuredCity
        let units = configuredUnits

        // Fetch current weather + daily high/low + hourly for humidity/feels like
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current_weather=true&temperature_unit=\(units.openMeteoTemperatureParameter)&windspeed_unit=\(units.openMeteoWindspeedParameter)&daily=temperature_2m_max,temperature_2m_min&hourly=relativehumidity_2m,apparent_temperature&timezone=auto&forecast_days=1"

        guard let url = URL(string: urlString) else {
            await MainActor.run { isLoading = false }
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let currentWeather = json["current_weather"] as? [String: Any],
               let temp = currentWeather["temperature"] as? Double,
               let code = currentWeather["weathercode"] as? Int,
               let isDay = currentWeather["is_day"] as? Int,
               let windSpeed = currentWeather["windspeed"] as? Double {

                // Get daily high/low
                var high = Int(temp.rounded())
                var low = Int(temp.rounded())
                if let daily = json["daily"] as? [String: Any],
                   let maxTemps = daily["temperature_2m_max"] as? [Double],
                   let minTemps = daily["temperature_2m_min"] as? [Double],
                   let maxTemp = maxTemps.first,
                   let minTemp = minTemps.first {
                    high = Int(maxTemp.rounded())
                    low = Int(minTemp.rounded())
                }

                // Get current hour's humidity and feels like
                var humidityVal = 50
                var feelsLikeVal = Int(temp.rounded())
                if let hourly = json["hourly"] as? [String: Any],
                   let humidities = hourly["relativehumidity_2m"] as? [Int],
                   let feelsLikes = hourly["apparent_temperature"] as? [Double] {
                    // Get current hour (index based on current time)
                    let hour = Calendar.current.component(.hour, from: Date())
                    if hour < humidities.count {
                        humidityVal = humidities[hour]
                    }
                    if hour < feelsLikes.count {
                        feelsLikeVal = Int(feelsLikes[hour].rounded())
                    }
                }

                // Capture final values for sendable closure
                let finalHigh = high
                let finalLow = low
                let finalHumidity = humidityVal
                let finalFeelsLike = feelsLikeVal

                await MainActor.run {
                    self.current = WeatherData(
                        temperature: Int(temp.rounded()),
                        feelsLike: finalFeelsLike,
                        humidity: finalHumidity,
                        windSpeed: Int(windSpeed.rounded()),
                        high: finalHigh,
                        low: finalLow,
                        weatherCode: code,
                        isDay: isDay == 1,
                        city: city,
                        updatedAt: Date(),
                        units: units
                    )
                    self.lastFetch = Date()
                    self.isLoading = false
                }
            } else {
                await MainActor.run { isLoading = false }
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }
}
