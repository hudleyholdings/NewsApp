import SwiftUI

struct IconAvatar: View {
    let text: String

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 28, height: 28)
            Text(text.uppercased())
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var gradientColors: [Color] {
        let colors: [Color] = [.blue, .teal, .orange, .pink, .mint, .indigo]
        let index = abs(text.hashValue) % colors.count
        let second = (index + 2) % colors.count
        return [colors[index], colors[second]]
    }
}
