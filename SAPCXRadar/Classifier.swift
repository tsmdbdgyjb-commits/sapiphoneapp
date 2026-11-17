import Foundation

/// Decides which products an article is about and whether it is release/roadmap news.
enum Classifier {
    private static let patterns: [Product: [String]] = [
        .salesV2: [
            #"sales\s*(&|and)?\s*(service\s*)?cloud\s*(v2|version\s*2)"#,
            #"sales\s*cloud\s*(v2|version\s*2)"#,
            #"sales\s*(&|and)\s*service\s*cloud\s*(v2|version\s*2)"#,
            #"sales\s*/\s*service\s*cloud\s*(v2|version\s*2)"#,
        ],
        .serviceV2: [
            #"service\s*cloud\s*(v2|version\s*2)"#,
            #"sales\s*(&|and|/)\s*service\s*cloud\s*(v2|version\s*2)"#,
        ],
        .fsm: [
            #"field\s*service\s*management"#,
            #"\bsap\s*fsm\b"#,
            #"\bfsm\b"#,
        ],
    ]

    private static let releaseWords = [
        #"release\s*(highlights|notes|briefing)"#, #"innovation\s*highlights"#, #"\b(25|26|27)(0[1-9]|1[0-2])\s*release"#,
        #"what[’']?s\s*new"#, #"\bq[1-4]\s*20\d\d\s*release"#,
        #"\b2[0-9](0[1-9]|1[0-2])\b\s*(release|update)"#, #"new\s*features"#, #"now\s*available"#,
    ]

    private static let roadmapWords = [
        #"roadmap"#, #"pre-?release"#, #"\bplanned\b"#, #"upcoming"#, #"coming\s*soon"#,
        #"early\s*adopter"#, #"sneak\s*peek"#, #"preview"#, #"future\s*of"#,
    ]

    private static func matches(_ text: String, _ regexes: [String]) -> Bool {
        regexes.contains { text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    /// Number of distinct matches in `text` for the most frequent pattern.
    private static func count(_ text: String, _ regexes: [String]) -> Int {
        regexes.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
            .map { $0.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) }
            .max() ?? 0
    }

    /// Products mentioned. Title counts fully; body only for the more specific patterns.
    static func products(title: String, body: String) -> Set<Product> {
        var result = Set<Product>()
        for (product, regexes) in patterns {
            if matches(title, regexes) {
                result.insert(product)
            } else {
                // In the body, a bare "FSM" is too ambiguous, and a single passing
                // mention is not enough: require the full name at least twice.
                let strict = regexes.filter { $0 != #"\bfsm\b"# }
                if count(body, strict) >= 2 { result.insert(product) }
            }
        }
        return result
    }

    static func topic(title: String, body: String) -> Topic {
        if matches(title, roadmapWords) { return .roadmap }
        if matches(title, releaseWords) { return .release }
        if matches(body, roadmapWords) && matches(body, [#"roadmap"#]) { return .roadmap }
        return .general
    }

    /// Release/roadmap posts often say just "SAP Sales Cloud" without "V2".
    /// Count those as V2 news unless they are explicitly about V1 / C4C.
    static func releaseProducts(title: String) -> Set<Product> {
        guard !matches(title, [#"\bC4C\b"#, #"\bV1\b"#, #"version\s*1"#]) else { return [] }
        var result = Set<Product>()
        if matches(title, [#"sales\s*cloud"#]) { result.insert(.salesV2) }
        if matches(title, [#"service\s*cloud"#]) { result.insert(.serviceV2) }
        if matches(title, [#"field\s*service\s*management"#]) { result.insert(.fsm) }
        return result
    }

    /// General SAP CX news (used for the SAP News Center feed, which rarely names "V2").
    static func isCXNews(title: String, body: String) -> Bool {
        matches(title + " " + body, [#"sales\s*cloud"#, #"service\s*cloud"#, #"field\s*service"#,
                                      #"customer\s*experience"#, #"\bSAP\s*CX\b"#, #"\bCRM\b"#])
    }

    /// Forum replies ("Re: …") are noise in the news list.
    /// Posts explicitly about V1 / C4C (without V2) are out of scope too.
    static func isNoise(title: String) -> Bool {
        if title.lowercased().hasPrefix("re:") { return true }
        let v1 = matches(title, [#"\bC4C\b"#, #"\bV1\b"#, #"version\s*1\b"#])
        let v2 = matches(title, [#"\bV2\b"#, #"version\s*2"#])
        return v1 && !v2
    }
}
