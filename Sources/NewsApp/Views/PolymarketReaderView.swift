import SwiftUI

/// Custom reader view for Polymarket prediction markets
/// Renders market data beautifully instead of showing raw HTML/JSON
struct PolymarketReaderView: View {
    let article: Article
    @State private var event: PolymarketEvent?
    @State private var priceHistory: [PricePoint] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @Environment(\.openURL) private var openURL

    private let service = PolymarketService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with image and probability side by side
                HStack(alignment: .top, spacing: 20) {
                    // Image thumbnail (if available)
                    if let imageURL = article.imageURL {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: 200, maxHeight: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            default:
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.purple.opacity(0.15))
                                    .frame(width: 160, height: 120)
                                    .overlay(
                                        Image(systemName: "chart.line.uptrend.xyaxis")
                                            .font(.system(size: 36))
                                            .foregroundStyle(.purple.opacity(0.5))
                                    )
                            }
                        }
                    }

                    // Main probability display
                    VStack(alignment: .leading, spacing: 12) {
                        if let event = event, let leading = event.leadingMarket {
                            compactProbabilityView(probability: leading.probability, label: leading.label)
                        } else if let data = article.polymarketData {
                            compactProbabilityView(probability: data.probability, label: data.leadingLabel)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                VStack(alignment: .leading, spacing: 20) {
                    // Price chart
                    if !priceHistory.isEmpty {
                        priceChartSection
                    }

                    // Multi-outcome display
                    if let event = event, let markets = event.markets, markets.count > 1 {
                        multiOutcomeSection(event: event)
                    }

                    // Stats grid
                    statsSection

                    // Description
                    if let event = event, let description = event.description, !description.isEmpty {
                        descriptionSection(description)
                    }

                    // Action buttons
                    actionButtons

                    // Legal disclaimer
                    Text("For informational purposes only. Not financial or investment advice. Prediction markets may be subject to legal restrictions in your jurisdiction.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: article.id) {
            // Reset state when article changes
            event = nil
            priceHistory = []
            isLoading = true
            loadError = nil
            await loadEventData()
        }
    }

    // MARK: - Compact Probability View (for header)

    @ViewBuilder
    private func compactProbabilityView(probability: Double, label: String?) -> some View {
        let hasMultipleOutcomes = (event?.markets?.count ?? 0) > 1
        let isYesNoMarket = !hasMultipleOutcomes || label == nil || label?.isEmpty == true || label == "Yes"

        VStack(alignment: .leading, spacing: 8) {
            if isYesNoMarket {
                // Simple Yes/No market
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(probability * 100))")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(probabilityGradient(probability))
                    Text("%")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Text("chance of YES")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Trend indicator
                if priceHistory.count > 1,
                   let first = priceHistory.first?.price,
                   let last = priceHistory.last?.price,
                   first > 0 {
                    let change = ((last - first) / first) * 100
                    trendBadge(change: change)
                }
            } else {
                // Multi-outcome: show leading outcome
                Text("LEADING OUTCOME")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                HStack(alignment: .center, spacing: 12) {
                    Text("\(Int(probability * 100))%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(probabilityGradient(probability))
                        )

                    if let label = label, !label.isEmpty {
                        Text(label)
                            .font(.system(size: 18, weight: .semibold))
                            .lineLimit(2)
                    }
                }

                // Trend indicator
                if priceHistory.count > 1,
                   let first = priceHistory.first?.price,
                   let last = priceHistory.last?.price,
                   first > 0 {
                    let change = ((last - first) / first) * 100
                    trendBadge(change: change)
                }
            }
        }
    }

    // MARK: - Main Probability

    @ViewBuilder
    private func mainProbabilityView(probability: Double, label: String?) -> some View {
        let hasMultipleOutcomes = (event?.markets?.count ?? 0) > 1
        let isYesNoMarket = !hasMultipleOutcomes || label == "Yes" || label == nil || label?.isEmpty == true

        VStack(alignment: .leading, spacing: 16) {
            if isYesNoMarket {
                // Simple Yes/No market - show big probability
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(Int(probability * 100))")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundStyle(probabilityGradient(probability))

                    Text("%")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Trend indicator
                    if priceHistory.count > 1,
                       let first = priceHistory.first?.price,
                       let last = priceHistory.last?.price,
                       first > 0 {
                        let change = ((last - first) / first) * 100
                        trendBadge(change: change)
                    }
                }

                Text("chance of YES")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else {
                // Multi-outcome market - show leading outcome prominently
                VStack(alignment: .leading, spacing: 8) {
                    Text("LEADING OUTCOME")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(1)

                    HStack(alignment: .center, spacing: 16) {
                        // Probability badge
                        Text("\(Int(probability * 100))%")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(probabilityGradient(probability))
                            )

                        // Label
                        if let label = label, !label.isEmpty {
                            Text(label)
                                .font(.system(size: 24, weight: .semibold))
                                .lineLimit(2)
                        }

                        Spacer()

                        // Trend indicator
                        if priceHistory.count > 1,
                           let first = priceHistory.first?.price,
                           let last = priceHistory.last?.price,
                           first > 0 {
                            let change = ((last - first) / first) * 100
                            trendBadge(change: change)
                        }
                    }
                }
                .padding(16)
                .background(Color.purple.opacity(0.08))
                .cornerRadius(12)
            }
        }
    }

    @ViewBuilder
    private func trendBadge(change: Double) -> some View {
        let isUp = change >= 0
        HStack(spacing: 4) {
            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 14, weight: .bold))
            Text(String(format: "%.1f%%", abs(change)))
                .font(.system(size: 16, weight: .bold, design: .rounded))
        }
        .foregroundStyle(isUp ? .green : .red)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background((isUp ? Color.green : Color.red).opacity(0.15))
        .cornerRadius(8)
    }

    private func probabilityGradient(_ probability: Double) -> LinearGradient {
        let percent = probability * 100
        let colors: [Color]
        if percent >= 60 {
            // Muted green
            let baseColor = Color(red: 0.2, green: 0.7, blue: 0.4)
            colors = [baseColor, baseColor.opacity(0.85)]
        } else if percent >= 35 {
            // Slate gray
            let baseColor = Color(red: 0.55, green: 0.55, blue: 0.6)
            colors = [baseColor, baseColor.opacity(0.85)]
        } else {
            // Muted red-gray
            let baseColor = Color(red: 0.6, green: 0.45, blue: 0.45)
            colors = [baseColor, baseColor.opacity(0.85)]
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    // MARK: - Price Chart

    @ViewBuilder
    private var priceChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Price History")
                    .font(.headline)
                Spacer()
                Text("7 Day")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(4)
            }

            LargePriceChartView(history: priceHistory)
                .frame(height: 180)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Multi-Outcome

    @ViewBuilder
    private func multiOutcomeSection(event: PolymarketEvent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("All Outcomes")
                .font(.headline)

            MultiOutcomeView(event: event, maxOutcomes: 8)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Stats

    @ViewBuilder
    private var statsSection: some View {
        let data = article.polymarketData
        let vol24 = event?.volume24hr ?? data?.volume24hr ?? 0
        let totalVol = event?.volume ?? data?.totalVolume ?? 0
        let liquidity = event?.liquidity ?? 0
        let comments = event?.commentCount ?? data?.commentCount ?? 0

        VStack(alignment: .leading, spacing: 12) {
            Text("Market Stats")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                StatCard(title: "24h Volume", value: formatCurrency(vol24), icon: "chart.bar.fill", color: .blue)
                StatCard(title: "Total Volume", value: formatCurrency(totalVol), icon: "dollarsign.circle.fill", color: .green)

                if liquidity > 0 {
                    StatCard(title: "Liquidity", value: formatCurrency(liquidity), icon: "drop.fill", color: .cyan)
                }

                if comments > 0 {
                    StatCard(title: "Comments", value: "\(comments)", icon: "bubble.left.fill", color: .orange)
                }

                if let endDate = data?.endDate {
                    StatCard(title: "Ends", value: formatEndDate(endDate), icon: "calendar", color: .purple)
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Description

    @ViewBuilder
    private func descriptionSection(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About this Market")
                .font(.headline)

            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                if let url = article.link {
                    openURL(url)
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.up.right.square.fill")
                    Text("Trade on Polymarket")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.purple)
                .foregroundStyle(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)

            Button {
                if let url = article.link {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            } label: {
                Image(systemName: "link")
                    .font(.headline)
                    .frame(width: 50, height: 50)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    // MARK: - Data Loading

    private func loadEventData() async {
        isLoading = true

        // Try to get event slug from article link
        if let link = article.link?.absoluteString,
           let slug = extractSlug(from: link) {
            do {
                event = try await service.fetchEventDetails(slug: slug)

                // Load price history
                if let market = event?.primaryMarket ?? event?.markets?.first,
                   let tokenId = market.yesTokenId {
                    let history = try await service.fetchPriceHistory(tokenID: tokenId, interval: .oneWeek)
                    priceHistory = history
                }
            } catch {
                loadError = error.localizedDescription
            }
        }

        isLoading = false
    }

    private func extractSlug(from url: String) -> String? {
        // Extract slug from URLs like "https://polymarket.com/event/some-slug"
        guard let urlObj = URL(string: url),
              urlObj.pathComponents.count >= 3,
              urlObj.pathComponents[1] == "event" else {
            return nil
        }
        return urlObj.pathComponents[2]
    }

    private func formatCurrency(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "$%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.0fK", value / 1_000)
        }
        return String(format: "$%.0f", value)
    }

    private func formatEndDate(_ date: Date) -> String {
        let now = Date()
        if date < now { return "Ended" }

        let components = Calendar.current.dateComponents([.day, .hour], from: now, to: date)
        if let days = components.day, days > 0 {
            return "\(days)d left"
        }
        if let hours = components.hour, hours > 0 {
            return "\(hours)h left"
        }
        return "Soon"
    }
}

// MARK: - Supporting Views

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.08))
        .cornerRadius(8)
    }
}

private struct LargePriceChartView: View {
    let history: [PricePoint]

    private var prices: [Double] {
        history.map { $0.price }
    }

    private var minPrice: Double {
        prices.min() ?? 0
    }

    private var maxPrice: Double {
        prices.max() ?? 1
    }

    private var priceRange: Double {
        max(maxPrice - minPrice, 0.01)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                // Grid lines
                VStack(spacing: 0) {
                    ForEach(0..<5) { i in
                        Divider()
                            .opacity(0.3)
                        if i < 4 { Spacer() }
                    }
                }

                // Price labels on right
                VStack {
                    Text("\(Int(maxPrice * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(minPrice * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 4)

                // Line chart
                if prices.count > 1 {
                    let stepX = (width - 40) / CGFloat(prices.count - 1)

                    // Fill gradient
                    Path { path in
                        for (index, price) in prices.enumerated() {
                            let x = CGFloat(index) * stepX
                            let normalizedY = (price - minPrice) / priceRange
                            let y = height * (1 - normalizedY)

                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                        path.addLine(to: CGPoint(x: (width - 40), y: height))
                        path.addLine(to: CGPoint(x: 0, y: height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.3), Color.purple.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // Line
                    Path { path in
                        for (index, price) in prices.enumerated() {
                            let x = CGFloat(index) * stepX
                            let normalizedY = (price - minPrice) / priceRange
                            let y = height * (1 - normalizedY)

                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Color.purple, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    // End dot
                    if let lastPrice = prices.last {
                        let lastY = height * (1 - (lastPrice - minPrice) / priceRange)
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 8, height: 8)
                            .position(x: width - 40, y: lastY)
                    }
                }
            }
        }
    }
}

#Preview {
    Text("Preview requires an article")
        .padding()
}
