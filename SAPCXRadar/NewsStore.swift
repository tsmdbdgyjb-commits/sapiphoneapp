import Foundation
import Observation

@MainActor
@Observable
final class NewsStore {
    private(set) var items: [NewsItem] = []
    private(set) var isLoading = false
    private(set) var lastUpdated: Date?
    private(set) var failedSources: [String] = []

    private(set) var bookmarks: [NewsItem] = []
    private(set) var readIDs: Set<String> = []

    private let defaults = UserDefaults.standard
    private enum Key {
        static let cache = "cachedItems"
        static let bookmarks = "bookmarks"
        static let read = "readIDs"
        static let updated = "lastUpdated"
    }

    init() {
        items = load([NewsItem].self, Key.cache) ?? []
        bookmarks = load([NewsItem].self, Key.bookmarks) ?? []
        readIDs = Set(load([String].self, Key.read) ?? [])
        lastUpdated = defaults.object(forKey: Key.updated) as? Date
    }

    // MARK: - Loading

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        var collected: [NewsItem] = []
        var failed: [String] = []

        await withTaskGroup(of: (FeedSource, [NewsItem]?).self) { group in
            for source in FeedSource.all {
                group.addTask { (source, await Self.fetch(source)) }
            }
            for await (source, result) in group {
                if let result { collected += result } else { failed.append(source.name) }
            }
        }

        // Deduplicate by link; keep the richest classification.
        var byID: [String: NewsItem] = [:]
        for item in collected {
            if let existing = byID[item.id], existing.products.count >= item.products.count { continue }
            byID[item.id] = item
        }

        let sorted = byID.values.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        if !sorted.isEmpty {
            items = sorted
            lastUpdated = .now
            save(items, Key.cache)
            defaults.set(lastUpdated, forKey: Key.updated)
        }
        failedSources = Array(Set(failed)).sorted()
    }

    /// Live search in the whole SAP Community (not limited to the tracked products).
    nonisolated static func searchCommunity(_ query: String) async -> [NewsItem]? {
        guard let items = await fetch(.community(query), requireProduct: false) else { return nil }
        // The community sometimes lists the same post under two URLs.
        var seenTitles = Set<String>()
        return items
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .filter { seenTitles.insert($0.title.lowercased()).inserted }
    }

    nonisolated private static func fetch(_ source: FeedSource, requireProduct: Bool = true) async -> [NewsItem]? {
        var request = URLRequest(url: source.url, timeoutInterval: 20)
        request.setValue("Mozilla/5.0 (iPhone) SAPCXRadar/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        let isNewsCenter = source.url.host?.contains("news.sap.com") == true

        return RSSParser.parse(data).compactMap { raw in
            guard !raw.title.lowercased().hasPrefix("re:"), let url = URL(string: raw.link) else { return nil }
            if requireProduct, Classifier.isNoise(title: raw.title) { return nil }
            let body = RSSParser.plainText(raw.description, limit: 4000)
            let topic = Classifier.topic(title: raw.title, body: body)
            var products = Classifier.products(title: raw.title, body: body)
            if topic != .general {
                products.formUnion(Classifier.releaseProducts(title: raw.title))
            }

            if products.isEmpty && requireProduct {
                // Keep only general CX news from the official news center.
                guard isNewsCenter, Classifier.isCXNews(title: raw.title, body: body) else { return nil }
            }

            return NewsItem(
                title: RSSParser.plainText(raw.title, limit: 300),
                link: url,
                summary: RSSParser.plainText(raw.description),
                date: RSSParser.date(from: raw.pubDate),
                author: raw.creator.isEmpty ? nil : raw.creator,
                source: source.name,
                products: products,
                topic: topic
            )
        }
    }

    // MARK: - Filtering

    func items(product: Product?, topics: Set<Topic>? = nil, search: String = "") -> [NewsItem] {
        items.filter { item in
            (product == nil || item.products.contains(product!))
            && (topics == nil || topics!.contains(item.topic))
            && (search.isEmpty
                || item.title.localizedCaseInsensitiveContains(search)
                || item.summary.localizedCaseInsensitiveContains(search))
        }
    }

    /// Global search over cached news and bookmarks. Every word must match
    /// (title, summary, author, source or product name).
    func globalSearch(_ query: String, product: Product?) -> [NewsItem] {
        let words = query.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }

        var seen = Set<String>()
        let pool = (items + bookmarks).filter { seen.insert($0.id).inserted }

        return pool.filter { item in
            if let product, !item.products.contains(product) { return false }
            let haystack = ([item.title, item.summary, item.author ?? "", item.source, item.topic.title]
                            + item.products.flatMap { [$0.title, $0.shortTitle] })
                .joined(separator: " ")
            return words.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
        }
        .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    func unreadCount(product: Product?, topics: Set<Topic>? = nil) -> Int {
        items(product: product, topics: topics).filter { !readIDs.contains($0.id) }.count
    }

    // MARK: - Read state & bookmarks

    func isRead(_ item: NewsItem) -> Bool { readIDs.contains(item.id) }

    func markRead(_ item: NewsItem) {
        readIDs.insert(item.id)
        save(Array(readIDs), Key.read)
    }

    func toggleRead(_ item: NewsItem) {
        if readIDs.contains(item.id) { readIDs.remove(item.id) } else { readIDs.insert(item.id) }
        save(Array(readIDs), Key.read)
    }

    func markAllRead(_ list: [NewsItem]) {
        readIDs.formUnion(list.map(\.id))
        save(Array(readIDs), Key.read)
    }

    func isBookmarked(_ item: NewsItem) -> Bool { bookmarks.contains { $0.id == item.id } }

    func toggleBookmark(_ item: NewsItem) {
        if let i = bookmarks.firstIndex(where: { $0.id == item.id }) {
            bookmarks.remove(at: i)
        } else {
            bookmarks.insert(item, at: 0)
        }
        save(bookmarks, Key.bookmarks)
    }

    // MARK: - Persistence

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
