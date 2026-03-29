import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    let url: URL?
    let blockAds: Bool
    let userAgent: String?
    let persistentSession: Bool
    var onScroll: ((CGFloat) -> Void)?

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let webView = makeWebView()
        context.coordinator.webView = webView
        context.coordinator.currentMode = (persistentSession, blockAds, userAgent)
        context.coordinator.onScroll = onScroll
        context.coordinator.observeScroll(in: webView)
        context.coordinator.observeReaderScroll()
        container.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let signature = (persistentSession, blockAds, userAgent)
        context.coordinator.onScroll = onScroll
        if context.coordinator.currentMode != signature {
            context.coordinator.currentMode = signature
            replaceWebView(in: nsView, coordinator: context.coordinator)
        }

        guard let webView = context.coordinator.webView else { return }
        if let url = url, webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = persistentSession ? .default() : .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = userAgent
        webView.allowsBackForwardNavigationGestures = true
        if blockAds, let ruleList = ContentBlockerStore.shared.ruleList {
            webView.configuration.userContentController.add(ruleList)
        }
        return webView
    }

    @MainActor
    private func replaceWebView(in container: NSView, coordinator: Coordinator) {
        coordinator.webView?.removeFromSuperview()
        let newWebView = makeWebView()
        coordinator.webView = newWebView
        coordinator.observeScroll(in: newWebView)
        container.addSubview(newWebView)
        newWebView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            newWebView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            newWebView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            newWebView.topAnchor.constraint(equalTo: container.topAnchor),
            newWebView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        if let url = url {
            newWebView.load(URLRequest(url: url))
        }
    }
}

@MainActor
final class Coordinator {
    var currentMode: (Bool, Bool, String?) = (false, false, nil)
    weak var webView: WKWebView?
    var onScroll: ((CGFloat) -> Void)?
    private var scrollObserver: NSObjectProtocol?

    // Note: scrollObserver is automatically removed when NotificationCenter deallocates it

    func observeScroll(in webView: WKWebView) {
        if let scrollObserver = scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
        }
        guard let scrollView = findScrollView(in: webView) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.observeScroll(in: webView)
            }
            return
        }
        let contentView = scrollView.contentView
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: contentView,
            queue: .main
        ) { [weak self, weak contentView] _ in
            guard let self, let contentView else { return }
            self.onScroll?(contentView.bounds.origin.y)
        }
        contentView.postsBoundsChangedNotifications = true
    }

    private var readerScrollObserver: NSObjectProtocol?

    func observeReaderScroll() {
        readerScrollObserver = NotificationCenter.default.addObserver(
            forName: .scrollReader, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let webView = self.webView else { return }
            let direction = (note.userInfo?["direction"] as? Int) ?? 1
            let delta = direction * 80
            webView.evaluateJavaScript("window.scrollBy({top: \(delta), behavior: 'smooth'})")
        }
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view.enclosingScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let scrollView = subview as? NSScrollView {
                return scrollView
            }
            if let found = findScrollView(in: subview) {
                return found
            }
        }
        return nil
    }
}
