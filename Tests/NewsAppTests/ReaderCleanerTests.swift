import XCTest
@testable import NewsApp

final class ReaderCleanerTests: XCTestCase {
    private let key = "readerCleanupEnabled"

    func testCleanupDefaultsToEnabledWhenPreferenceIsMissing() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: key)
        defaults.removeObject(forKey: key)
        defer { restore(previous) }

        let cleaned = ReaderCleaner.clean("Sign in to save this story\n\nThe actual article body stays here.")

        XCTAssertEqual(cleaned, "The actual article body stays here.")
    }

    func testCleanupCanBeDisabled() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: key)
        defaults.set(false, forKey: key)
        defer { restore(previous) }

        let input = "Sign in to save this story\n\nThe actual article body stays here."

        XCTAssertEqual(ReaderCleaner.clean(input), input)
    }

    private func restore(_ value: Any?) {
        let defaults = UserDefaults.standard
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
