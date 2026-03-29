import Foundation
import WebKit

@MainActor
final class ContentBlockerStore: ObservableObject {
    static let shared = ContentBlockerStore()

    @Published private(set) var ruleList: WKContentRuleList?

    func load() async {
        guard ruleList == nil else { return }
        guard let url = Bundle.module.url(forResource: "ContentBlocker", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rules = String(data: data, encoding: .utf8) else {
            return
        }

        do {
            let compiled = try await compileRules(identifier: "NewsAppContentBlocker", rules: rules)
            ruleList = compiled
        } catch {
            ruleList = nil
        }
    }

    private func compileRules(identifier: String, rules: String) async throws -> WKContentRuleList {
        try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: rules) { list, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let list = list {
                    continuation.resume(returning: list)
                } else {
                    continuation.resume(throwing: URLError(.cannotParseResponse))
                }
            }
        }
    }
}
