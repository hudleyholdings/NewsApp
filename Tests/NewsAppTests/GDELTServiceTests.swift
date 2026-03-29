import XCTest
@testable import NewsApp

final class GDELTServiceTests: XCTestCase {
    func testBuildQueryIncludesSegments() {
        let service = GDELTService()
        let config = GDELTSourceConfig(
            query: "climate",
            topic: .science,
            language: .english,
            country: "us",
            timeWindow: .sixHours,
            domain: "cnn.com",
            maxRecords: 100
        )

        let query = service.buildQuery(config: config)
        XCTAssertEqual(query, "science climate sourcelang:eng sourcecountry:US domain:cnn.com")
    }

    func testBuildURLIncludesParams() throws {
        let service = GDELTService()
        let config = GDELTSourceConfig(
            query: "economy",
            topic: .markets,
            language: .english,
            country: nil,
            timeWindow: .twelveHours,
            domain: nil,
            maxRecords: 120
        )

        let url = try service.buildURL(config: config)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["mode"], "ArtList")
        XCTAssertEqual(items["format"], "json")
        XCTAssertEqual(items["maxrecords"], "120")
        XCTAssertEqual(items["timespan"], "12h")
    }

    func testEntriesFromResponse() throws {
        let service = GDELTService()
        let payload = """
        {"articles":[{"url":"https://example.com/a","url_mobile":"","title":"Hello","seendate":"20260107T153000Z","socialimage":"https://example.com/img.jpg","domain":"example.com","language":"English","sourcecountry":"United States"}]}
        """
        let response = try JSONDecoder().decode(GDELTResponse.self, from: Data(payload.utf8))
        let entries = service.entries(from: response)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.externalID, "https://example.com/a")
        XCTAssertEqual(entries.first?.imageURL, "https://example.com/img.jpg")
        XCTAssertNotNil(entries.first?.publishedAt)
    }
}
