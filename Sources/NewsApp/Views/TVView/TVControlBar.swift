import SwiftUI

/// Control bar for TV View - appears on mouse movement
struct TVControlBar: View {
    let isPlaying: Bool
    let currentIndex: Int
    let totalStories: Int
    let onPlayPause: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onClose: () -> Void

    @State private var isHoveringClose = false
    @State private var isHoveringPrev = false
    @State private var isHoveringPlay = false
    @State private var isHoveringNext = false

    var body: some View {
        VStack {
            // Top control bar
            HStack {
                // Close button
                Button(action: onClose) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Exit")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHoveringClose ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .onHover { isHoveringClose = $0 }

                Spacer()

                // Story counter
                Text("\(currentIndex + 1) of \(totalStories)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.black.opacity(0.3))
                    )

                Spacer()

                // Playback controls
                HStack(spacing: 4) {
                    // Previous
                    controlButton(
                        icon: "backward.fill",
                        action: onPrevious,
                        isHovering: $isHoveringPrev
                    )

                    // Play/Pause
                    controlButton(
                        icon: isPlaying ? "pause.fill" : "play.fill",
                        action: onPlayPause,
                        isHovering: $isHoveringPlay,
                        isLarge: true
                    )

                    // Next
                    controlButton(
                        icon: "forward.fill",
                        action: onNext,
                        isHovering: $isHoveringNext
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.8), Color.black.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Spacer()
        }
    }

    @ViewBuilder
    private func controlButton(
        icon: String,
        action: @escaping () -> Void,
        isHovering: Binding<Bool>,
        isLarge: Bool = false
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: isLarge ? 16 : 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: isLarge ? 44 : 36, height: isLarge ? 44 : 36)
                .background(
                    Circle()
                        .fill(isHovering.wrappedValue ? Color.white.opacity(0.25) : Color.white.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering.wrappedValue = $0 }
    }
}

/// Progress bar showing story progress and position
struct TVProgressBar: View {
    let progress: Double
    let totalStories: Int
    let currentIndex: Int

    var body: some View {
        VStack(spacing: 0) {
            // Story segments
            HStack(spacing: 3) {
                ForEach(0..<totalStories, id: \.self) { index in
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.white.opacity(0.2))

                            // Progress fill
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.white.opacity(0.9))
                                .frame(width: progressWidth(for: index, totalWidth: geo.size.width))
                        }
                    }
                    .frame(height: 3)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 60)
            .offset(y: -20)
        )
    }

    private func progressWidth(for index: Int, totalWidth: CGFloat) -> CGFloat {
        if index < currentIndex {
            return totalWidth // Completed
        } else if index == currentIndex {
            return totalWidth * progress // Current
        } else {
            return 0 // Upcoming
        }
    }
}

// MARK: - Keyboard Shortcut Help Overlay

struct TVKeyboardHelp: View {
    @Binding var isVisible: Bool

    private let shortcuts: [(key: String, description: String)] = [
        ("Space", "Play / Pause"),
        ("← →", "Previous / Next Story"),
        ("Esc", "Exit TV View"),
    ]

    var body: some View {
        if isVisible {
            VStack(spacing: 16) {
                Text("KEYBOARD SHORTCUTS")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.6))

                VStack(spacing: 10) {
                    ForEach(shortcuts, id: \.key) { shortcut in
                        HStack {
                            Text(shortcut.key)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                                .frame(width: 60, alignment: .trailing)

                            Text(shortcut.description)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.8))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black

        VStack {
            TVControlBar(
                isPlaying: true,
                currentIndex: 2,
                totalStories: 10,
                onPlayPause: {},
                onPrevious: {},
                onNext: {},
                onClose: {}
            )

            Spacer()

            TVProgressBar(
                progress: 0.65,
                totalStories: 10,
                currentIndex: 2
            )
        }
    }
    .frame(width: 1000, height: 600)
}
