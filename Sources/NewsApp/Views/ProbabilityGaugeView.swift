import SwiftUI

struct ProbabilityGaugeView: View {
    let probability: Double
    let size: GaugeSize
    let showLabel: Bool

    enum GaugeSize {
        case small
        case medium
        case large

        var dimension: CGFloat {
            switch self {
            case .small: return 32
            case .medium: return 48
            case .large: return 64
            }
        }

        var lineWidth: CGFloat {
            switch self {
            case .small: return 3
            case .medium: return 4
            case .large: return 5
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .small: return 10
            case .medium: return 14
            case .large: return 18
            }
        }
    }

    init(probability: Double, size: GaugeSize = .medium, showLabel: Bool = true) {
        self.probability = probability
        self.size = size
        self.showLabel = showLabel
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: size.lineWidth)

            Circle()
                .trim(from: 0, to: probability)
                .stroke(
                    probabilityColor,
                    style: StrokeStyle(lineWidth: size.lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: probability)

            if showLabel {
                Text("\(Int(probability * 100))%")
                    .font(.system(size: size.fontSize, weight: .bold, design: .rounded))
                    .foregroundColor(probabilityColor)
            }
        }
        .frame(width: size.dimension, height: size.dimension)
    }

    private var probabilityColor: Color {
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

struct ProbabilityBarView: View {
    let probability: Double
    let height: CGFloat

    init(probability: Double, height: CGFloat = 6) {
        self.probability = probability
        self.height = height
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.secondary.opacity(0.2))

                RoundedRectangle(cornerRadius: height / 2)
                    .fill(probabilityGradient)
                    .frame(width: geometry.size.width * probability)
                    .animation(.easeInOut(duration: 0.3), value: probability)
            }
        }
        .frame(height: height)
    }

    private var probabilityGradient: LinearGradient {
        let percent = probability * 100
        let color: Color
        if percent >= 60 {
            color = Color(red: 0.2, green: 0.7, blue: 0.4)  // Muted green
        } else if percent >= 35 {
            color = Color(red: 0.55, green: 0.55, blue: 0.6)  // Slate gray
        } else {
            color = Color(red: 0.6, green: 0.45, blue: 0.45)  // Muted red-gray
        }
        return LinearGradient(
            colors: [color.opacity(0.8), color],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct ProbabilityPillView: View {
    let probability: Double

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(probabilityColor)
                .frame(width: 8, height: 8)

            Text("\(Int(probability * 100))%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(probabilityColor.opacity(0.15))
        .cornerRadius(12)
    }

    private var probabilityColor: Color {
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
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            ProbabilityGaugeView(probability: 0.85, size: .small)
            ProbabilityGaugeView(probability: 0.55, size: .medium)
            ProbabilityGaugeView(probability: 0.25, size: .large)
        }

        VStack(spacing: 8) {
            ProbabilityBarView(probability: 0.75)
            ProbabilityBarView(probability: 0.45)
            ProbabilityBarView(probability: 0.15)
        }
        .padding(.horizontal)

        HStack(spacing: 8) {
            ProbabilityPillView(probability: 0.82)
            ProbabilityPillView(probability: 0.51)
            ProbabilityPillView(probability: 0.18)
        }
    }
    .padding()
}
