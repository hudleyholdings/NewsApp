import SwiftUI

/// TV View - CNN/BBC/PBS NewsHour style news presentation
struct TVView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var settings: SettingsStore
    @Binding var isPresented: Bool

    @StateObject private var viewModel = TVViewModel()
    @State private var showControls = false
    @State private var controlsTimer: Timer?
    @State private var currentImage: NSImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black
                    .ignoresSafeArea()

                if viewModel.articles.isEmpty {
                    emptyState
                } else {
                    // Main story display
                    storyView(geometry: geometry)

                    // Lower third at bottom with title-safe margins
                    VStack {
                        Spacer()

                        if let article = viewModel.currentArticle {
                            LowerThirdView(
                                article: article,
                                source: feedStore.feedName(for: article.feedID) ?? "News",
                                category: feedStore.feedCategory(for: article.feedID),
                                faviconURL: feedStore.feeds.first(where: { $0.id == article.feedID })?.iconURL,
                                accentColor: feedAccentColor(for: article.feedID),
                                isVisible: viewModel.showLowerThird,
                                showProgress: settings.tvShowProgress,
                                progress: viewModel.storyProgress,
                                totalStories: viewModel.articles.count,
                                currentIndex: viewModel.currentIndex
                            )
                        }
                    }

                    // Control bar (shows on mouse movement)
                    if showControls {
                        TVControlBar(
                            isPlaying: viewModel.isPlaying,
                            currentIndex: viewModel.currentIndex,
                            totalStories: viewModel.articles.count,
                            onPlayPause: { viewModel.togglePlayPause() },
                            onPrevious: { viewModel.previousStory() },
                            onNext: { viewModel.nextStory() },
                            onClose: { isPresented = false }
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .onAppear {
                setupView()
            }
            .onDisappear {
                viewModel.stop()
                controlsTimer?.invalidate()
            }
            .onHover { hovering in
                if hovering {
                    showControlsTemporarily()
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    showControlsTemporarily()
                case .ended:
                    break
                }
            }
            .focusable()
            .onKeyPress(.escape) {
                isPresented = false
                return .handled
            }
            .onKeyPress(.space) {
                viewModel.togglePlayPause()
                showControlsTemporarily()
                return .handled
            }
            .onKeyPress(.leftArrow) {
                viewModel.previousStory()
                showControlsTemporarily()
                return .handled
            }
            .onKeyPress(.rightArrow) {
                viewModel.nextStory()
                showControlsTemporarily()
                return .handled
            }
        }
        .preferredColorScheme(.dark) // TV view always dark for cinematic feel
    }

    // MARK: - Story View

    @ViewBuilder
    private func storyView(geometry: GeometryProxy) -> some View {
        if let article = viewModel.currentArticle {
            ZStack {
                // Image with Ken Burns effect - full screen, no heavy overlays
                KenBurnsImage(
                    article: article,
                    effect: viewModel.currentEffect,
                    duration: Double(settings.tvStoryDuration),
                    enabled: settings.tvKenBurnsEnabled,
                    geometry: geometry
                )
                .id(article.id) // Force recreation on article change

                // Subtle vignette for cinematic feel (doesn't obscure image)
                RadialGradient(
                    colors: [Color.clear, Color.black.opacity(0.3)],
                    center: .center,
                    startRadius: geometry.size.width * 0.3,
                    endRadius: geometry.size.width * 0.8
                )
                .allowsHitTesting(false)
            }
            .transition(.opacity)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "tv")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No Stories Available")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("Add some feeds to watch the news")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            Button("Close") {
                isPresented = false
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Helpers

    private func setupView() {
        let articles = feedStore.sortedArticles(for: feedStore.selectedSidebarItem)
            .filter { $0.imageURL != nil } // Only show articles with images for TV view

        viewModel.configure(
            articles: Array(articles.prefix(50)), // Limit for performance
            storyDuration: settings.tvStoryDuration,
            autoplay: settings.tvAutoplay
        )
        viewModel.start()

        // Initial controls show
        showControlsTemporarily()
    }

    private func showControlsTemporarily() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls = true
        }

        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [self] _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.3)) {
                    showControls = false
                }
            }
        }
    }

    private func feedAccentColor(for feedID: UUID) -> Color {
        // Generate a consistent color based on feed ID
        let hash = feedID.hashValue
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.7, brightness: 0.8)
    }
}

// MARK: - TV View Model

@MainActor
final class TVViewModel: ObservableObject {
    @Published var articles: [Article] = []
    @Published var currentIndex = 0
    @Published var isPlaying = false
    @Published var storyProgress: Double = 0
    @Published var showLowerThird = false
    @Published var currentEffect: KenBurnsEffect = .zoomIn

    private var storyDuration: Int = 20
    private var progressTimer: Timer?
    private var autoplay = true

    var currentArticle: Article? {
        guard currentIndex >= 0 && currentIndex < articles.count else { return nil }
        return articles[currentIndex]
    }

    func configure(articles: [Article], storyDuration: Int, autoplay: Bool) {
        self.articles = articles
        self.storyDuration = storyDuration
        self.autoplay = autoplay
        self.currentIndex = 0
        self.currentEffect = selectEffect(for: 0)
    }

    func start() {
        guard !articles.isEmpty else { return }
        isPlaying = autoplay
        showLowerThird = false
        storyProgress = 0

        // Animate in lower third after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.4)) {
                self.showLowerThird = true
            }
        }

        if autoplay {
            startProgressTimer()
        }
    }

    func stop() {
        progressTimer?.invalidate()
        progressTimer = nil
        isPlaying = false
    }

    func togglePlayPause() {
        isPlaying.toggle()
        if isPlaying {
            startProgressTimer()
        } else {
            progressTimer?.invalidate()
        }
    }

    func nextStory() {
        guard !articles.isEmpty else { return }
        transitionTo(index: (currentIndex + 1) % articles.count)
    }

    func previousStory() {
        guard !articles.isEmpty else { return }
        let newIndex = currentIndex > 0 ? currentIndex - 1 : articles.count - 1
        transitionTo(index: newIndex)
    }

    private func transitionTo(index: Int) {
        // Hide lower third
        withAnimation(.easeIn(duration: 0.2)) {
            showLowerThird = false
        }

        // Short delay then change story
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.5)) {
                self.currentIndex = index
                self.currentEffect = self.selectEffect(for: index)
                self.storyProgress = 0
            }

            // Show new lower third
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeOut(duration: 0.4)) {
                    self.showLowerThird = true
                }
            }

            // Restart timer if playing
            if self.isPlaying {
                self.startProgressTimer()
            }
        }
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        let interval = 0.05 // 50ms updates for smooth progress
        let increment = interval / Double(storyDuration)

        progressTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.storyProgress += increment
                if self.storyProgress >= 1.0 {
                    self.nextStory()
                }
            }
        }
    }

    private func selectEffect(for index: Int) -> KenBurnsEffect {
        // Cycle through effects for variety
        let effects: [KenBurnsEffect] = [.zoomIn, .panLeft, .zoomOut, .panRight, .diagonal, .panUp]
        return effects[index % effects.count]
    }
}

// MARK: - Preview

#Preview {
    Text("TV View Preview")
        .frame(width: 800, height: 600)
}
