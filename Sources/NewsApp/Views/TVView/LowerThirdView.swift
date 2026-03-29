import SwiftUI
import CoreImage.CIFilterBuiltins

/// Broadcast-style lower third - compact bar at bottom of screen
/// Follows title-safe guidelines for streaming compatibility
/// Shows headline, then transitions to first paragraph
struct LowerThirdView: View {
    let article: Article
    let source: String
    let category: String?
    let faviconURL: URL?
    let accentColor: Color
    let isVisible: Bool
    let showProgress: Bool
    let progress: Double
    let totalStories: Int
    let currentIndex: Int

    @EnvironmentObject private var settings: SettingsStore

    // Animation states
    @State private var showBar = false
    @State private var showSource = false
    @State private var showHeadline = false
    @State private var showContent = false
    @State private var faviconImage: NSImage?

    // Content transition state
    @State private var showingParagraph = false
    @State private var currentParagraphIndex = 0
    @State private var transitionWorkItem: DispatchWorkItem?

    // Title-safe margins (5% of screen)
    private let titleSafeMargin: CGFloat = 0.05

    // Timing
    private let headlineDisplayDuration: Double = 7.0  // Seconds before switching to paragraph
    private let paragraphDisplayDuration: Double = 8.0  // Seconds per paragraph part

    var body: some View {
        GeometryReader { geometry in
            let safeHorizontal = geometry.size.width * titleSafeMargin
            let safeBottom = geometry.size.height * titleSafeMargin

            ZStack {
                // Main content area
                VStack(spacing: 0) {
                    Spacer()

                    // Lower third container
                    HStack(alignment: .bottom, spacing: 16) {
                        // Left side: Lower third content
                        VStack(alignment: .leading, spacing: 0) {
                            sourceBar
                                .opacity(showSource ? 1 : 0)
                                .offset(x: showSource ? 0 : -40)

                            // Content area - headline or paragraph
                            contentArea
                                .opacity(showHeadline ? 1 : 0)
                                .offset(y: showHeadline ? 0 : 15)
                        }
                        .frame(maxWidth: geometry.size.width * 0.65, alignment: .leading)

                        Spacer(minLength: 16)

                        // Right side: Integrated QR + Clock & Weather widget
                        TVInfoWidget(
                            articleURL: settings.tvShowQRCode ? article.link : nil
                        )
                        .opacity(showBar ? 1 : 0)
                    }
                    .padding(.horizontal, safeHorizontal)
                    .offset(y: showBar ? 0 : 80)
                    .opacity(showBar ? 1 : 0)

                    // Progress segments
                    if showProgress {
                        progressSegments
                            .padding(.horizontal, safeHorizontal)
                            .padding(.top, 10)
                            .opacity(showBar ? 1 : 0)
                    }

                    Spacer()
                        .frame(height: safeBottom)
                }
            }
        }
        .onChange(of: isVisible) { _, visible in
            if visible {
                animateIn()
            } else {
                animateOut()
            }
        }
        .onChange(of: article.id) { _, _ in
            // Reset state when article changes
            resetState()
            // Clear favicon so wrong one doesn't show
            faviconImage = nil
        }
        .onAppear {
            if isVisible {
                animateIn()
            }
        }
        .task(id: faviconURL) {
            await loadFavicon()
        }
    }

    // MARK: - Source Bar

