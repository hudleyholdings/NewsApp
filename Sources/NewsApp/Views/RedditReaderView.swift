import SwiftUI
import AppKit

/// Custom reader for Reddit posts. The RSS body Reddit ships is a `<table>` with
/// a thumbnail and `[link]` / `[comments]` anchors — rendered raw it looks awful
/// (huge empty space below the image, plus literal `[link] [comments]` markup at
/// the bottom). This view extracts those bits and lays them out properly.
///
/// Triggered when `Article.isRedditArticle` is true.
struct RedditReaderView: View {
    let article: Article
    let metadata: RedditPostMetadata
    let maxWidth: CGFloat?
    let isExpanded: Bool
    @Environment(\.openURL) private var openURL
    @State private var imageHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                titleBlock
                bylineRow

                if let imageURL = metadata.thumbnailURL {
                    RedditPostImage(url: imageURL, targetLink: metadata.externalLinkURL ?? article.link)
                        .frame(maxWidth: .infinity)
                }

                if let bodyHTML = metadata.cleanedBodyHTML, !bodyHTML.isEmpty {
                    Text(bodyHTML.strippingHTML().decodingHTMLEntities())
                        .font(.system(size: 14))
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                actionRow
            }
            .padding(.horizontal, isExpanded ? 32 : 24)
            .padding(.vertical, 20)
            .frame(maxWidth: contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var contentMaxWidth: CGFloat {
        if isExpanded {
            // In fullscreen mode, prefer a wider but still readable column so the
            // post sits centered instead of pinned to the leading edge.
            return max(maxWidth ?? 900, 700)
        }
        return max(maxWidth ?? 720, 480)
    }

    private var titleBlock: some View {
        Text(article.title)
            .font(.system(size: 22, weight: .semibold))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var bylineRow: some View {
        HStack(spacing: 8) {
            if let subreddit = metadata.subreddit {
                SubredditBadge(name: subreddit)
            }
            if let submitter = metadata.submitterUsername {
                Text("by")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("u/\(submitter)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.9))
            }
            if let publishedAt = article.publishedAt {
                Text("•")
                    .foregroundStyle(.secondary)
                Text(publishedAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            if let link = metadata.externalLinkURL, link != metadata.commentsURL {
                Button {
                    openURL(link)
                } label: {
                    Label("Open Link", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
            }
            if let comments = metadata.commentsURL {
                Button {
                    openURL(comments)
                } label: {
                    Label("View Comments", systemImage: "bubble.left.and.bubble.right")
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }
}

private struct SubredditBadge: View {
    let name: String

    var body: some View {
        Text("r/\(name)")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.orange))
    }
}

/// Image with constrained max height + tap-to-open behaviour. Reddit's RSS
/// thumbnails are often tiny — we let them render at natural size up to a cap,
/// instead of stretching them across the reader pane.
private struct RedditPostImage: View {
    let url: URL
    let targetLink: URL?
    @Environment(\.openURL) private var openURL
    @State private var image: NSImage?
    @State private var didLoad = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 480)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let targetLink {
                            openURL(targetLink)
                        }
                    }
                    .help(targetLink.map { "Open \($0.absoluteString)" } ?? "Open image")
            } else if didLoad {
                EmptyView()
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(height: 160)
                    .overlay(ProgressView().controlSize(.small))
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        if let cached = ImagePrefetcher.shared.image(for: url) {
            image = cached
            didLoad = true
            return
        }
        if let loaded = await ImagePrefetcher.shared.loadImage(for: url) {
            image = loaded
        }
        didLoad = true
    }
}
