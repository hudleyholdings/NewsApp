import XCTest
@testable import NewsApp

final class ReaderHTMLSanitizerTests: XCTestCase {
    func testRemovesInlineMediaAndObjectPlaceholders() {
        let html = """
        <p>Lead text <img src="https://example.com/image.jpg"> continues.\u{FFFC}</p>
        <figure>
          <picture><source srcset="image.webp"><img src="image.jpg"></picture>
          <figcaption>Image caption</figcaption>
        </figure>
        <object data="movie.swf"></object>
        <p>Body text remains.</p>
        """

        let sanitized = ReaderHTMLSanitizer.sanitizeFragment(html)

        XCTAssertTrue(sanitized.contains("Lead text"))
        XCTAssertTrue(sanitized.contains("Body text remains."))
        XCTAssertFalse(sanitized.localizedCaseInsensitiveContains("<img"))
        XCTAssertFalse(sanitized.localizedCaseInsensitiveContains("<picture"))
        XCTAssertFalse(sanitized.localizedCaseInsensitiveContains("<figure"))
        XCTAssertFalse(sanitized.localizedCaseInsensitiveContains("<object"))
        XCTAssertFalse(sanitized.contains("\u{FFFC}"))
    }

    func testStringSanitizerRemovesObjectReplacementCharacter() {
        XCTAssertEqual("before\u{FFFC}after".sanitizingProblematicCharacters(), "beforeafter")
    }
}
