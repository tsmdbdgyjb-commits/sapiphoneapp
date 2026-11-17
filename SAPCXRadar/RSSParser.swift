import Foundation

/// A raw entry straight from an RSS feed.
struct RawEntry {
    var title = ""
    var link = ""
    var description = ""
    var pubDate = ""
    var creator = ""
}

/// Minimal RSS 2.0 parser built on Foundation's XMLParser.
final class RSSParser: NSObject, XMLParserDelegate {
    private var entries: [RawEntry] = []
    private var current: RawEntry?
    private var text = ""

    static func parse(_ data: Data) -> [RawEntry] {
        let delegate = RSSParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.entries
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "item" { current = RawEntry() }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if elementName == "item", let item = current {
            entries.append(item)
            current = nil
        } else if current != nil {
            switch elementName {
            case "title": current?.title = value
            case "link": current?.link = value
            case "description": current?.description = value
            case "pubDate": current?.pubDate = value
            case "dc:creator", "creator": current?.creator = value
            default: break
            }
        }
        text = ""
    }

    // MARK: - Helpers

    private static let rfc822: [DateFormatter] = {
        ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEE, dd MMM yyyy HH:mm:ss Z", "dd MMM yyyy HH:mm:ss zzz"].map {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = $0
            return f
        }
    }()

    static func date(from string: String) -> Date? {
        for f in rfc822 { if let d = f.date(from: string) { return d } }
        return nil
    }

    /// Strips HTML tags/entities and shortens text for a preview.
    static func plainText(_ html: String, limit: Int = 280) -> String {
        var s = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&rsquo;": "’", "&ndash;": "–", "&hellip;": "…"]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if s.count > limit { s = String(s.prefix(limit)) + "…" }
        return s
    }
}
