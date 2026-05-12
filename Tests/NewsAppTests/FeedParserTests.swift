import XCTest
@testable import NewsApp

final class FeedParserTests: XCTestCase {
    func testParsesRSSDateWithNamedTimezoneAndImageEnclosure() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Example Feed</title>
            <item>
              <title>Example Story</title>
              <link>https://example.com/story</link>
              <guid>story-1</guid>
              <description><![CDATA[<p>Summary</p>]]></description>
              <pubDate>Mon, 11 May 2026 15:45:12 GMT</pubDate>
              <enclosure url="https://example.com/image.jpg" type="image/jpeg" />
            </item>
          </channel>
        </rss>
        """

        let result = try FeedParser().parse(data: Data(xml.utf8), url: URL(string: "https://example.com/feed.xml")!)

        XCTAssertEqual(result.title, "Example Feed")
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries.first?.externalID, "story-1")
        XCTAssertEqual(result.entries.first?.imageURL, "https://example.com/image.jpg")
        XCTAssertNotNil(result.entries.first?.publishedAt)
    }

    func testParsesJSONFeedAuthorsAndFractionalDates() throws {
        let json = """
        {
          "version": "https://jsonfeed.org/version/1.1",
          "title": "JSON Example",
          "items": [
            {
              "id": "json-1",
              "url": "https://example.com/json-1",
              "title": "JSON Story",
              "content_text": "Body",
              "authors": [{ "name": "Reporter" }],
              "date_published": "2026-05-11T15:45:12.123Z",
              "banner_image": "https://example.com/banner.jpg"
            }
          ]
        }
        """

        let result = try FeedParser().parse(data: Data(json.utf8), url: URL(string: "https://example.com/feed.json")!)

        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries.first?.author, "Reporter")
        XCTAssertEqual(result.entries.first?.imageURL, "https://example.com/banner.jpg")
        XCTAssertNotNil(result.entries.first?.publishedAt)
    }
}
