import SwiftUI

// MARK: - Sparkline View

struct SparklineView: View {
    let prices: [Double]
    let color: Color
    let height: CGFloat

    init(prices: [Double], color: Color = .purple, height: CGFloat = 30) {
        self.prices = prices
        self.color = color
        self.height = height
    }

    var body: some View {
        GeometryReader { geometry in
            if prices.count > 1, let minPrice = prices.min(), let maxPrice = prices.max(), maxPrice > minPrice {
                let range = maxPrice - minPrice
                let stepX = geometry.size.width / CGFloat(prices.count - 1)

                Path { path in
                    for (index, price) in prices.enumerated() {
                        let x = CGFloat(index) * stepX
                        let normalizedY = (price - minPrice) / range
                        let y = geometry.size.height * (1 - normalizedY)

                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                // Trend indicator
                let trendUp = (prices.last ?? 0) > (prices.first ?? 0)
                Circle()
                    .fill(trendUp ? Color.green : Color.red)
                    .frame(width: 4, height: 4)
                    .position(
                        x: geometry.size.width,
                        y: geometry.size.height * (1 - ((prices.last! - minPrice) / range))
                    )
            } else {
                // Flat line if no variance
                Rectangle()
                    .fill(color.opacity(0.3))
                    .frame(height: 1)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Price Change Indicator

struct PriceChangeView: View {
    let currentPrice: Double
    let previousPrice: Double

    private var change: Double {
        guard previousPrice > 0 else { return 0 }
        return currentPrice - previousPrice
    }

    private var changePercent: Double {
        guard previousPrice > 0 else { return 0 }
        return (change / previousPrice) * 100
    }

    private var isUp: Bool { change >= 0 }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 9, weight: .bold))

            Text(String(format: "%.1f%%", abs(changePercent)))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(isUp ? .green : .red)
    }
}

// MARK: - Multi-Outcome Display

struct MultiOutcomeView: View {
    let event: PolymarketEvent
    let maxOutcomes: Int

    init(event: PolymarketEvent, maxOutcomes: Int = 5) {
        self.event = event
        self.maxOutcomes = maxOutcomes
    }

    private var sortedMarkets: [(market: PolymarketMarket, probability: Double, label: String)] {
        guard let markets = event.markets else { return [] }

        // First pass: collect all questions
        let allQuestions = markets.compactMap { $0.question ?? $0.groupItemTitle }

        // Find common prefix to remove
        let commonPrefix = findCommonPrefix(allQuestions)

        return markets.compactMap { market -> (PolymarketMarket, Double, String)? in
            let prob = market.yesPrice ?? 0
            guard prob > 0.001 else { return nil }

            let label: String
            if let question = market.question ?? market.groupItemTitle {
                label = extractSmartLabel(from: question, commonPrefix: commonPrefix)
            } else {
                label = "Option"
            }
            return (market, prob, label)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(maxOutcomes)
        .map { ($0.0, $0.1, $0.2) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(sortedMarkets.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 10) {
                    // Probability with colored background
                    Text("\(Int(item.probability * 100))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(barColor(for: index, isLeading: index == 0))
                        )

                    // Probability bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.12))

                            RoundedRectangle(cornerRadius: 4)
                                .fill(barColor(for: index, isLeading: index == 0).opacity(0.6))
                                .frame(width: geo.size.width * item.probability)
                        }
                    }
                    .frame(height: 26)

                    // Label
                    Text(item.label)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                        .frame(minWidth: 80, alignment: .leading)
                }
            }
        }
    }

    private func barColor(for index: Int, isLeading: Bool) -> Color {
        if isLeading {
            return Color(red: 0.2, green: 0.7, blue: 0.4)  // Muted green for leading
        }
        // Muted blue-gray scale for non-leading outcomes
        let grayColors: [Color] = [
            Color(white: 0.45),
            Color(white: 0.50),
            Color(white: 0.55),
            Color(white: 0.40),
            Color(white: 0.48),
        ]
        return grayColors[index % grayColors.count]
    }

    /// Find the longest common prefix among all questions
    private func findCommonPrefix(_ strings: [String]) -> String {
        guard let first = strings.first, !strings.isEmpty else { return "" }
        var prefix = first

        for string in strings.dropFirst() {
            while !string.hasPrefix(prefix) && !prefix.isEmpty {
                prefix = String(prefix.dropLast())
            }
        }

        // If the prefix ends mid-word, back up to last space
        if !prefix.isEmpty, let lastSpace = prefix.lastIndex(of: " ") {
            prefix = String(prefix[...lastSpace])
        }

        return prefix
    }

    /// Return the label as-is without manipulation
    private func extractSmartLabel(from question: String, commonPrefix: String) -> String {
        // Return original question without trimming
        question
    }
}

// MARK: - Market Detail Card

struct MarketDetailCard: View {
    let event: PolymarketEvent
    @State private var priceHistory: [Double] = []
    @State private var isLoadingHistory = false
    @Environment(\.openURL) private var openURL

