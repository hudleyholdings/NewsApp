import SwiftUI

/// Modern cinematic effects for TV-style image animation
enum CinematicEffect: CaseIterable {
    case zoomIn          // Classic Ken Burns zoom in
    case zoomOut         // Classic Ken Burns zoom out
    case panLeft         // Horizontal pan left
    case panRight        // Horizontal pan right
    case panUp           // Vertical pan up
    case panDown         // Vertical pan down
    case diagonal        // Diagonal movement with zoom
    case driftFloat      // Slow floating drift
    case parallaxDepth   // Subtle 3D parallax feel
    case epicZoom        // Dramatic slow zoom
    case cornerPan       // Pan from corner to corner

    /// Starting transform values
    var startState: CinematicState {
        switch self {
        case .zoomIn:
            return CinematicState(scale: 1.0, offsetX: 0, offsetY: 0, rotation: 0)
        case .zoomOut:
            return CinematicState(scale: 1.15, offsetX: 0, offsetY: 0, rotation: 0)
        case .panLeft:
            return CinematicState(scale: 1.1, offsetX: 0.06, offsetY: 0, rotation: 0)
        case .panRight:
            return CinematicState(scale: 1.1, offsetX: -0.06, offsetY: 0, rotation: 0)
        case .panUp:
            return CinematicState(scale: 1.1, offsetX: 0, offsetY: 0.05, rotation: 0)
        case .panDown:
            return CinematicState(scale: 1.1, offsetX: 0, offsetY: -0.05, rotation: 0)
        case .diagonal:
            return CinematicState(scale: 1.0, offsetX: -0.04, offsetY: -0.04, rotation: 0)
        case .driftFloat:
            return CinematicState(scale: 1.08, offsetX: -0.02, offsetY: 0.02, rotation: -0.3)
        case .parallaxDepth:
            return CinematicState(scale: 1.0, offsetX: 0.03, offsetY: 0, rotation: 0)
        case .epicZoom:
            return CinematicState(scale: 1.0, offsetX: 0, offsetY: 0, rotation: 0)
        case .cornerPan:
            return CinematicState(scale: 1.12, offsetX: -0.05, offsetY: -0.04, rotation: 0)
        }
    }

    /// Ending transform values
    var endState: CinematicState {
        switch self {
        case .zoomIn:
            return CinematicState(scale: 1.15, offsetX: 0, offsetY: 0, rotation: 0)
        case .zoomOut:
            return CinematicState(scale: 1.0, offsetX: 0, offsetY: 0, rotation: 0)
        case .panLeft:
            return CinematicState(scale: 1.1, offsetX: -0.06, offsetY: 0, rotation: 0)
        case .panRight:
            return CinematicState(scale: 1.1, offsetX: 0.06, offsetY: 0, rotation: 0)
        case .panUp:
            return CinematicState(scale: 1.1, offsetX: 0, offsetY: -0.05, rotation: 0)
        case .panDown:
            return CinematicState(scale: 1.1, offsetX: 0, offsetY: 0.05, rotation: 0)
        case .diagonal:
            return CinematicState(scale: 1.15, offsetX: 0.04, offsetY: 0.04, rotation: 0)
        case .driftFloat:
            return CinematicState(scale: 1.08, offsetX: 0.02, offsetY: -0.02, rotation: 0.3)
        case .parallaxDepth:
            return CinematicState(scale: 1.12, offsetX: -0.03, offsetY: 0, rotation: 0)
        case .epicZoom:
            return CinematicState(scale: 1.25, offsetX: 0, offsetY: -0.02, rotation: 0)
        case .cornerPan:
            return CinematicState(scale: 1.12, offsetX: 0.05, offsetY: 0.04, rotation: 0)
        }
    }
}

/// State for cinematic animation
struct CinematicState {
    let scale: CGFloat
    let offsetX: CGFloat  // As percentage of width
    let offsetY: CGFloat  // As percentage of height
    let rotation: CGFloat // Degrees

    func interpolate(to end: CinematicState, progress: CGFloat) -> CinematicState {
        // Use eased progress for smoother motion
        let easedProgress = easeInOutCubic(progress)
        return CinematicState(
            scale: scale + (end.scale - scale) * easedProgress,
            offsetX: offsetX + (end.offsetX - offsetX) * easedProgress,
            offsetY: offsetY + (end.offsetY - offsetY) * easedProgress,
            rotation: rotation + (end.rotation - rotation) * easedProgress
        )
    }

    private func easeInOutCubic(_ t: CGFloat) -> CGFloat {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
}

// Type alias for backwards compatibility
typealias KenBurnsEffect = CinematicEffect
typealias KenBurnsState = CinematicState

/// Animated image with cinematic Ken Burns and modern effects
struct KenBurnsImage: View {
    let article: Article
    let effect: CinematicEffect
    let duration: Double
    let enabled: Bool
    let geometry: GeometryProxy