    private var sourceBar: some View {
        HStack(spacing: 0) {
            // Accent bar + Favicon + Source name
            HStack(spacing: 0) {
                // Accent color bar
                Rectangle()
                    .fill(accentColor)
                    .frame(width: 6)

                // Favicon (tastefully integrated)
                if let favicon = faviconImage {
                    Image(nsImage: favicon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .padding(.leading, 12)
                        .padding(.vertical, 8)
                }

                // Source name - large and bold for TV viewing distance
                Text(source.uppercased())
                    .font(.system(size: 20, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(.white)
                    .padding(.leading, faviconImage != nil ? 12 : 16)
                    .padding(.trailing, 16)
                    .padding(.vertical, 10)
            }
            .background(accentColor)

            // Category badge
            if let category = category, !category.isEmpty, category.lowercased() != source.lowercased() {
                Text(category.uppercased())
                    .font(.system(size: 16, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.15))
            }

            Spacer()

            // Time ago - large and readable
            if let time = timeAgo {
                Text(time)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.4))
            }
        }
        .frame(height: 48)
        .background(Color.black.opacity(0.7))
    }

    // MARK: - Content Area (Headline or Paragraphs)

    private var contentArea: some View {
        ZStack {
            // Headline view
            headlineView
                .opacity(showingParagraph ? 0 : 1)
                .offset(y: showingParagraph ? -20 : 0)

            // Paragraph views - cycle through parts
            ForEach(Array(paragraphParts.enumerated()), id: \.offset) { index, part in
                paragraphView(part)
                    .opacity(showingParagraph && currentParagraphIndex == index ? 1 : 0)
                    .offset(y: showingParagraph && currentParagraphIndex == index ? 0 : 20)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: showingParagraph)
        .animation(.easeInOut(duration: 0.5), value: currentParagraphIndex)
        .background(Color.black.opacity(0.7))
    }

    private var headlineView: some View {
        Text(article.title)
            .font(.system(size: 36, weight: .bold, design: .default))
            .foregroundStyle(.white)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .lineSpacing(6)
            .shadow(color: .black.opacity(0.8), radius: 4, x: 0, y: 2)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func paragraphView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 28, weight: .medium, design: .default))
            .foregroundStyle(.white)
            .lineLimit(4)
            .multilineTextAlignment(.leading)
            .lineSpacing(6)
            .shadow(color: .black.opacity(0.7), radius: 3, x: 0, y: 2)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Split content into displayable paragraph parts (max ~200 chars each for readability)
    private var paragraphParts: [String] {
        let text = article.summary ?? article.contentText ?? ""
        let cleaned = cleanText(text)

        guard !cleaned.isEmpty else { return [] }

        // Collect all sentences first
        var sentences: [String] = []
        var currentSentence = ""

        for char in cleaned {
            currentSentence.append(char)
            if char == "." || char == "!" || char == "?" {
                let trimmed = currentSentence.trimmingCharacters(in: .whitespaces)
                if trimmed.count > 20 {
                    sentences.append(trimmed)
                }
                currentSentence = ""

                // Limit total sentences
                if sentences.count >= 8 {
                    break
                }
            }
        }

        guard !sentences.isEmpty else { return [] }

        // Group sentences into parts (~200 chars each for TV readability)
        var parts: [String] = []
        var currentPart = ""

        for sentence in sentences {
            if currentPart.isEmpty {
                currentPart = sentence
            } else if currentPart.count + sentence.count < 220 {
                currentPart += " " + sentence
            } else {
                parts.append(currentPart)
                currentPart = sentence

                // Max 3 parts
                if parts.count >= 2 {
                    break
                }
            }
        }

        // Add final part
        if !currentPart.isEmpty && parts.count < 3 {
            parts.append(currentPart)
        }

        return parts
    }


    // MARK: - Progress Segments

    private var progressSegments: some View {
        HStack(spacing: 3) {
            ForEach(0..<min(totalStories, 25), id: \.self) { index in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.2))

                        if index < currentIndex {
                            // Completed
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.white.opacity(0.7))
                        } else if index == currentIndex {
                            // Current - animated progress
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.white)
                                .frame(width: geo.size.width * progress)
                        }
                    }
                }
                .frame(height: 3)
            }
        }
    }

    // MARK: - Helpers

    private var timeAgo: String? {
        guard let date = article.publishedAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func cleanText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&hellip;", with: "...")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadFavicon() async {
        guard let url = faviconURL else { return }
        if let image = await ImagePrefetcher.shared.loadImage(for: url) {
            faviconImage = image
        }
    }

    // MARK: - Animations

    private func animateIn() {
        // Cancel any pending transitions
        transitionWorkItem?.cancel()
        transitionWorkItem = nil

        // Reset states
        showBar = false
        showSource = false
        showHeadline = false
        showContent = false
        showingParagraph = false
        currentParagraphIndex = 0

        withAnimation(.easeOut(duration: 0.35)) {
            showBar = true
        }

        withAnimation(.easeOut(duration: 0.3).delay(0.1)) {
            showSource = true
        }

        withAnimation(.easeOut(duration: 0.35).delay(0.2)) {
            showHeadline = true
        }

        withAnimation(.easeOut(duration: 0.3).delay(0.35)) {
            showContent = true
        }

        // Transition to paragraph after headline display time
        if !paragraphParts.isEmpty {
            scheduleTransitionToParagraph()
        }
    }

    private func animateOut() {
        // Cancel any pending transitions
        transitionWorkItem?.cancel()
        transitionWorkItem = nil

        withAnimation(.easeIn(duration: 0.15)) {
            showContent = false
            showHeadline = false
        }

        withAnimation(.easeIn(duration: 0.15).delay(0.05)) {
            showSource = false
        }

        withAnimation(.easeIn(duration: 0.2).delay(0.1)) {
            showBar = false
        }
    }

    private func scheduleTransitionToParagraph() {
        let workItem = DispatchWorkItem { [self] in
            guard isVisible else { return }

            withAnimation(.easeInOut(duration: 0.5)) {
                showingParagraph = true
                currentParagraphIndex = 0
            }

            // Schedule cycling through additional paragraph parts
            if paragraphParts.count > 1 {
                scheduleNextParagraphPart()
            }
        }

        transitionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + headlineDisplayDuration, execute: workItem)
    }

    private func scheduleNextParagraphPart() {
        let workItem = DispatchWorkItem { [self] in
            guard isVisible && showingParagraph else { return }

            let nextIndex = currentParagraphIndex + 1
            if nextIndex < paragraphParts.count {
                withAnimation(.easeInOut(duration: 0.5)) {
                    currentParagraphIndex = nextIndex
                }

                // Schedule next part if there are more
                if nextIndex + 1 < paragraphParts.count {
                    scheduleNextParagraphPart()
                }
            }
        }

        transitionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + paragraphDisplayDuration, execute: workItem)
    }

    private func resetState() {
        // Cancel any pending transitions
        transitionWorkItem?.cancel()
        transitionWorkItem = nil

        showingParagraph = false
        currentParagraphIndex = 0
    }
}

