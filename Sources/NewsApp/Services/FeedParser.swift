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
            let link = item["url"] as? String ?? item["external_url"] as? String
            let summary = item["summary"] as? String
            let contentHTML = item["content_html"] as? String ?? item["content_text"] as? String
            let author = (item["author"] as? [String: Any])?["name"] as? String
                ?? (item["authors"] as? [[String: Any]])?.first?["name"] as? String
            let dateString = item["date_published"] as? String
            let publishedAt = dateString.flatMap { dateParser.parse($0) }
            let imageURL = item["image"] as? String ?? item["banner_image"] as? String
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

    private var elementStack: [String] = []
    private var textStack: [String] = []
    private var elementHasChildStack: [Bool] = []
    private var currentEntry: FeedEntry?
    private var isInItem = false
    private var isInEntry = false
    private var itemRootDepth: Int?
    private var entryRootDepth: Int?
    private var authorDepth: Int?

    init(dateParser: FeedDateParser) {
        self.dateParser = dateParser
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let currentElement = normalizedName(elementName, qualifiedName: qName)
        if !elementHasChildStack.isEmpty {
            elementHasChildStack[elementHasChildStack.count - 1] = true
        }
        elementStack.append(currentElement)
        textStack.append("")
        elementHasChildStack.append(false)

        if currentElement == "item" {
            isInItem = true
            itemRootDepth = elementStack.count
            authorDepth = nil
            currentEntry = FeedEntry(externalID: "", title: "Untitled", link: nil, summary: nil, contentHTML: nil, author: nil, publishedAt: nil, imageURL: nil)
        } else if currentElement == "entry" {
            isInEntry = true
            entryRootDepth = elementStack.count
            authorDepth = nil
            currentEntry = FeedEntry(externalID: "", title: "Untitled", link: nil, summary: nil, contentHTML: nil, author: nil, publishedAt: nil, imageURL: nil)
        }

        if (isInItem || isInEntry), currentElement == "author", isDirectEntryChild {
            authorDepth = elementStack.count
        }

        if isInItem || isInEntry, isDirectEntryChild || isMediaElement(currentElement) {
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
        guard !textStack.isEmpty else { return }
        textStack[textStack.count - 1] += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let text = String(data: CDATABlock, encoding: .utf8), !textStack.isEmpty else { return }
        textStack[textStack.count - 1] += text
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = normalizedName(elementName, qualifiedName: qName)
        let depth = elementStack.count
        let text = (textStack.last ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hadChildren = elementHasChildStack.last ?? false

        if isInItem || isInEntry {
            if isDirectEntryChild(atDepth: depth) {
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
                case "author":
                    if !hadChildren, !text.isEmpty { currentEntry?.author = text }
                case "dc:creator":
                    if !text.isEmpty { currentEntry?.author = text }
                case "pubdate", "published", "updated":
                    if let date = dateParser.parse(text) { currentEntry?.publishedAt = date }
                default:
                    break
                }
            } else if let authorDepth, depth == authorDepth + 1, localName(name) == "name" {
                if !text.isEmpty { currentEntry?.author = text }
            }
        } else if name == "title", parentName == "channel" {
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
            itemRootDepth = nil
            authorDepth = nil
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
            entryRootDepth = nil
            authorDepth = nil
        }

        if let authorDepth, depth == authorDepth, name == "author" {
            self.authorDepth = nil
        }

        popElement()
    }

    private func normalizedName(_ elementName: String, qualifiedName qName: String?) -> String {
        let name = qName?.isEmpty == false ? qName! : elementName
        return name.lowercased()
    }

    private var currentRootDepth: Int? {
        itemRootDepth ?? entryRootDepth
    }

    private var isDirectEntryChild: Bool {
        isDirectEntryChild(atDepth: elementStack.count)
    }

    private func isDirectEntryChild(atDepth depth: Int) -> Bool {
        guard let rootDepth = currentRootDepth else { return false }
        return depth == rootDepth + 1
    }

    private func isMediaElement(_ name: String) -> Bool {
        name == "media:content" || name == "media:thumbnail"
    }

    private var parentName: String? {
        guard elementStack.count >= 2 else { return nil }
        return elementStack[elementStack.count - 2]
    }

    private func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }

    private func popElement() {
        guard !elementStack.isEmpty else { return }
        let rawText = textStack.popLast() ?? ""
        _ = elementStack.popLast()
        _ = elementHasChildStack.popLast()
        if !textStack.isEmpty {
            textStack[textStack.count - 1] += rawText
        }
    }
}

final class FeedDateParser {
    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }

    private let dateFormatters: [DateFormatter] = [
        formatter("EEE, dd MMM yyyy HH:mm:ss Z"),
        formatter("EEE, dd MMM yyyy HH:mm:ss zzz"),
        formatter("dd MMM yyyy HH:mm:ss Z"),
        formatter("dd MMM yyyy HH:mm:ss zzz"),
        formatter("yyyy-MM-dd'T'HH:mm:ssZ"),
        formatter("yyyy-MM-dd'T'HH:mm:ss.SSSZ")
    ]

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let isoFormatterWithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    func parse(_ value: String) -> Date? {
        for formatter in dateFormatters {
            if let date = formatter.date(from: value) { return date }
        }
        if let date = isoFormatter.date(from: value) { return date }
        if let date = isoFormatterWithoutFractionalSeconds.date(from: value) { return date }
        return nil
    }
}