    @State private var image: NSImage?
    @State private var animationProgress: CGFloat = 0
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Placeholder background
            Color.black

            if let image = image {
                imageView(image: image)
                    .onAppear {
                        // Start animation when image appears
                        if enabled && !isAnimating {
                            startAnimation()
                        }
                    }
            } else {
                loadingPlaceholder
            }
        }
        .task(id: article.id) {
            // Reset animation state for new article
            animationProgress = 0
            isAnimating = false
            await loadImage()
        }
        .onChange(of: image) { _, newImage in
            // Start animation when image loads
            if newImage != nil && enabled && !isAnimating {
                startAnimation()
            }
        }
    }

    // MARK: - Image View

    private func imageView(image: NSImage) -> some View {
        let viewSize = geometry.size
        let imgSize = image.size

        // Calculate how to fill the screen while respecting aspect ratio
        let imageAspect = imgSize.width / imgSize.height
        let viewAspect = viewSize.width / viewSize.height

        // Determine base scale to fill the view (with extra margin for effects)
        let baseScale: CGFloat = imageAspect > viewAspect
            ? viewSize.height / imgSize.height
            : viewSize.width / imgSize.width

        let scaledWidth = imgSize.width * baseScale
        let scaledHeight = imgSize.height * baseScale

        // Current animation state
        let currentState: CinematicState = enabled
            ? effect.startState.interpolate(to: effect.endState, progress: animationProgress)
            : CinematicState(scale: 1.05, offsetX: 0, offsetY: 0, rotation: 0)

        // Apply cinematic transforms
        return Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: scaledWidth, height: scaledHeight)
            .scaleEffect(currentState.scale)
            .rotationEffect(.degrees(currentState.rotation))
            .offset(
                x: scaledWidth * currentState.offsetX,
                y: scaledHeight * currentState.offsetY
            )
            .frame(width: viewSize.width, height: viewSize.height)
            .clipped()
    }

    // MARK: - Loading Placeholder

    private var loadingPlaceholder: some View {
        ZStack {
            // Dark gradient background
            LinearGradient(
                colors: [Color(white: 0.15), Color(white: 0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle loading indicator
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white.opacity(0.4))
        }
    }

    // MARK: - Image Loading

    private func loadImage() async {
        // Reset for new image
        self.image = nil

        guard let url = article.imageURL else { return }

        // Check shared cache first
        if let cached = ImagePrefetcher.shared.image(for: url) {
            self.image = cached
            return
        }

        // Load from URL
        if let loadedImage = await ImagePrefetcher.shared.loadImage(for: url) {
            withAnimation(.easeIn(duration: 0.4)) {
                self.image = loadedImage
            }
        }
    }

    // MARK: - Animation

    private func startAnimation() {
        guard enabled else { return }

        isAnimating = true
        animationProgress = 0

        // Animate over the story duration with smooth timing
        withAnimation(.linear(duration: duration)) {
            animationProgress = 1.0
        }
    }
}

// MARK: - Effect Selection Helper

extension CinematicEffect {
    /// Select a varied effect based on index for visual interest
    static func selectFor(index: Int) -> CinematicEffect {
        let allEffects: [CinematicEffect] = [
            .zoomIn, .panLeft, .epicZoom, .panRight,
            .driftFloat, .zoomOut, .diagonal, .parallaxDepth,
            .panUp, .cornerPan, .panDown
        ]
        return allEffects[index % allEffects.count]
    }

    /// Select effect appropriate for image aspect ratio
    static func selectFor(imageSize: CGSize, index: Int) -> CinematicEffect {
        let aspectRatio = imageSize.width / imageSize.height
        let variation = index % 6

        if aspectRatio > 1.6 {
            // Wide/panoramic - horizontal movements
            let wideEffects: [CinematicEffect] = [.panLeft, .panRight, .driftFloat, .cornerPan, .parallaxDepth, .epicZoom]
            return wideEffects[variation]
        } else if aspectRatio < 0.8 {
            // Tall/portrait - vertical movements
            let tallEffects: [CinematicEffect] = [.panUp, .panDown, .zoomIn, .zoomOut, .epicZoom, .diagonal]
            return tallEffects[variation]
        } else {
            // Standard - mix of effects
            return selectFor(index: index)
        }
    }
}

#Preview {
    GeometryReader { geo in
        ZStack {
            Color.black
            Text("Cinematic Effects Preview")
                .foregroundStyle(.white)
        }
    }
    .frame(width: 800, height: 450)
}
