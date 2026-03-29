import SwiftUI

struct TrendingPredictionsWidget: View {
    @StateObject private var viewModel = TrendingPredictionsViewModel()
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chart.pie")
                        .foregroundStyle(.purple)
                    Text("Trending Predictions")
                        .font(.headline)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()

                if viewModel.isLoading && viewModel.events.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Spacer()
                    }
                    .padding()
                } else if viewModel.events.isEmpty {
                    HStack {
                        Spacer()
                        Text("No predictions available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding()
                } else {
                    VStack(spacing: 0) {
                        ForEach(viewModel.events.prefix(5), id: \.id) { event in
                            TrendingEventRow(event: event)
                            if event.id != viewModel.events.prefix(5).last?.id {
                                Divider()
                                    .padding(.leading, 12)
                            }
                        }
                    }
                }

                // Footer with refresh button
                HStack {
                    if let lastUpdated = viewModel.lastUpdated {
                        Text("Updated \(lastUpdated, style: .relative) ago")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button {
                        Task {
                            await viewModel.refresh()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isLoading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
        .task {
            await viewModel.loadIfNeeded()
        }
    }
}

struct TrendingEventRow: View {
    let event: PolymarketEvent
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = event.eventURL {
                openURL(url)
            }
        } label: {
            HStack(spacing: 10) {
                // Probability indicator
                if let market = event.primaryMarket {
                    ProbabilityGaugeView(
                        probability: market.yesPrice ?? 0,
                        size: .small,
                        showLabel: true
                    )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.subheadline)
                        .lineLimit(2)
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        Text(event.formattedVolume24hr)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if event.volume24hr ?? 0 > 100000 {
                            Text("HOT")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.orange)
                                .cornerRadius(3)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
class TrendingPredictionsViewModel: ObservableObject {
    @Published var events: [PolymarketEvent] = []
    @Published var isLoading = false
    @Published var lastUpdated: Date?

    private let service = PolymarketService()
    private var hasLoaded = false

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true

        do {
            events = try await service.fetchTrendingEvents(limit: 10)
            lastUpdated = Date()
        } catch {
            // Keep existing events on error
        }

        isLoading = false
    }
}

// MARK: - Top Sidebar Widget (More Info)

struct TrendingPredictionsTopView: View {
    @StateObject private var viewModel = TrendingPredictionsViewModel()
    @State private var isCollapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isCollapsed.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.purple)
                    Text("PREDICTION MARKETS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                if viewModel.events.isEmpty && !viewModel.isLoading {
                    Text("Loading predictions...")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                } else {
                    VStack(spacing: 2) {
                        ForEach(viewModel.events.prefix(5), id: \.id) { event in
                            TopPredictionRow(event: event)
                        }
                    }
                    .padding(.bottom, 6)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.purple.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.purple.opacity(0.15), lineWidth: 1)
        )
        .task {
            await viewModel.loadIfNeeded()
        }
    }
}

struct TopPredictionRow: View {
    let event: PolymarketEvent
    @Environment(\.openURL) private var openURL
    @State private var isHovered = false
    @State private var priceHistory: [Double] = []

    private let service = PolymarketService()

    private var leadingInfo: (probability: Double, label: String) {
        if let leading = event.leadingMarket {
            return (leading.probability, leading.label)
        }
        return (event.primaryMarket?.yesPrice ?? 0, "Yes")
    }

    private var priceChange: Double? {
        guard priceHistory.count > 1,
              let first = priceHistory.first,
              let last = priceHistory.last,
              first > 0 else { return nil }
        return ((last - first) / first) * 100
    }

    var body: some View {
        Button {
            if let url = event.eventURL {
                openURL(url)
            }
        } label: {
            HStack(spacing: 8) {
                // Probability with color background
                let prob = leadingInfo.probability
                Text("\(Int(prob * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(probabilityColor(prob))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        // Leading outcome label
                        if !leadingInfo.label.isEmpty && leadingInfo.label != "Yes" {
                            Text(leadingInfo.label)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color(red: 0.55, green: 0.5, blue: 0.65))  // Muted purple
                                .lineLimit(1)
                        }

                        // Volume
                        HStack(spacing: 2) {
                            Image(systemName: "dollarsign.circle.fill")
                                .font(.system(size: 8))
                            Text(event.formattedVolume24hr)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(.secondary)

                        // Price change indicator
                        if let change = priceChange, abs(change) > 0.5 {
                            HStack(spacing: 1) {
                                Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                                    .font(.system(size: 7, weight: .bold))
                                Text(String(format: "%.0f%%", abs(change)))
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .foregroundStyle(change >= 0 ? .green : .red)
                        }

                        // Hot indicator for high volume
                        if (event.volume24hr ?? 0) > 500_000 {
                            Text("HOT")
                                .font(.system(size: 7, weight: .black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule().fill(Color.orange)
                                )
                        }
                    }
                }

                // Mini sparkline
                if priceHistory.count > 2 {
                    SparklineView(prices: priceHistory, color: .purple.opacity(0.7), height: 16)
                        .frame(width: 40)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.purple.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .task {
            await loadPriceHistory()
        }
    }

    private func loadPriceHistory() async {
        guard let market = event.primaryMarket ?? event.markets?.first,
              let tokenId = market.yesTokenId else { return }

        do {
            let history = try await service.fetchPriceHistory(tokenID: tokenId, interval: .oneWeek)
            // Downsample to ~20 points for mini sparkline
            let stride = max(1, history.count / 20)
            priceHistory = stride > 1 ? history.enumerated().compactMap { $0.offset % stride == 0 ? $0.element.price : nil } : history.map { $0.price }
        } catch {
            // Silently fail
        }
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
}

// MARK: - Compact Sidebar Widget (Legacy)

struct TrendingPredictionsSidebarView: View {
    @StateObject private var viewModel = TrendingPredictionsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.pie")
                    .foregroundStyle(.purple)
                Text("Predictions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)

            if viewModel.isLoading && viewModel.events.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.events.prefix(3), id: \.id) { event in
                    CompactPredictionRow(event: event)
                }
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }
}

struct CompactPredictionRow: View {
    let event: PolymarketEvent
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = event.eventURL {
                openURL(url)
            }
        } label: {
            HStack(spacing: 6) {
                if let market = event.primaryMarket {
                    Text("\(market.probabilityPercent)%")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(probabilityColor(market.yesPrice ?? 0))
                        .frame(width: 32)
                }

                Text(event.title)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
}

#Preview {
    TrendingPredictionsWidget()
        .frame(width: 300)
        .padding()
}
