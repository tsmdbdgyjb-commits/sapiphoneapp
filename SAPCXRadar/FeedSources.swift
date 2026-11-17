import Foundation

/// An RSS feed the app pulls from.
struct FeedSource: Hashable {
    let name: String
    let url: URL

    /// SAP Community full-text search as RSS.
    static func community(_ query: String) -> FeedSource {
        var c = URLComponents(string: "https://community.sap.com/khhcw49343/rss/search")!
        c.queryItems = [URLQueryItem(name: "q", value: query)]
        return FeedSource(name: "SAP Community", url: c.url!)
    }

    static func board(_ id: String, name: String) -> FeedSource {
        FeedSource(name: name, url: URL(string: "https://community.sap.com/khhcw49343/rss/board?board.id=\(id)")!)
    }

    /// All feeds. Search results are noisy, so `Classifier` decides what is relevant.
    static let all: [FeedSource] = [
        // Blog boards for CRM & CX
        .board("crm-blog-sap", name: "CX Blogs (SAP)"),
        .board("crm-blog-members", name: "CX Blogs (Community)"),

        // Sales / Service Cloud V2
        .community("\"Sales Cloud V2\""),
        .community("\"Sales Cloud Version 2\""),
        .community("\"Service Cloud V2\""),
        .community("\"Service Cloud Version 2\""),
        .community("\"Sales and Service Cloud V2\""),

        // Field Service Management
        .community("\"SAP Field Service Management\""),
        .community("\"SAP FSM\""),

        // Releases & roadmap
        .community("\"Sales Cloud\" release highlights"),
        .community("\"Service Cloud\" release highlights"),
        .community("\"Sales Cloud\" roadmap"),
        .community("\"Field Service Management\" release"),
        .community("\"Pre-Release Briefing\" Sales Service Cloud"),

        // Official SAP News Center
        FeedSource(name: "SAP News Center", url: URL(string: "https://news.sap.com/feed/")!),
    ]
}

/// Useful official pages, opened in the in-app browser.
struct QuickLink: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String
    let url: URL
    let product: Product?

    static let all: [QuickLink] = [
        QuickLink(title: "SAP Roadmap Explorer",
                  subtitle: "Geplante Features je Produkt und Quartal",
                  symbol: "map",
                  url: URL(string: "https://roadmaps.sap.com/")!,
                  product: nil),
        QuickLink(title: "What's New Viewer",
                  subtitle: "Neue Funktionen je Release",
                  symbol: "sparkles",
                  url: URL(string: "https://help.sap.com/whats-new/")!,
                  product: nil),
        QuickLink(title: "Hilfe: Sales Cloud V2",
                  subtitle: "Dokumentation & What's New",
                  symbol: Product.salesV2.symbol,
                  url: URL(string: "https://help.sap.com/docs/CX_NG_SALES")!,
                  product: .salesV2),
        QuickLink(title: "Hilfe: Service Cloud V2",
                  subtitle: "Dokumentation & What's New",
                  symbol: Product.serviceV2.symbol,
                  url: URL(string: "https://help.sap.com/docs/CX_NG_SVC")!,
                  product: .serviceV2),
        QuickLink(title: "Hilfe: Field Service Management",
                  subtitle: "Dokumentation & Release Notes",
                  symbol: Product.fsm.symbol,
                  url: URL(string: "https://help.sap.com/docs/SAP_FIELD_SERVICE_MANAGEMENT")!,
                  product: .fsm),
        QuickLink(title: "SAP News Center",
                  subtitle: "Offizielle Pressemitteilungen",
                  symbol: "newspaper",
                  url: URL(string: "https://news.sap.com/")!,
                  product: nil),
    ]
}
