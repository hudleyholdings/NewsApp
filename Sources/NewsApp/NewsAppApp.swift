import SwiftUI
import AppKit

@main
struct NewsAppApp: App {
    @StateObject private var feedStore = FeedStore()
    @StateObject private var settings = SettingsStore()

    var body: some Scene {
        WindowGroup {
            Group {
                if settings.hasCompletedOnboarding {
                    MainSplitView()
                        .background(WindowAccessor())
                } else {
                    WelcomeView()
                }
            }
            .environmentObject(feedStore)
            .environmentObject(settings)
            .preferredColorScheme(settings.colorScheme)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1320, height: 860)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            NewsCommands()
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
        }
    }
}

// MARK: - Window Accessor (persists toolbar config across view changes)

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowConfigView {
        WindowConfigView()
    }

    func updateNSView(_ nsView: WindowConfigView, context: Context) {
        nsView.applyConfiguration()
    }

    class WindowConfigView: NSView {
        nonisolated(unsafe) private var updateObserver: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                applyConfiguration()
                startEnforcement()
            } else {
                stopEnforcement()
            }
        }

        override func layout() {
            super.layout()
            applyConfiguration()
        }

        private func startEnforcement() {
            stopEnforcement()
            guard let window = window else { return }

            // NSWindow.didUpdateNotification fires during toolbar rebuilds
            updateObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didUpdateNotification, object: window, queue: .main
            ) { [weak self] _ in self?.applyConfiguration() }
        }

        private func stopEnforcement() {
            if let obs = updateObserver {
                NotificationCenter.default.removeObserver(obs)
                updateObserver = nil
            }
        }

        func applyConfiguration() {
            guard let window = window else { return }
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .line
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            if let toolbar = window.toolbar {
                toolbar.isVisible = true
                for item in toolbar.items where item.isBordered {
                    item.isBordered = false
                }
            }
        }

        deinit {
            if let obs = updateObserver {
                NotificationCenter.default.removeObserver(obs)
            }
        }
    }
}
