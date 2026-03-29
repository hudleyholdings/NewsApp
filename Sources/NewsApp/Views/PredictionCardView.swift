import SwiftUI

struct PredictionCardView: View {
    let article: Article
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var polymarketData: PolymarketData? {
        article.polymarketData
    }

    var body: some View {
        HStack(spacing: 12) {
            // Probability gauge
            if let data = polymarketData {
                ProbabilityGaugeView(
                    probability: data.probability,
                    size: .medium,
                    showLabel: true
                )
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundColor(isSelected ? .white : .primary)

                // Stats row
                HStack(spacing: 12) {
                    if let data = polymarketData {
                        Label(data.formattedVolume24hr, systemImage: "chart.line.uptrend.xyaxis")
                            .font(.caption)
                            .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)

                        if let timeLeft = data.timeRemaining {
                            Label(timeLeft, systemImage: "clock")
                                .font(.caption)
                                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                        }

                        if data.commentCount > 0 {
                            Label("\(data.commentCount)", systemImage: "bubble.left")
                                .font(.caption)
                                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                        }
                    }
                }
            }

            Spacer()

            // Thumbnail if available
            if let imageURL = article.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 50, height: 50)
                            .cornerRadius(8)
                    case .failure:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Image(systemName: "chart.pie")
                                    .foregroundColor(.secondary)
                            )
                    case .empty:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(width: 50, height: 50)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor : cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.98)
    }
}

struct PredictionRowView: View {
    let article: Article
    let isSelected: Bool

    private var polymarketData: PolymarketData? {
        article.polymarketData
    }

    var body: some View {
        HStack(spacing: 10) {
            // Compact probability indicator
            if let data = polymarketData {
                ProbabilityPillView(probability: data.probability)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(article.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .foregroundColor(isSelected ? .white : .primary)

                if let data = polymarketData {
                    Text("\(data.formattedVolume24hr) vol")
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct PredictionDetailView: View {
    let article: Article
    @Environment(\.colorScheme) private var colorScheme

    private var polymarketData: PolymarketData? {
        article.polymarketData
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with large gauge
            HStack(alignment: .top, spacing: 16) {
                if let data = polymarketData {
                    ProbabilityGaugeView(
                        probability: data.probability,
                        size: .large,
                        showLabel: true
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(article.title)
                        .font(.title2)
                        .fontWeight(.bold)

                    if let author = article.author {
                        Text(author)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Stats grid
            if let data = polymarketData {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    StatBox(title: "24h Volume", value: data.formattedVolume24hr, icon: "chart.line.uptrend.xyaxis")
                    StatBox(title: "Total Volume", value: data.formattedTotalVolume, icon: "dollarsign.circle")
                    StatBox(title: "Comments", value: "\(data.commentCount)", icon: "bubble.left")
                }
            }

            // Probability bar
            if let data = polymarketData {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Yes")
                            .font(.caption)
                            .foregroundColor(.green)
                        Spacer()
                        Text("No")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    ProbabilityBarView(probability: data.probability, height: 10)
                    HStack {
                        Text("\(data.probabilityPercent)%")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                        Spacer()
                        Text("\(100 - data.probabilityPercent)%")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.95))
                )
            }

            // Time remaining
            if let data = polymarketData, let timeRemaining = data.timeRemaining {
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                    Text(timeRemaining)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // Description
            if let summary = article.summary {
                Text(summary)
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            // Link to Polymarket
            if let link = article.link {
                Link(destination: link) {
                    HStack {
                        Image(systemName: "arrow.up.right.square")
                        Text("View on Polymarket")
                    }
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                }
            }
        }
        .padding()
    }
}

struct StatBox: View {
    let title: String
    let value: String
    let icon: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)

            Text(value)
                .font(.headline)
                .fontWeight(.bold)

            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.95))
        )
    }
}
