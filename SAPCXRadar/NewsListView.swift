import SwiftUI

struct NewsListView: View {
    @Environment(NewsStore.self) private var store
    let title: String
    let topics: Set<Topic>?

    @AppStorage("selectedProduct") private var productRaw = ""
    @State private var search = ""
    @State private var openURL: URL?

    private var product: Product? { Product(rawValue: productRaw) }
    private var list: [NewsItem] { store.items(product: product, topics: topics, search: search) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ProductFilter(selection: $productRaw, topics: topics)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                if !store.failedSources.isEmpty {
                    Label("\(store.failedSources.count) Quelle(n) nicht erreichbar", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(groupedByDay, id: \.day) { group in
                    Section(group.day) {
                        ForEach(group.items) { item in
                            Button {
                                store.markRead(item)
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
                            .swipeActions(edge: .trailing) {
                                Button {
                                    store.toggleRead(item)
                                } label: {
                                    Label(store.isRead(item) ? "Ungelesen" : "Gelesen",
                                          systemImage: store.isRead(item) ? "circle.fill" : "checkmark.circle")
                                }
                                .tint(.blue)
                            }
                            .contextMenu {
                                ShareLink(item: item.link)
                                Button(store.isBookmarked(item) ? "Von Merkliste entfernen" : "Merken",
                                       systemImage: "bookmark") { store.toggleBookmark(item) }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(title)
            .searchable(text: $search, prompt: "In News suchen")
            .refreshable { await store.refresh() }
            .overlay { emptyState }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Alle als gelesen markieren", systemImage: "checkmark.circle") {
                            store.markAllRead(list)
                        }
                        Button("Aktualisieren", systemImage: "arrow.clockwise") {
                            Task { await store.refresh() }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .status) {
                    if store.isLoading {
                        ProgressView()
                    } else if let updated = store.lastUpdated {
                        Text("Aktualisiert \(updated, style: .relative)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(item: $openURL) { url in
                SafariView(url: url).ignoresSafeArea()
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if list.isEmpty {
            if store.isLoading {
                ProgressView("Lade News…")
            } else if !search.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                ContentUnavailableView("Keine Beiträge", systemImage: "newspaper",
                                       description: Text("Zum Aktualisieren nach unten ziehen."))
            }
        }
    }

    private var groupedByDay: [(day: String, items: [NewsItem])] {
        let cal = Calendar.current
        var groups: [(day: String, items: [NewsItem])] = []
        for item in list {
            let day: String
            if let d = item.date {
                if cal.isDateInToday(d) { day = "Heute" }
                else if cal.isDateInYesterday(d) { day = "Gestern" }
                else { day = d.formatted(.dateTime.weekday(.wide).day().month(.wide).year()) }
            } else { day = "Ohne Datum" }
            if groups.last?.day == day { groups[groups.count - 1].items.append(item) }
            else { groups.append((day, [item])) }
        }
        return groups
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - Product filter

struct ProductFilter: View {
    @Environment(NewsStore.self) private var store
    @Binding var selection: String
    let topics: Set<Topic>?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil)
                ForEach(Product.allCases) { chip($0) }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
    }

    private func chip(_ product: Product?) -> some View {
        let selected = (product?.rawValue ?? "") == selection
        let color = product?.color ?? .gray
        let unread = store.unreadCount(product: product, topics: topics)
        return Button {
            withAnimation(.snappy) { selection = product?.rawValue ?? "" }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: product?.symbol ?? "square.grid.2x2")
                Text(product?.shortTitle ?? "Alle")
                if unread > 0 {
                    Text("\(unread)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(selected ? .white.opacity(0.3) : color.opacity(0.2), in: .capsule)
                }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(selected ? .white : color)
            .background(selected ? color : color.opacity(0.12), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Row

struct NewsRow: View {
    @Environment(NewsStore.self) private var store
    let item: NewsItem

    var body: some View {
        let read = store.isRead(item)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if !read {
                    Circle().fill(.blue).frame(width: 8, height: 8)
                }
                ForEach(item.products.sorted(by: { $0.rawValue < $1.rawValue })) { p in
                    Text(p.shortTitle)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .foregroundStyle(p.color)
                        .background(p.color.opacity(0.12), in: .capsule)
                }
                if item.topic != .general {
                    HStack(spacing: 3) {
                        Image(systemName: item.topic.symbol)
                        Text(item.topic.title)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
                }
                Spacer()
                if store.isBookmarked(item) {
                    Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(.yellow)
                }
            }

            Text(item.title)
                .font(.headline)
                .foregroundStyle(read ? .secondary : .primary)
                .lineLimit(3)

            if !item.summary.isEmpty {
                Text(item.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack {
                Text(item.source)
                if let author = item.author { Text("· \(author)") }
                Spacer()
                if let d = item.date { Text(d, format: .dateTime.hour().minute()) }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}
