import Foundation

struct FeedEntry {
    var externalID: String
    var title: String
    var link: String?
    var summary: String?
    var contentHTML: String?
    var author: String?
    var publishedAt: Date?
    var imageURL: String?
}

struct FeedParseResult {
    var title: String?
    var entries: [FeedEntry]
}

enum FeedParserError: Error {
    case unsupportedFormat
    case invalidData
}

final class FeedParser {
    private let dateParser = FeedDateParser()

    func parse(data: Data, url: URL) throws -> FeedParseResult {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["version"] != nil {
            return parseJSONFeed(json: json)
        }

        let parser = XMLParser(data: data)
        let delegate = FeedXMLParserDelegate(dateParser: dateParser)
        parser.delegate = delegate
        if parser.parse() {
            guard !delegate.entries.isEmpty else {
                throw FeedParserError.invalidData
            }
            return FeedParseResult(title: delegate.feedTitle, entries: delegate.entries)
        }

        throw FeedParserError.unsupportedFormat
    }

    private func parseJSONFeed(json: [String: Any]) -> FeedParseResult {
        let title = json["title"] as? String
        let items = json["items"] as? [[String: Any]] ?? []
        let entries = items.compactMap { item -> FeedEntry? in
            let id = item["id"] as? String ?? item["url"] as? String ?? UUID().uuidString
            let title = item["title"] as? String ?? "Untitled"
            let link = item["url"] as? String
            let summary = item["summary"] as? String
            let contentHTML = item["content_html"] as? String ?? item["content_text"] as? String
            let author = (item["author"] as? [String: Any])?["name"] as? String
            let dateString = item["date_published"] as? String
            let publishedAt = dateString.flatMap { dateParser.parse($0) }
            let imageURL = item["image"] as? String
            return FeedEntry(
                externalID: id,
                title: title,
                link: link,
                summary: summary,
                contentHTML: contentHTML,
                author: author,
                publishedAt: publishedAt,
                imageURL: imageURL
            )
        }
        return FeedParseResult(title: title, entries: entries)
    }
}

final class FeedXMLParserDelegate: NSObject, XMLParserDelegate {
    private let dateParser: FeedDateParser
    private(set) var entries: [FeedEntry] = []
    private(set) var feedTitle: String?

    private var currentText: String = ""
    private var currentEntry: FeedEntry?
    private var currentElement: String = ""
    private var isInItem = false
    private var isInEntry = false

    init(dateParser: FeedDateParser) {
        self.dateParser = dateParser
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName.lowercased()
        currentText = ""

        if currentElement == "item" {
            isInItem = true
            currentEntry = FeedEntry(externalID: "", title: "Untitled", link: nil, summary: nil, contentHTML: nil, author: nil, publishedAt: nil, imageURL: nil)
        } else if currentElement == "entry" {
            isInEntry = true
            currentEntry = FeedEntry(externalID: "", title: "Untitled", link: nil, summary: nil, contentHTML: nil, author: nil, publishedAt: nil, imageURL: nil)
        }

        if isInItem || isInEntry {
            if currentElement == "link" {
                if let href = attributeDict["href"], attributeDict["rel"] != "self" {
                    currentEntry?.link = href
                }
            }
            if currentElement == "enclosure" {
                if let type = attributeDict["type"], type.starts(with: "image"), let url = attributeDict["url"] {
                    currentEntry?.imageURL = url
                }
            }
            if currentElement == "media:content" || currentElement == "media:thumbnail" {
                if let url = attributeDict["url"] {
                    currentEntry?.imageURL = url
                }
            }
            if currentElement == "id" {
                if let value = attributeDict["xml:base"] {
                    currentEntry?.externalID = value
                }
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if isInItem || isInEntry {
            switch name {
            case "title":
                if !text.isEmpty { currentEntry?.title = text }
            case "link":
                if currentEntry?.link == nil, !text.isEmpty { currentEntry?.link = text }
            case "guid", "id":
                if !text.isEmpty { currentEntry?.externalID = text }
            case "description", "summary":
                if !text.isEmpty { currentEntry?.summary = text }
            case "content", "content:encoded":
                if !text.isEmpty { currentEntry?.contentHTML = text }
            case "author", "dc:creator", "name":
                if !text.isEmpty { currentEntry?.author = text }
            case "pubdate", "published", "updated":
                if let date = dateParser.parse(text) { currentEntry?.publishedAt = date }
            default:
                break
            }
        } else if name == "title" {
            if !text.isEmpty { feedTitle = text }
        }

        if name == "item" {
            if var entry = currentEntry {
                if entry.externalID.isEmpty {
                    entry.externalID = entry.link ?? entry.title
                }
                entries.append(entry)
            }
            currentEntry = nil
            isInItem = false
        }

        if name == "entry" {
            if var entry = currentEntry {
                if entry.externalID.isEmpty {
                    entry.externalID = entry.link ?? entry.title
                }
                entries.append(entry)
            }
            currentEntry = nil
            isInEntry = false
        }

        currentText = ""
    }
}

final class FeedDateParser {
    private let rfc822Formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()

    private let rfc822AltFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()

    private let isoFormatter = ISO8601DateFormatter()

    func parse(_ value: String) -> Date? {
        if let date = rfc822Formatter.date(from: value) { return date }
        if let date = rfc822AltFormatter.date(from: value) { return date }
        if let date = isoFormatter.date(from: value) { return date }
        return nil
    }
}
