import SwiftUI
import WebKit
import AppKit

/// Custom reader view for YouTube videos. The header (rendered by `ReaderHeader`
/// in `ReaderView`) already shows the title, channel, and date — this view focuses
/// on the player, the video description, and an Open-on-YouTube button.
///
/// In expanded (fullscreen) mode the player widens to fill most of the viewport
/// and centers under the header.
struct YouTubeReaderView: View {
    let article: Article
    let videoID: String
    /// Optional channel name. Only rendered when distinct from the article's source
    /// (rare — usually they match and the header already shows it).
    let channelName: String?
    /// SwiftUI maxWidth threaded down from `ReaderView`; nil means "as wide as
    /// the pane is". Expanded reader passes a larger ceiling so the player can
    /// breathe across the whole window.
    let maxWidth: CGFloat?
    let isExpanded: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                YouTubeEmbedPlayer(videoID: videoID)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                if let body = descriptionText, !body.isEmpty {
                    Text(body)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    if let link = article.link {
                        Button {
                            openURL(link)
                        } label: {
                            Label("Open on YouTube", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(.bordered)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, isExpanded ? 32 : 24)
            .padding(.vertical, 20)
            .frame(maxWidth: contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var contentMaxWidth: CGFloat {
        if isExpanded {
            // Wide center column in fullscreen — most modern displays give us
            // 1200+ to play with; 1100 keeps the video readable without dragging
            // the user's eye across the whole screen.
            return max(maxWidth ?? 1100, 900)
        }
        return max(maxWidth ?? 720, 480)
    }

    /// RSS description text. We deliberately do NOT fall back to `contentText`
    /// because the reader extractor scrapes youtube.com (which is JS-driven) and
    /// usually returns just the site footer ("About Press Copyright Contact…").
    private var descriptionText: String? {
        guard let summary = article.summary, !summary.isEmpty else { return nil }
        return summary
    }
}

/// `WKWebView` hosting the YouTube embed iframe. Privacy-enhanced
/// `youtube-nocookie.com/embed` keeps Google's third-party cookies out of the app.
///
/// The embed is loaded with `enablejsapi=1` so we can postMessage `pauseVideo`
/// to it when the host view goes away — without this, switching to the
/// fullscreen reader or jumping to a different article would leave the iframe
/// playing audio in the background with no UI affordance to stop it.
private struct YouTubeEmbedPlayer: NSViewRepresentable {
    let videoID: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // YouTube's iframe player runs JS for playback controls.
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Persistent store so the player remembers volume / preferred quality
        // across video switches in the same session.
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        loadVideo(into: webView)
        context.coordinator.bindPauseNotifications(for: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Reload only if the video changed — otherwise pressing pause / scrubbing
        // would reset on every parent re-render.
        if context.coordinator.lastLoadedVideoID != videoID {
            // Stop the previous video first so its audio doesn't briefly
            // overlap the new one's load.
            Self.pause(webView)
            loadVideo(into: webView)
            context.coordinator.lastLoadedVideoID = videoID
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        // The web view leaves the SwiftUI hierarchy but isn't guaranteed to be
        // released immediately — without this, the embedded YouTube player can
        // keep playing audio in the background after the host view disappears.
        pause(webView)
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        let coord = Coordinator()
        coord.lastLoadedVideoID = videoID
        return coord
    }

    @MainActor
    private func loadVideo(into webView: WKWebView) {
        let embedURL = "https://www.youtube-nocookie.com/embed/\(videoID)?rel=0&modestbranding=1&playsinline=1&enablejsapi=1"
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <style>
            html, body { margin: 0; padding: 0; background: #000; height: 100%; }
            .frame-wrap { position: relative; width: 100%; height: 100%; }
            iframe { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; }
        </style>
        </head>
        <body>
        <div class="frame-wrap">
            <iframe id="ytplayer" src="\(embedURL)"
                allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
                allowfullscreen></iframe>
        </div>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com"))
    }

    /// postMessage `pauseVideo` to the iframe via the YouTube IFrame Player API
    /// command schema (the host page can issue commands by posting JSON to the
    /// iframe's contentWindow). Falls back gracefully if the player hasn't
    /// bootstrapped yet.
    nonisolated static func pause(_ webView: WKWebView) {
        let script = """
        (function() {
            try {
                var f = document.getElementById('ytplayer');
                if (f && f.contentWindow) {
                    f.contentWindow.postMessage(JSON.stringify({event:'command', func:'pauseVideo', args:[]}), '*');
                    f.contentWindow.postMessage(JSON.stringify({event:'command', func:'stopVideo', args:[]}), '*');
                }
            } catch (e) {}
        })();
        """
        Task { @MainActor in
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    final class Coordinator {
        var lastLoadedVideoID: String?
        private var pauseObserver: NSObjectProtocol?

        deinit {
            if let pauseObserver { NotificationCenter.default.removeObserver(pauseObserver) }
        }

        /// Listen for the global "pause all YouTube players" broadcast. Posted by
        /// `MainSplitView` whenever the article changes or the fullscreen reader
        /// toggles, so an off-screen player can't keep blasting audio.
        func bindPauseNotifications(for webView: WKWebView) {
            if let pauseObserver { NotificationCenter.default.removeObserver(pauseObserver) }
            pauseObserver = NotificationCenter.default.addObserver(
                forName: .pauseAllYouTubePlayers,
                object: nil,
                queue: .main
            ) { [weak webView] _ in
                guard let webView else { return }
                YouTubeEmbedPlayer.pause(webView)
            }
        }
    }
}

extension Notification.Name {
    /// Broadcast whenever any YouTube embed in the app should stop playback —
    /// e.g. user switched articles, toggled fullscreen, or closed the reader.
    /// All `YouTubeEmbedPlayer` instances listen and pause themselves on receipt.
    static let pauseAllYouTubePlayers = Notification.Name("pauseAllYouTubePlayers")
}
