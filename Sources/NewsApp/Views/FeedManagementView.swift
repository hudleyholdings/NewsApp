import SwiftUI
import UniformTypeIdentifiers

struct FeedManagementView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @Binding var isPresented: Bool
    @State private var selectedTab: ManagementTab = .addSource
    @State private var editingList: UserList?

    private enum ManagementTab: String, CaseIterable {
        case addSource = "Add Source"
        case feeds = "Feeds"
        case lists = "Lists"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Manage Sources")
                    .font(.title2.bold())
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Tab Picker
            Picker("", selection: $selectedTab) {
                ForEach(ManagementTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            Divider()

            // Content
            Group {
                switch selectedTab {
                case .addSource:
                    AddSourceView()
                case .feeds:
                    FeedsListView()
                case .lists:
                    ListsManagementView(editingList: $editingList)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 600, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $editingList) { list in
            ListEditorView(list: list)
        }
    }
}

// MARK: - Source Type Enum

private enum SourceType: String, CaseIterable {
    case rss = "RSS / Website"
    case gdelt = "GDELT News"
    case polymarket = "Polymarket"
}

// MARK: - Add Source View

private struct AddSourceView: View {
    @State private var sourceType: SourceType = .rss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sourceTypeSelector
                Divider()
                sourceForm
                Spacer(minLength: 20)
            }
            .padding(24)
        }
    }

    private var sourceTypeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Source Type")
                .font(.headline)

            HStack(spacing: 12) {
                ForEach(SourceType.allCases, id: \.self) { type in
                    SourceTypeButton(
                        type: type,
                        isSelected: sourceType == type,
                        action: { sourceType = type }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var sourceForm: some View {
        switch sourceType {
        case .rss:
            RSSSourceForm()
        case .gdelt:
            GDELTSourceForm()
        case .polymarket:
            PolymarketSourceForm()
        }
    }
}

private struct SourceTypeButton: View {
    let type: SourceType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 24))
                Text(type.rawValue)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch type {
        case .rss: return "dot.radiowaves.up.forward"
        case .gdelt: return "globe"
        case .polymarket: return "chart.pie"
        }
    }
}

// MARK: - RSS Source Form

private struct RSSSourceForm: View {
    @EnvironmentObject private var feedStore: FeedStore
    @State private var urlInput = ""
    @State private var category = ""
    @State private var isAdding = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add RSS Feed")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Feed or Website URL")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("https://example.com/feed.xml", text: $urlInput)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Category (optional)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("e.g. Tech, News, Sports", text: $category)
                        .textFieldStyle(.roundedBorder)
                    if !existingCategories.isEmpty {
                        Menu {
                            ForEach(existingCategories, id: \.self) { cat in
                                Button(cat) { category = cat }
                            }
                        } label: {
                            Text("Pick")
                        }
                    }
                }
            }

            HStack {
                Button {
                    addFeed()
                } label: {
                    HStack {
                        if isAdding {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isAdding ? "Adding..." : "Add Feed")
                    }
                    .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .disabled(urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAdding)

                if let status = statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(statusIsError ? .red : .green)
                }
            }
        }
    }

    private var existingCategories: [String] {
        Array(Set(feedStore.feeds.compactMap { $0.category })).sorted()
    }

    private func addFeed() {
        isAdding = true
        statusMessage = nil
        Task {
            let result = await feedStore.addFeed(
                from: urlInput.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category.isEmpty ? nil : category,
                listIDs: []
            )
            switch result {
            case .success(let feed):
                statusMessage = "Added: \(feed.name)"
                statusIsError = false
                urlInput = ""
            case .failure:
                statusMessage = "Could not add feed"
                statusIsError = true
            }
            isAdding = false
        }
    }
}

// MARK: - GDELT Source Form

private struct GDELTSourceForm: View {
    @EnvironmentObject private var feedStore: FeedStore
    @State private var query = ""
    @State private var topicIndex = 0
    @State private var languageIndex = 0
    @State private var timeWindowIndex = 2
    @State private var country = ""
    @State private var domain = ""
    @State private var displayName = ""
    @State private var category = ""
    @State private var isAdding = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var showAdvanced = false