    private let service = PolymarketService()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .top, spacing: 12) {
                // Image
                if let imageURL = event.resolvedImageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .cornerRadius(8)
                        default:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.purple.opacity(0.2))
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Image(systemName: "chart.pie")
                                        .foregroundStyle(.purple)
                                )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.headline)
                        .lineLimit(2)

                    // Leading probability
                    if let leading = event.leadingMarket {
                        HStack(spacing: 6) {
                            Text("\(Int(leading.probability * 100))%")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(probabilityColor(leading.probability))

                            if !leading.label.isEmpty && leading.label != "Yes" {
                                Text(leading.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.15))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }

                Spacer()
            }

            // Sparkline
            if !priceHistory.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("7D Trend")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if priceHistory.count > 1 {
                            PriceChangeView(
                                currentPrice: priceHistory.last ?? 0,
                                previousPrice: priceHistory.first ?? 0
                            )
                        }
                    }
                    SparklineView(prices: priceHistory, color: .purple, height: 40)
                }
                .padding(.vertical, 4)
            } else if isLoadingHistory {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
                .frame(height: 40)
            }

            // Multi-outcome display for grouped events
            if let markets = event.markets, markets.count > 1 {
                Divider()
                Text("Top Outcomes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                MultiOutcomeView(event: event, maxOutcomes: 4)
            }

            // Stats row
            Divider()
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("24h Volume")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(event.formattedVolume24hr)
                        .font(.system(size: 12, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Volume")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(event.formattedTotalVolume)
                        .font(.system(size: 12, weight: .semibold))
                }

                if let liquidity = event.liquidity, liquidity > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Liquidity")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(formatCurrency(liquidity))
                            .font(.system(size: 12, weight: .semibold))
                    }
                }

                Spacer()

                if let comments = event.commentCount, comments > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left")
                            .font(.caption)
                        Text("\(comments)")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
            }

            // Open in Polymarket button
            Button {
                if let url = event.eventURL {
                    openURL(url)
                }
            } label: {
                HStack {
                    Text("View on Polymarket")
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.purple.opacity(0.15))
                .foregroundStyle(.purple)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
        .task {
            await loadPriceHistory()
        }
    }

    private func loadPriceHistory() async {
        guard let market = event.primaryMarket ?? event.markets?.first,
              let tokenId = market.yesTokenId else { return }

        isLoadingHistory = true
        do {
            let history = try await service.fetchPriceHistory(tokenID: tokenId, interval: .oneWeek)
            priceHistory = history.map { $0.price }
        } catch {
            // Silently fail - sparkline is optional
        }
        isLoadingHistory = false
    }

    private func probabilityColor(_ probability: Double) -> Color {
        let percent = probability * 100
        if percent >= 60 {
            return Color(red: 0.2, green: 0.7, blue: 0.4)  // Muted green
        } else if percent >= 35 {
            return Color(red: 0.55, green: 0.55, blue: 0.6)  // Slate gray
        } else {
            return Color(red: 0.6, green: 0.45, blue: 0.45)  // Muted red-gray
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "$%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.0fK", value / 1_000)
        }
        return String(format: "$%.0f", value)
    }
}

// MARK: - Search View

struct PolymarketSearchView: View {
    @State private var searchText = ""
    @State private var results: [PolymarketEvent] = []
    @State private var isSearching = false
    @State private var selectedEvent: PolymarketEvent?

    private let service = PolymarketService()

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search prediction markets...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        Task { await search() }
                    }
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        results = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            .padding()

            Divider()

            // Results
            if results.isEmpty && !searchText.isEmpty && !isSearching {
                ContentUnavailableView("No Results", systemImage: "magnifyingglass", description: Text("Try a different search term"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(results, id: \.id) { event in
                            MarketDetailCard(event: event)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
    }

    private func search() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isSearching = true
        do {
            results = try await service.searchEvents(query: query)
        } catch {
            results = []
        }
        isSearching = false
    }
}

#Preview("Sparkline") {
    SparklineView(prices: [0.45, 0.48, 0.52, 0.49, 0.55, 0.58, 0.62, 0.59, 0.65])
        .frame(width: 100, height: 30)
        .padding()
}

#Preview("Multi Outcome") {
    Text("Preview requires live data")
        .padding()
}
