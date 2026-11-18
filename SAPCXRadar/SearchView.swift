import SwiftUI

/// Global search: cached news + bookmarks + links, plus a live search in the whole SAP Community.
struct SearchView: View {
    @Environment(NewsStore.self) private var store

    @State private var query = ""
    @State private var scope: Product?
    @State private var openURL: URL?

    @State private var communityResults: [NewsItem] = []
    @State private var communityState: LoadState = .idle
    @AppStorage("recentSearches") private var recentRaw = ""

    enum LoadState: Equatable { case idle, loading, done, failed }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var recent: [String] { recentRaw.split(separator: "\n").map(String.init) }

    private var localResults: [NewsItem] { store.globalSearch(trimmed, product: scope) }

    private var linkResults: [QuickLink] {
        guard !trimmed.isEmpty else { return [] }
        return QuickLink.all.filter {
            ($0.title + " " + $0.subtitle).localizedCaseInsensitiveContains(trimmed)
            && (scope == nil || $0.product == nil || $0.product == scope)
        }
    }

    /// Community hits not already shown in the local results.
    private var extraCommunity: [NewsItem] {
        let localIDs = Set(localResults.map(\.id))
        let localTitles = Set(localResults.map { $0.title.lowercased() })
        return communityResults.filter { item in
            !localIDs.contains(item.id) && !localTitles.contains(item.title.lowercased())
            && (scope == nil || item.products.contains(scope!))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if trimmed.isEmpty {
                    suggestions
                } else {
                    results
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Suche")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "News, Roadmap, Themen …")
            .searchScopes($scope, activation: .onSearchPresentation) {
                Text("Alle").tag(Product?.none)
                ForEach(Product.allCases) { Text($0.shortTitle).tag(Product?.some($0)) }
            }
            .onSubmit(of: .search) { remember(trimmed) }
            .task(id: trimmed) { await runCommunitySearch() }
            .sheet(item: $openURL) { SafariView(url: $0).ignoresSafeArea() }
        }
    }

    // MARK: Sections

    @ViewBuilder private var suggestions: some View {
        if !recent.isEmpty {
            Section {
                ForEach(recent, id: \.self) { term in
                    Button { query = term } label: {
                        Label(term, systemImage: "clock.arrow.circlepath")
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                HStack {
                    Text("Zuletzt gesucht")
                    Spacer()
                    Button("Löschen") { recentRaw = "" }.font(.caption)
                }
            }
        }
        Section("Vorschläge") {
            ForEach(["Release Highlights", "Roadmap", "Pre-Release Briefing", "Autoflow",
                     "Joule", "Extensibility", "Integration S/4HANA"], id: \.self) { term in
                Button { query = term } label: {
                    Label(term, systemImage: "magnifyingglass")
                }
                .foregroundStyle(.primary)
            }
        }
    }

    @ViewBuilder private var results: some View {
        let local = localResults

        if !local.isEmpty {
            Section("In der App (\(local.count))") {
                ForEach(local) { row($0) }
            }
        }

        if !linkResults.isEmpty {
            Section("Links") {
                ForEach(linkResults) { link in
                    Button { openURL = link.url } label: {
                        Label(link.title, systemImage: link.symbol)
                    }
                    .foregroundStyle(.primary)
                }
            }
        }

        Section {
            switch communityState {
            case .idle, .loading:
                HStack { ProgressView(); Text("Suche in der SAP Community …").foregroundStyle(.secondary) }
            case .failed:
                Label("SAP Community nicht erreichbar", systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.secondary)
            case .done:
                if extraCommunity.isEmpty {
                    Text("Keine weiteren Treffer").foregroundStyle(.secondary)
                } else {
                    ForEach(extraCommunity) { row($0) }
                }
            }
        } header: {
            Text("SAP Community – live")
        } footer: {
            Text("Durchsucht die gesamte SAP Community, nicht nur die drei Produkte.")
        }
    }

    private func row(_ item: NewsItem) -> some View {
        Button {
            store.markRead(item)
            remember(trimmed)
            openURL = item.link
        } label: {
            NewsRow(item: item)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            Button {
                store.toggleBookmark(item)
            } label: {
                Label("Merken", systemImage: store.isBookmarked(item) ? "bookmark.slash" : "bookmark")
            }
            .tint(.yellow)
        }
    }

    // MARK: Logic

    private func runCommunitySearch() async {
        let term = trimmed
        communityResults = []
        guard term.count >= 2 else { communityState = .idle; return }
        communityState = .loading
        // Debounce typing.
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        if let found = await NewsStore.searchCommunity(term) {
            guard !Task.isCancelled else { return }
            communityResults = found
            communityState = .done
        } else if !Task.isCancelled {
            communityState = .failed
        }
    }

    private func remember(_ term: String) {
        guard term.count >= 2 else { return }
        let list = [term] + recent.filter { $0.caseInsensitiveCompare(term) != .orderedSame }
        recentRaw = list.prefix(8).joined(separator: "\n")
    }
}
