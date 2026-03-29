import SwiftUI

struct NewsCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Add Feed") {
                NotificationCenter.default.post(name: .openFeedManager, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandGroup(after: .sidebar) {
            Button("Refresh All") {
                NotificationCenter.default.post(name: .refreshAllFeeds, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command])
        }

        CommandGroup(after: .textFormatting) {
            Button("Increase Font Size") {
                NotificationCenter.default.post(name: .increaseFontSize, object: nil)
            }
            .keyboardShortcut("+", modifiers: [.command])

            Button("Decrease Font Size") {
                NotificationCenter.default.post(name: .decreaseFontSize, object: nil)
            }
            .keyboardShortcut("-", modifiers: [.command])
        }
    }
}

extension Notification.Name {
    static let openFeedManager = Notification.Name("openFeedManager")
    static let refreshAllFeeds = Notification.Name("refreshAllFeeds")
    static let increaseFontSize = Notification.Name("increaseFontSize")
    static let decreaseFontSize = Notification.Name("decreaseFontSize")
    static let scrollReader = Notification.Name("scrollReader")
}