    private var topicOptions: [GDELTTopic?] { [nil] + GDELTTopic.allCases.map { Optional($0) } }
    private let languageOptions = GDELTLanguage.allCases
    private let timeWindowOptions = GDELTTimeWindow.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add GDELT News Source")
                .font(.headline)

            Text("GDELT monitors news from around the world in real-time.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Topic")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("Topic", selection: $topicIndex) {
                        Text("Any Topic").tag(0)
                        ForEach(1..<topicOptions.count, id: \.self) { i in
                            if let topic = topicOptions[i] {
                                Text(topic.label).tag(i)
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Time Window")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("Time", selection: $timeWindowIndex) {
                        ForEach(0..<timeWindowOptions.count, id: \.self) { i in
                            Text(timeWindowOptions[i].label).tag(i)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Keyword Search (optional)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("e.g. climate change, election", text: $query)
                    .textFieldStyle(.roundedBorder)
            }

            DisclosureGroup("Advanced Options", isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Language")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Picker("Language", selection: $languageIndex) {
                                ForEach(0..<languageOptions.count, id: \.self) { i in
                                    Text(languageOptions[i].label).tag(i)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Country Code")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TextField("e.g. US, GB", text: $country)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Domain Filter")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("e.g. nytimes.com", text: $domain)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Display Name")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("Custom name for this source", text: $displayName)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Category")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("e.g. GDELT, World News", text: $category)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.top, 8)
            }

            HStack {
                Button {
                    addGDELT()
                } label: {
                    HStack {
                        if isAdding {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isAdding ? "Adding..." : "Add GDELT Source")
                    }
                    .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAdding)

                if let status = statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(statusIsError ? .red : .green)
                }
            }
        }
    }

    private func addGDELT() {
        isAdding = true
        statusMessage = nil
        let config = GDELTSourceConfig(
            query: query,
            topic: topicOptions[topicIndex],
            language: languageOptions[languageIndex],
            country: country.isEmpty ? nil : country.uppercased(),
            timeWindow: timeWindowOptions[timeWindowIndex],
            domain: domain.isEmpty ? nil : domain,
            maxRecords: 100
        )
        let result = feedStore.addGDELTSource(
            name: displayName.isEmpty ? nil : displayName,
            config: config,
            category: category.isEmpty ? "GDELT" : category,
            listIDs: []
        )
        switch result {
        case .success(let feed):
            statusMessage = "Added: \(feed.name)"
            statusIsError = false
            query = ""
            displayName = ""
            topicIndex = 0
        case .failure:
            statusMessage = "Could not add source"
            statusIsError = true
        }
        isAdding = false
    }
}

// MARK: - Polymarket Source Form

private struct PolymarketSourceForm: View {
    @EnvironmentObject private var feedStore: FeedStore
    @State private var categoryIndex = 0
    @State private var sortIndex = 0
    @State private var displayName = ""
    @State private var category = ""
    @State private var isAdding = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    private let categoryOptions = PolymarketCategory.allCases
    private let sortOptions = PolymarketSort.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Polymarket Predictions")
                .font(.headline)

