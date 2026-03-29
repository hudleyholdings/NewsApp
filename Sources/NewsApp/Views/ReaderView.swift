import SwiftUI
import AppKit

struct ReaderView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var settings: SettingsStore
    let isExpanded: Bool
    let expandedMargin: CGFloat
    let onExpand: (() -> Void)?
    let onClose: (() -> Void)?
    @Binding var externalModeOverride: ReaderDisplayMode?
    @State private var internalModeOverride: ReaderDisplayMode?
    @State private var readerFallbackNotice: String?
    @State private var lastFallbackArticleID: UUID?
    @State private var scrollProgress: Double = 0
    @State private var isHeaderCompact = false

    private var displayModeOverride: ReaderDisplayMode? {
        get { isExpanded ? externalModeOverride : internalModeOverride }
    }

    init(
        isExpanded: Bool = false,
        expandedMargin: CGFloat = 0,
        onExpand: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        modeOverride: Binding<ReaderDisplayMode?>? = nil
    ) {
        self.isExpanded = isExpanded
        self.expandedMargin = expandedMargin
        self.onExpand = onExpand
        self.onClose = onClose
        self._externalModeOverride = modeOverride ?? .constant(nil)
    }

    var body: some View {
        if let article = feedStore.article(for: feedStore.selectedArticleID) {
            let currentDisplayMode = effectiveDisplayMode(for: article)
            let source = feedStore.feedName(for: article.feedID) ?? article.link?.host
            let copyPayload = copyText(for: article, source: source)
            VStack(spacing: 0) {
                ReaderHeader(
                    article: article,
                    source: source,
                    link: article.link,
                    copyText: copyPayload,
                    displayMode: currentDisplayMode,
                    maxWidth: contentMaxWidth,
                    isCompact: isHeaderCompact,
                    isExpanded: isExpanded,
                    horizontalMargin: expandedMargin,
                    onExpand: onExpand,
                    onClose: onClose,
                    modeOverride: modeBinding
                )
                if let notice = readerFallbackNotice {
                    ReaderNoticeBanner(message: notice, buttonTitle: "Open Web") {
                        setModeOverride(.web)
                    }
                }
                if currentDisplayMode == .web, !settings.persistentWebSessions {
                    ReaderNoticeBanner(message: "Private Web Mode: Keychain access is disabled until you enable persistent sessions.", buttonTitle: "Enable") {
                        settings.persistentWebSessions = true
                    }
                }
                Divider()
                ZStack {
                    if currentDisplayMode == .reader {
                        if article.isPolymarketArticle {
                            // Custom Polymarket reader view
                            PolymarketReaderView(article: article)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        } else {
                            ZStack(alignment: .trailing) {
                                ReaderTextView(
                                    article: article,
                                    maxWidth: contentMaxWidth,
                                    isExpanded: isExpanded,
                                    horizontalMargin: expandedMargin,
                                    progress: $scrollProgress,
                                    onScroll: { offset in
                                        updateHeaderCompact(forOffset: offset)
                                    }
                                )
                                ReaderProgressIndicator(progress: scrollProgress)
                                    .padding(.trailing, 6)
                            }
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    } else {
                        WebView(
                            url: article.link,
                            blockAds: settings.blockAdsEnabled,
                            userAgent: webUserAgent,
                            persistentSession: settings.persistentWebSessions,
                            onScroll: { offset in
                                updateHeaderCompact(forOffset: offset)
                            }
                        )
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: currentDisplayMode)
            }
            .task(id: article.id) {
                if settings.markReadOnOpen {
                    feedStore.markRead(article)
                }
                if currentDisplayMode == .reader {
                    await feedStore.ensureContent(for: article.id)
                }
                evaluateReaderFallback(for: article)
            }
            .onChange(of: article.id) { _, _ in
                setModeOverride(nil)
                readerFallbackNotice = nil
                scrollProgress = feedStore.readingProgress(for: article.id)
                isHeaderCompact = false
            }
            .onChange(of: displayMode) { _, newValue in
                if newValue == .reader, article.forceWebView != true {
                    Task { await feedStore.ensureContent(for: article.id) }
                }
            }
            .onChange(of: article.contentText) { _, _ in
                evaluateReaderFallback(for: article)
            }
            .onChange(of: scrollProgress) { _, newValue in
                feedStore.updateReadingProgress(for: article.id, progress: newValue)
                if effectiveDisplayMode(for: article) == .reader {
                    updateHeaderCompact(forProgress: newValue)
                }
            }
            .onAppear {
                scrollProgress = feedStore.readingProgress(for: article.id)
            }
        } else {
            ContentUnavailableView("Select an Article", systemImage: "doc.text.magnifyingglass", description: Text("Choose a story to begin reading."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var displayMode: ReaderDisplayMode {
        displayModeOverride ?? settings.defaultReaderMode
    }

    private var contentMaxWidth: CGFloat? {
        // Always fill available width - no max constraint
        nil
    }

    private var modeBinding: Binding<ReaderDisplayMode?> {
        Binding(
            get: { displayModeOverride },
            set: { newValue in
                if isExpanded {
                    externalModeOverride = newValue
                } else {
                    internalModeOverride = newValue
                }
            }
        )
    }

    private func setModeOverride(_ mode: ReaderDisplayMode?) {
        if isExpanded {
            externalModeOverride = mode
        } else {
            internalModeOverride = mode
        }
    }

    private var webUserAgent: String {
        if settings.preferMobileSite {
            return "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        }
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    }

    private func effectiveDisplayMode(for article: Article) -> ReaderDisplayMode {
        if article.forceWebView == true {
            return .web
        }
        return displayMode
    }

    private func updateHeaderCompact(forProgress scrollValue: Double) {
        let shouldCompact = scrollValue > 0.0
        if shouldCompact != isHeaderCompact {
            withAnimation(.easeInOut(duration: 0.18)) {
                isHeaderCompact = shouldCompact
            }
        }
    }

    private func updateHeaderCompact(forOffset scrollOffset: CGFloat) {
        let shouldCompact = scrollOffset > 10
        if shouldCompact != isHeaderCompact {
            withAnimation(.easeInOut(duration: 0.18)) {
                isHeaderCompact = shouldCompact
            }
        }
    }

    private func evaluateReaderFallback(for article: Article) {
        guard let text = article.contentText, !text.isEmpty else { return }
        let fallbackDetected = ReaderFallbackDetector.shouldFallback(text: text)
        if fallbackDetected {
            let notice = "Reader mode blocked by publisher. Switched to Web view."
            if lastFallbackArticleID != article.id {
                lastFallbackArticleID = article.id
                readerFallbackNotice = notice
                setModeOverride(.web)
            } else {
                readerFallbackNotice = notice
            }
        } else {
            readerFallbackNotice = nil
        }
    }

    private func copyText(for article: Article, source: String?) -> String {
        var lines: [String] = []
        lines.append(article.title)
        if let source = source { lines.append(source) }
        let date = article.publishedAt ?? article.addedAt
        lines.append(ReaderView.copyDateFormatter.string(from: date))
        if let body = article.contentText ?? article.summary {
            lines.append(body)
        }
        if let link = article.link?.absoluteString {
            lines.append(link)
        }
        return lines.joined(separator: "\n\n")
    }

    private static let copyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private enum ReaderFallbackDetector {
    private static let phrases = [
        "disable ad blocker",
        "disable any ad blocker",
        "turn off your ad blocker",
        "please enable javascript",
        "enable javascript",
        "enable js",
        "please enable js",
        "subscribe to continue",
        "sign in to continue",
        "access denied",
        "not authorized"
    ]

    static func shouldFallback(text: String) -> Bool {
        let lower = text.lowercased()
        let isShort = lower.count < 800
        let hasPhrase = phrases.contains { lower.contains($0) }
        return isShort && hasPhrase
    }
}

private struct ReaderNoticeBanner: View {
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
            Spacer()
            Button(buttonTitle) { action() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.18))
    }
}

private struct ReaderProgressIndicator: View {
    let progress: Double

    var body: some View {
        if progress > 0.02 {
            GeometryReader { proxy in
                let clamped = min(max(progress, 0), 1)
                let yOffset = (proxy.size.height - 18) * CGFloat(clamped)
                ZStack(alignment: .top) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 2)
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .offset(y: yOffset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
            .frame(width: 12)
            .padding(.vertical, 12)
            .allowsHitTesting(false)
        }
    }
}

struct ReaderHeader: View {
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var settings: SettingsStore
    let article: Article
    let source: String?
    let link: URL?
    let copyText: String
    let displayMode: ReaderDisplayMode
    let maxWidth: CGFloat?
    let isCompact: Bool
    let isExpanded: Bool
    let horizontalMargin: CGFloat
    let onExpand: (() -> Void)?
    let onClose: (() -> Void)?
    @Binding var modeOverride: ReaderDisplayMode?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: isCompact ? 4 : 6) {
                headerTopRow

                Text(article.title)
                    .font(settings.readerFont(size: isCompact ? settings.readerFontSize + 1 : settings.readerFontSize + 6, weight: .bold))
                    .lineLimit(isCompact ? 1 : 3)

                HStack(spacing: 6) {
                    if isExpanded, let source = source, !source.isEmpty {
                        Text(source)
                            .fontWeight(.medium)
                        Text("•")
                    }
                    if !isCompact, let author = article.author, !author.isEmpty {
                        Text(author)
                            .fontWeight(.medium)
                        Text("•")
                    }
                    Text(relativeTime)
                    if !isCompact, let readingTime = readingTime {
                        Text("•")
                        Text(readingTime)
                    }
                }
                .font(settings.readerFont(size: max(11, settings.readerFontSize - (isCompact ? 6 : 5)), weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if !isCompact {
                    HStack(spacing: 10) {
                        Button {
                            feedStore.toggleStar(article)
                        } label: {
                            Label(article.isStarred ? "Saved" : "Save", systemImage: article.isStarred ? "bookmark.fill" : "bookmark")
                        }
                        .buttonStyle(.borderless)

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(copyText, forType: .string)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)

                        if let link = link {
                            Button {
                                NSWorkspace.shared.open(link)
                            } label: {
                                Label("Open in Browser", systemImage: "arrow.up.right.square")
                            }
                            .buttonStyle(.borderless)
                        }

                        if let link = link {
                            ShareLink(item: link) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderless)
                        }

                        Spacer()
                    }
                    .font(settings.readerFont(size: max(11, settings.readerFontSize - 4), weight: .medium))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: isExpanded ? 900 : (maxWidth ?? .infinity), alignment: .leading)
            .padding(.horizontal, isExpanded ? max(20, horizontalMargin) : 20)
            .padding(.top, isCompact ? 8 : 12)
            .padding(.bottom, isCompact ? 6 : 10)
            .animation(.easeInOut(duration: 0.2), value: isCompact)
        }
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
    }

    @ViewBuilder
    private var headerTopRow: some View {
        // In expanded mode, source badge and picker are handled elsewhere
        if isExpanded {
            EmptyView()
        } else {
            HStack(alignment: .center) {
                if let source = source, !source.isEmpty {
                    Text(source.uppercased())
                        .font(.system(size: settings.scaled(10), weight: .semibold, design: .rounded))
                        .tracking(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                Spacer()

                Picker("", selection: Binding(
                    get: { displayMode },
                    set: { modeOverride = $0 }
                )) {
                    ForEach(ReaderDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 120)

                if let onExpand {
                    Button {
                        onExpand()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Expand to full width")
                }

                if let onClose {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Hide reader pane")
                }
            }
        }
    }

    private var relativeTime: String {
        let date = article.publishedAt ?? article.addedAt
        return ReaderHeader.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private var publishedLine: String {
        let date = article.publishedAt ?? article.addedAt
        let absolute = ReaderHeader.absoluteFormatter.string(from: date)
        let relative = ReaderHeader.relativeFormatter.localizedString(for: date, relativeTo: Date())
        return "\(absolute) • \(relative)"
    }

    private var readingTime: String? {
        let text = article.contentText ?? article.summary ?? ""
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        guard words > 0 else { return nil }
        let minutes = max(1, Int(round(Double(words) / 200.0)))
        return "\(minutes) min read"
    }

    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let relativeFormatter = RelativeDateTimeFormatter()
}

struct ReaderTextView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme
    let article: Article
    let maxWidth: CGFloat?
    let isExpanded: Bool
    let horizontalMargin: CGFloat
    @Binding var progress: Double
    var onScroll: ((CGFloat) -> Void)?
    @State private var imagePreview: ImagePreviewItem?
    @State private var scrollOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 1
    @State private var viewportHeight: CGFloat = 1
    @State private var renderedHTML: AttributedString?

    var body: some View {
        let htmlContent = article.readerHTML ?? article.contentHTML
        let rawText = article.contentText ?? article.summary ?? ""
        let cleanedText = rawText.sanitizingProblematicCharacters()
        let paragraphs = ReaderTextView.paragraphs(from: cleanedText)
        let isImageOnly = article.imageURL != nil && isGarbledOrEmpty(cleanedText)
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    KeyboardScrollAnchor()
                        .frame(width: 0, height: 0)
                    if let imageURL = article.imageURL {
                        Button {
                            imagePreview = ImagePreviewItem(url: imageURL)
                        } label: {
                            AsyncImage(url: imageURL) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                Color.gray.opacity(0.2)
                            }
                            .frame(maxWidth: maxWidth ?? .infinity)
                            .frame(maxHeight: isImageOnly ? 500 : 360)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Open Image") {
                                NSWorkspace.shared.open(imageURL)
                            }
                        }
                    }

                    if !isImageOnly {
                        // Only show summary if it's different from the main content
                        let summaryText = article.summary?.sanitizingProblematicCharacters() ?? ""
                        let contentIsDifferent = !cleanedText.hasPrefix(summaryText.prefix(100)) && !summaryText.hasPrefix(cleanedText.prefix(100))

                        if !summaryText.isEmpty, !isGarbledOrEmpty(summaryText), contentIsDifferent {
                            Text(summaryText)
                                .font(settings.readerFont(size: settings.readerFontSize - 2, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Group {
                            if let htmlContent = htmlContent, !htmlContent.isEmpty {
                                if let attributed = renderedHTML {
                                    Text(attributed)
                                        .lineSpacing(settings.readerLineSpacing)
                                } else {
                                    Text("Loading article...")
                                        .font(settings.readerFont)
                                        .lineSpacing(settings.readerLineSpacing)
                                }
                            } else if paragraphs.isEmpty {
                                if article.imageURL == nil {
                                    Text("Loading article...")
                                        .font(settings.readerFont)
                                        .lineSpacing(settings.readerLineSpacing)
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                                        Text(paragraph)
                                            .font(settings.readerFont)
                                            .lineSpacing(settings.readerLineSpacing)
                                    }
                                }
                            }
                        }
                    } else if article.link != nil {
                        Text("Tap image to view full size, or switch to Web view for more details.")
                            .font(settings.readerFont(size: settings.readerFontSize - 2, weight: .regular))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                }
                .frame(maxWidth: isExpanded ? 900 : (maxWidth ?? .infinity), alignment: .leading)
                .padding(.horizontal, isExpanded ? max(24, horizontalMargin) : 24)
                .padding(.vertical, 24)
                .background(
                    GeometryReader { contentGeo in
                        Color.clear
                            .preference(key: ReaderContentHeightKey.self, value: contentGeo.size.height)
                    }
                )
                .background(
                    GeometryReader { offsetGeo in
                        Color.clear
                            .preference(key: ReaderScrollOffsetKey.self, value: offsetGeo.frame(in: .named("readerScroll")).minY)
                    }
                    .frame(height: 0)
                )
            }
            .coordinateSpace(name: "readerScroll")
            .onPreferenceChange(ReaderContentHeightKey.self) { height in
                contentHeight = height
                updateProgress()
            }
            .onPreferenceChange(ReaderScrollOffsetKey.self) { offset in
                scrollOffset = offset
                updateProgress()
            }
            .onAppear {
                viewportHeight = proxy.size.height
            }
            .onChange(of: proxy.size.height) { _, newValue in
                viewportHeight = newValue
                updateProgress()
            }
            .onChange(of: scrollOffset) { _, newValue in
                onScroll?(max(0, -newValue))
            }
        }
        .textSelection(.enabled)
        .sheet(item: $imagePreview) { item in
            ImagePreviewView(url: item.url)
        }
        .background(readerBackground)
        .task(id: renderRequest(htmlContent: htmlContent)) {
            guard let htmlContent = htmlContent, !htmlContent.isEmpty else {
                renderedHTML = nil
                return
            }
            let request = renderRequest(htmlContent: htmlContent)
            let attributed = await Task.detached(priority: .userInitiated) {
                let scaledSize = max(0.75, min(3.5, request.typeScale)) * request.fontSize
                let font = SettingsStore.previewFont(family: request.fontFamily, size: scaledSize)
                let linkColor = ReaderTextView.linkColor(for: request.colorScheme)
                return ReaderTextView.attributedString(
                    from: request.html,
                    font: font,
                    lineSpacing: request.lineSpacing,
                    linkColor: linkColor
                )
            }.value
            renderedHTML = attributed
        }
    }

    private func renderRequest(htmlContent: String?) -> RenderRequest {
        RenderRequest(
            html: htmlContent ?? "",
            fontFamily: settings.readerFontFamily,
            fontSize: settings.readerFontSize,
            lineSpacing: settings.readerLineSpacing,
            typeScale: settings.typeScale,
            colorScheme: colorScheme
        )
    }

    nonisolated private static func paragraphs(from text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let parts = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.count > 1 {
            return parts
        }
        return text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Detects if text is empty, too short, or contains garbled/non-readable content
    private func isGarbledOrEmpty(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }

        // Check if text is too short to be meaningful content
        if trimmed.count < 20 { return true }

        // Count readable vs non-readable characters
        var readableCount = 0
        var totalCount = 0
        for scalar in trimmed.unicodeScalars {
            totalCount += 1
            // Letters, numbers, common punctuation, and whitespace are readable
            if scalar.properties.isAlphabetic ||
               scalar.properties.isWhitespace ||
               scalar.value >= 0x30 && scalar.value <= 0x39 || // 0-9
               scalar.value >= 0x20 && scalar.value <= 0x7E {  // Basic ASCII printable
                readableCount += 1
            }
        }

        // If less than 60% readable, consider it garbled
        let readableRatio = totalCount > 0 ? Double(readableCount) / Double(totalCount) : 0
        return readableRatio < 0.6
    }

    nonisolated private static func attributedString(from html: String, font: Font, lineSpacing: Double, linkColor: NSColor) -> AttributedString? {
        let normalized = normalizeHTML(html)
        // Add CSS to force paragraph spacing
        let css = """
        <style>
        p { margin-bottom: 0.16em; margin-top: 0; }
        div { margin-bottom: 0.10em; }
        br + br { display: block; content: ""; margin-top: 0.13em; }
        </style>
        """
        let wrapped = "\(css)<div>\(normalized)</div>"
        guard let data = wrapped.data(using: .utf8) else { return nil }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        guard let attributed = try? NSMutableAttributedString(data: data, options: options, documentAttributes: nil) else {
            return nil
        }
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.paragraphSpacing = 3  // Spacing after paragraphs
        paragraphStyle.paragraphSpacingBefore = 0  // Spacing before paragraphs
        attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attributed.length))
        attributed.enumerateAttribute(.link, in: NSRange(location: 0, length: attributed.length), options: []) { value, range, _ in
            guard value != nil else { return }
            attributed.addAttribute(.foregroundColor, value: linkColor, range: range)
            attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        var swiftString = AttributedString(attributed)
        swiftString.font = font
        return swiftString
    }

    nonisolated private static func normalizeHTML(_ html: String) -> String {
        var output = html

        // Normalize all BR tags to consistent format first
        output = output.replacingOccurrences(of: "<br />", with: "<br/>", options: .caseInsensitive)
        output = output.replacingOccurrences(of: "<br>", with: "<br/>", options: .caseInsensitive)

        // Convert double newlines (paragraph breaks in source) to HTML paragraph breaks
        output = output.replacingOccurrences(of: "\r\n\r\n", with: "</p><p>")
        output = output.replacingOccurrences(of: "\n\n", with: "</p><p>")

        // Convert double BR tags into paragraph breaks for proper spacing
        output = output.replacingOccurrences(of: "<br/><br/>", with: "</p><p>", options: .caseInsensitive)
        output = output.replacingOccurrences(of: "<br/>\n<br/>", with: "</p><p>", options: .caseInsensitive)
        output = output.replacingOccurrences(of: "<br/> <br/>", with: "</p><p>", options: .caseInsensitive)

        // Convert single newlines to line breaks (preserves paragraph structure)
        output = output.replacingOccurrences(of: "\r\n", with: "<br/>")
        output = output.replacingOccurrences(of: "\n", with: "<br/>")

        // Wrap in paragraph tags if not already wrapped
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.lowercased().hasPrefix("<p") && !trimmed.lowercased().hasPrefix("<div") && !trimmed.lowercased().hasPrefix("<style") {
            output = "<p>\(output)</p>"
        }

        // Clean up empty paragraphs that might have been created
        output = output.replacingOccurrences(of: "<p></p>", with: "", options: .caseInsensitive)
        output = output.replacingOccurrences(of: "<p> </p>", with: "", options: .caseInsensitive)
        output = output.replacingOccurrences(of: "<p><br/></p>", with: "", options: .caseInsensitive)

        return output
    }

    nonisolated private static func linkColor(for scheme: ColorScheme) -> NSColor {
        switch scheme {
        case .dark:
            return NSColor.systemCyan
        default:
            return NSColor.linkColor
        }
    }

    private var readerBackground: some View {
        Group {
            if colorScheme == .dark {
                LinearGradient(colors: [Color.black.opacity(0.2), Color.black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
            } else {
                Color(.windowBackgroundColor)
            }
        }
    }

    private func updateProgress() {
        let total = max(contentHeight - viewportHeight, 1)
        let value = min(max((-scrollOffset) / total, 0), 1)
        if abs(progress - value) > 0.01 {
            progress = value
        }
    }
}

private struct RenderRequest: Equatable {
    let html: String
    let fontFamily: ReaderFontFamily
    let fontSize: Double
    let lineSpacing: Double
    let typeScale: Double
    let colorScheme: ColorScheme
}

private struct ReaderScrollOffsetKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ReaderContentHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 1
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ImagePreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ImagePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    var body: some View {
        GeometryReader { geo in
            let imageWidth = min(geo.size.width - 40, 1400)
            let imageHeight = min(geo.size.height - 40, 900)

            ZStack {
                Color.black
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }

                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: imageWidth, maxHeight: imageHeight)
                            .onTapGesture { }
                    case .failure:
                        VStack {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                            Text("Failed to load image")
                        }
                        .foregroundStyle(.secondary)
                    case .empty:
                        ProgressView()
                            .tint(.white)
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)

                // Close button
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .buttonStyle(.plain)
                        .padding(20)
                    }
                    Spacer()
                }
            }
        }
        .frame(minWidth: 800, idealWidth: 1200, minHeight: 600, idealHeight: 800)
    }
}

// MARK: - Keyboard Scroll Support

/// Zero-size NSView placed inside a ScrollView. Uses enclosingScrollView (walks UP the
/// view hierarchy) to get a reliable reference to the backing NSScrollView, then scrolls
/// it when the .scrollReader notification fires. No Accessibility permissions needed.
struct KeyboardScrollAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // Defer lookup to next run loop so the view is in the hierarchy
        DispatchQueue.main.async {
            context.coordinator.scrollView = view.enclosingScrollView
        }
        context.coordinator.startObserving()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Re-acquire in case the hierarchy changed
        DispatchQueue.main.async {
            context.coordinator.scrollView = nsView.enclosingScrollView
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        weak var scrollView: NSScrollView?
        private var observer: NSObjectProtocol?

        func startObserving() {
            observer = NotificationCenter.default.addObserver(
                forName: .scrollReader, object: nil, queue: .main
            ) { [weak self] note in
                guard let self, let scrollView = self.scrollView,
                      let documentView = scrollView.documentView else { return }
                let direction = (note.userInfo?["direction"] as? Int) ?? 1
                let clip = scrollView.contentView
                let current = clip.bounds.origin
                let maxY = max(0, documentView.frame.height - clip.bounds.height)
                let delta: CGFloat = CGFloat(direction) * 80
                let newY = min(max(current.y + delta, 0), maxY)
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.12
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    clip.animator().setBoundsOrigin(NSPoint(x: current.x, y: newY))
                }
                scrollView.reflectScrolledClipView(clip)
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
