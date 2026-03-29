import Foundation

struct OPMLFeed {
    var title: String
    var xmlURL: URL
    var htmlURL: URL?
}

final class OPMLService: NSObject, XMLParserDelegate {
    private var feeds: [OPMLFeed] = []

    func parse(data: Data) -> [OPMLFeed] {
        feeds = []
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return feeds
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard elementName.lowercased() == "outline" else { return }
        if let xmlUrl = attributeDict["xmlUrl"], let feedURL = URL(string: xmlUrl) {
            let title = attributeDict["title"] ?? attributeDict["text"] ?? feedURL.host ?? "Feed"
            let htmlURL = attributeDict["htmlUrl"].flatMap { URL(string: $0) }
            feeds.append(OPMLFeed(title: title, xmlURL: feedURL, htmlURL: htmlURL))
        }
    }

    func export(feeds: [Feed]) -> Data {
        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<opml version=\"2.0\">")
        lines.append("  <head><title>NewsApp Feeds</title></head>")
        lines.append("  <body>")
        for feed in feeds {
            let title = escape(feed.name)
            let xmlUrl = escape(feed.feedURL.absoluteString)
            let htmlUrl = escape(feed.siteURL?.absoluteString ?? "")
            lines.append("    <outline type=\"rss\" text=\"\(title)\" title=\"\(title)\" xmlUrl=\"\(xmlUrl)\" htmlUrl=\"\(htmlUrl)\" />")
        }
        lines.append("  </body>")
        lines.append("</opml>")
        return Data(lines.joined(separator: "\n").utf8)
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