            Text("Track prediction market odds and trends from Polymarket.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Legal disclaimer
            Text("For informational purposes only. Not financial or investment advice. Check local regulations before participating in prediction markets.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(8)
                .background(Color.yellow.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Category")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("Category", selection: $categoryIndex) {
                        ForEach(0..<categoryOptions.count, id: \.self) { i in
                            Text(categoryOptions[i].label).tag(i)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sort By")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("Sort", selection: $sortIndex) {
                        ForEach(0..<sortOptions.count, id: \.self) { i in
                            Text(sortOptions[i].label).tag(i)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Display Name (optional)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Custom name for this source", text: $displayName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Category (optional)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("e.g. Predictions, Markets", text: $category)
                    .textFieldStyle(.roundedBorder)
            }

            // Preview of what will be added
            GroupBox {
                HStack(spacing: 12) {
                    Image(systemName: "chart.pie")
                        .font(.title2)
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(previewName)
                            .font(.subheadline.weight(.medium))
                        Text("Prediction markets with real-time odds")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            HStack {
                Button {
                    addPolymarket()
                } label: {
                    HStack {
                        if isAdding {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isAdding ? "Adding..." : "Add Polymarket Source")
                    }
                    .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAdding)

                if let status = statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(statusIsError ? .red : .green)
                }
            }
        }
    }

    private var previewName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return "Polymarket: \(categoryOptions[categoryIndex].label) (\(sortOptions[sortIndex].label))"
    }

    private func addPolymarket() {
        isAdding = true
        statusMessage = nil
        let config = PolymarketSourceConfig(
            category: categoryOptions[categoryIndex],
            sort: sortOptions[sortIndex],
            maxRecords: 50,
            showResolved: false
        )
        let result = feedStore.addPolymarketSource(
            name: displayName.isEmpty ? nil : displayName,
            config: config,
            category: category.isEmpty ? "Predictions" : category,
            listIDs: []
        )
        switch result {
        case .success(let feed):
            statusMessage = "Added: \(feed.name)"
            statusIsError = false
            displayName = ""
            categoryIndex = 0
            sortIndex = 0
        case .failure:
            statusMessage = "Could not add source"
            statusIsError = true
        }
        isAdding = false
    }
}

// MARK: - Feeds List View

private struct FeedsListView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @State private var searchText = ""
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var importMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Search and actions
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search feeds", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Button("Import") { showImporter = true }
                Button("Export") { showExporter = true }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            if let msg = importMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 24)
            }

            Divider()

            // Feed list
            List {
                ForEach(filteredFeeds) { feed in
                    FeedManagementRow(feed: feed)
                }
                .onDelete { offsets in
                    let feedsToDelete = offsets.map { filteredFeeds[$0] }
                    for feed in feedsToDelete {
                        if let idx = feedStore.feeds.firstIndex(where: { $0.id == feed.id }) {
                            feedStore.removeFeeds(at: IndexSet([idx]))
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.xml, .init(filenameExtension: "opml")!]) { result in
            if case let .success(url) = result {
                let added = feedStore.importOPML(from: url)
                importMessage = "Imported \(added) feeds"
            }
        }
        .fileExporter(isPresented: $showExporter, document: OPMLDocument(feeds: feedStore.feeds), contentType: .xml, defaultFilename: "NewsAppFeeds.opml") { _ in }
    }

    private var filteredFeeds: [Feed] {
        guard !searchText.isEmpty else { return feedStore.feeds }
        return feedStore.feeds.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.feedURL.absoluteString.localizedCaseInsensitiveContains(searchText) ||
            ($0.category ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }
}

private struct FeedManagementRow: View {
    @EnvironmentObject private var feedStore: FeedStore
    let feed: Feed

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            sourceIcon
                .frame(width: 32, height: 32)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(feed.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(feed.sourceKind.rawValue.uppercased())
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(sourceColor.opacity(0.15))
                        .foregroundStyle(sourceColor)
                        .clipShape(Capsule())
                    if let category = feed.category {
                        Text(category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Enable toggle
            Toggle("", isOn: Binding(
                get: { feed.isEnabled },
                set: { _ in feedStore.toggleFeedEnabled(feed) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var sourceIcon: some View {
        switch feed.sourceKind {
        case .rss:
            Image(systemName: "dot.radiowaves.up.forward")
                .font(.system(size: 16))
                .frame(width: 32, height: 32)
                .background(Color.orange.opacity(0.15))
                .foregroundStyle(.orange)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        case .gdelt:
            Image(systemName: "globe")
                .font(.system(size: 16))
                .frame(width: 32, height: 32)
                .background(Color.blue.opacity(0.15))
                .foregroundStyle(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        case .polymarket:
            Image(systemName: "chart.pie")
                .font(.system(size: 16))
                .frame(width: 32, height: 32)
                .background(Color.purple.opacity(0.15))
                .foregroundStyle(.purple)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var sourceColor: Color {
        switch feed.sourceKind {
        case .rss: return .orange
        case .gdelt: return .blue
        case .polymarket: return .purple
        }
    }
}

// MARK: - Lists Management View

private struct ListsManagementView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @Binding var editingList: UserList?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("\(feedStore.lists.count) Lists")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    editingList = UserList(name: "New List")
                } label: {
                    Label("New List", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Divider()

            if feedStore.lists.isEmpty {
                ContentUnavailableView(
                    "No Lists",
                    systemImage: "folder",
                    description: Text("Create lists to organize your feeds.")
                )
            } else {
                List {
                    ForEach(feedStore.lists) { list in
                        ListManagementRow(list: list) {
                            editingList = list
                        }
                    }
                    .onDelete { offsets in
                        feedStore.removeLists(at: offsets)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

private struct ListManagementRow: View {
    let list: UserList
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ListIconView(name: list.name, iconSystemName: nil, iconURL: list.iconURL)

            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .font(.headline)
                Text(list.feedIDs.isEmpty ? "No feeds" : "\(list.feedIDs.count) feeds")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Edit", action: onEdit)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - List Editor View

struct ListEditorView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @Environment(\.dismiss) private var dismiss
    let list: UserList
    @State private var name: String
    @State private var iconURLText: String
    @State private var selectedFeedIDs: Set<UUID>
    @State private var feedSearchText = ""

    init(list: UserList) {
        self.list = list
        _name = State(initialValue: list.name)
        _iconURLText = State(initialValue: list.iconURL?.absoluteString ?? "")
        _selectedFeedIDs = State(initialValue: Set(list.feedIDs))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit List" : "New List")
                    .font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("List Name")
                            .font(.headline)
                        TextField("My List", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Icon
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Icon URL (optional)")
                            .font(.headline)
                        TextField("https://example.com/icon.png", text: $iconURLText)
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 12) {
                            Text("Preview:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ListIconView(name: name.isEmpty ? "List" : name, iconSystemName: nil, iconURL: resolvedIconURL)
                        }
                    }

                    Divider()

                    // Feeds
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Feeds in List")
                                .font(.headline)
                            Spacer()
                            Text("\(selectedFeedIDs.count) selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        TextField("Search feeds...", text: $feedSearchText)
                            .textFieldStyle(.roundedBorder)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(filteredFeeds) { feed in
                                    Toggle(isOn: Binding(
                                        get: { selectedFeedIDs.contains(feed.id) },
                                        set: { isOn in
                                            if isOn {
                                                selectedFeedIDs.insert(feed.id)
                                            } else {
                                                selectedFeedIDs.remove(feed.id)
                                            }
                                        }
                                    )) {
                                        HStack {
                                            Text(feed.name)
                                            if let category = feed.category {
                                                Text("(\(category))")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        .frame(height: 200)
                        .padding(8)
                        .background(Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 500, height: 520)
    }

    private var isEditing: Bool {
        feedStore.lists.contains(where: { $0.id == list.id })
    }

    private var resolvedIconURL: URL? {
        let trimmed = iconURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : URL(string: trimmed)
    }

    private var filteredFeeds: [Feed] {
        let query = feedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return feedStore.feeds }
        return feedStore.feeds.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            ($0.category ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let updated = UserList(
            id: list.id,
            name: trimmedName,
            iconSystemName: nil,
            iconURL: resolvedIconURL,
            feedIDs: Array(selectedFeedIDs)
        )
        if isEditing {
            feedStore.updateList(updated)
        } else {
            _ = feedStore.addList(name: updated.name, iconSystemName: nil, iconURL: updated.iconURL, feedIDs: updated.feedIDs)
        }
        dismiss()
    }
}

// MARK: - OPML Document

struct OPMLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.xml] }

    var feeds: [Feed]

    init(feeds: [Feed]) {
        self.feeds = feeds
    }

    init(configuration: ReadConfiguration) throws {
        self.feeds = []
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = OPMLService().export(feeds: feeds)
        return FileWrapper(regularFileWithContents: data)
    }
}