// MARK: - Integrated Info Widget (QR + Clock + Weather)

struct TVInfoWidget: View {
    let articleURL: URL?

    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var weather = SharedWeatherService.shared
    @State private var currentTime = Date()
    @State private var cityIndex = 0
    @State private var timeTimer: Timer?
    @State private var cityTimer: Timer?

    // Major global cities for cycling when no weather configured
    private let globalCities: [(name: String, timezone: String)] = [
        ("New York", "America/New_York"),
        ("London", "Europe/London"),
        ("Tokyo", "Asia/Tokyo"),
        ("Sydney", "Australia/Sydney"),
        ("Paris", "Europe/Paris"),
        ("Dubai", "Asia/Dubai"),
        ("Hong Kong", "Asia/Hong_Kong"),
        ("Los Angeles", "America/Los_Angeles"),
    ]

    private var hasConfiguredWeather: Bool {
        settings.weatherEnabled && settings.weatherLatitude != 0 && settings.weatherLongitude != 0
    }

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            // QR Code (if URL provided)
            if let url = articleURL, let qrImage = generateQRCode(from: url.absoluteString) {
                VStack(spacing: 5) {
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 90, height: 90)
                        .padding(5)
                        .background(Color.white)
                        .cornerRadius(8)

                    Text("SCAN TO READ")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            // Divider if QR shown
            if articleURL != nil {
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 1)
            }

            // Time display - bigger for TV
            HStack(spacing: 6) {
                Text(formattedTime)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()

                VStack(alignment: .leading, spacing: 1) {
                    Text(amPm)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(timezone)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            // Weather or City - bigger for TV
            HStack(spacing: 6) {
                if hasConfiguredWeather, let data = weather.current {
                    Image(systemName: data.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(data.iconColor)

                    Text("\(data.temperature)°F")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(displayCity)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.6))

                    Text(currentCityName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 190)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
        .onAppear {
            startTimers()
            if hasConfiguredWeather {
                configureWeather()
            }
        }
        .onDisappear {
            timeTimer?.invalidate()
            timeTimer = nil
            cityTimer?.invalidate()
            cityTimer = nil
        }
    }

    // MARK: - QR Code Generation

    private func generateQRCode(from string: String) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        // Scale up for crisp rendering
        let scale = 6.0
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    // MARK: - Time Formatting

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        if !hasConfiguredWeather {
            formatter.timeZone = TimeZone(identifier: globalCities[cityIndex].timezone)
        }
        return formatter.string(from: currentTime)
    }

    private var amPm: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "a"
        if !hasConfiguredWeather {
            formatter.timeZone = TimeZone(identifier: globalCities[cityIndex].timezone)
        }
        return formatter.string(from: currentTime)
    }

    private var timezone: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "zzz"
        if !hasConfiguredWeather {
            formatter.timeZone = TimeZone(identifier: globalCities[cityIndex].timezone)
        }
        return formatter.string(from: currentTime)
    }

    private var displayCity: String {
        let full = settings.weatherCity
        if let comma = full.firstIndex(of: ",") {
            return String(full[..<comma])
        }
        return full.isEmpty ? "Local" : full
    }

    private var currentCityName: String {
        globalCities[cityIndex].name
    }

    private func startTimers() {
        // Invalidate any existing timers first
        timeTimer?.invalidate()
        cityTimer?.invalidate()

        // Update time every second
        timeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                currentTime = Date()
            }
        }

        // Cycle cities every 10 seconds if no weather configured
        if !hasConfiguredWeather {
            cityTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
                Task { @MainActor in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        cityIndex = (cityIndex + 1) % globalCities.count
                    }
                }
            }
        }
    }

    private func configureWeather() {
        weather.configure(
            city: displayCity,
            lat: settings.weatherLatitude,
            lon: settings.weatherLongitude
        )
        weather.fetchIfNeeded()
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        LinearGradient(
            colors: [.blue, .purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        LowerThirdView(
            article: Article(
                feedID: UUID(),
                externalID: "test",
                title: "Major Economic Summit Concludes with Historic Climate Agreement",
                summary: "World leaders reach unprecedented consensus on carbon reduction targets. The agreement promises to cut emissions by 50% before 2030, marking a significant milestone in global climate policy.",
                publishedAt: Date().addingTimeInterval(-180),
                isRead: false
            ),
            source: "BBC News",
            category: "World",
            faviconURL: nil,
            accentColor: .red,
            isVisible: true,
            showProgress: true,
            progress: 0.4,
            totalStories: 12,
            currentIndex: 3
        )
    }
    .frame(width: 1200, height: 700)
    .environmentObject(SettingsStore())
}
