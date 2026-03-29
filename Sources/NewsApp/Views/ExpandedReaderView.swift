import SwiftUI

struct ExpandedReaderView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var settings: SettingsStore
    @Binding var isExpanded: Bool
    @Binding var showReaderPane: Bool
    @State private var displayModeOverride: ReaderDisplayMode?

    private var displayMode: ReaderDisplayMode {
        displayModeOverride ?? settings.defaultReaderMode
    }

    var body: some View {
        GeometryReader { geometry in
            let viewportWidth = geometry.size.width
            // Add margins when viewport exceeds threshold
            let horizontalMargin: CGFloat = viewportWidth > 1200 ? max(0, (viewportWidth - 900) / 2) : 0

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    if feedStore.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }

                    SettingsLink(label: {
                        Label("Settings", systemImage: "gearshape")
                    })

                    Spacer()

                    // Reader/Web toggle moved here
                    Picker("", selection: Binding(
                        get: { displayMode },
                        set: { displayModeOverride = $0 }
                    )) {
                        ForEach(ReaderDisplayMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 120)

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isExpanded = false
                        }
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Return to three-pane view")

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isExpanded = false
                            showReaderPane = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Hide reader")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.thinMaterial)

                ReaderView(
                    isExpanded: true,
                    expandedMargin: horizontalMargin,
                    modeOverride: $displayModeOverride
                )
            }
            .focusable()
            .onKeyPress { key in
                switch key.key {
                case .escape:
                    withAnimation(.easeInOut(duration: 0.25)) { isExpanded = false }
                    return .handled
                case .upArrow:
                    feedStore.navigateArticle(direction: -1)
                    return .handled
                case .downArrow:
                    feedStore.navigateArticle(direction: 1)
                    return .handled
                default:
                    break
                }
                let char = key.characters.lowercased()
                switch char {
                case "k":
                    feedStore.navigateArticle(direction: -1)
                    return .handled
                case "j":
                    feedStore.navigateArticle(direction: 1)
                    return .handled
                case "s":
                    feedStore.toggleStarCurrentArticle()
                    return .handled
                case "u":
                    feedStore.toggleReadCurrentArticle()
                    return .handled
                case "o":
                    feedStore.openCurrentArticleInBrowser()
                    return .handled
                default:
                    return .ignored
                }
            }
        }
    }
}
