import SwiftUI
import SafariServices

struct BookmarksView: View {
    @Environment(NewsStore.self) private var store
    @State private var openURL: URL?

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.bookmarks) { item in
                    Button {
                        openURL = item.link
                    } label: {
                        NewsRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Entfernen", systemImage: "trash", role: .destructive) {
                            store.toggleBookmark(item)
                        }
                    }
                }
            }
            .navigationTitle("Merkliste")
            .overlay {
                if store.bookmarks.isEmpty {
                    ContentUnavailableView("Noch nichts gemerkt", systemImage: "bookmark",
                                           description: Text("Wische in der News-Liste nach rechts, um einen Beitrag zu merken."))
                }
            }
            .sheet(item: $openURL) { SafariView(url: $0).ignoresSafeArea() }
        }
    }
}

struct LinksView: View {
    @State private var openURL: URL?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(QuickLink.all.filter { $0.product == nil }) { row($0) }
                } header: {
                    Text("Roadmap & Releases")
                } footer: {
                    Text("Im Roadmap Explorer nach „Sales Cloud“, „Service Cloud“ oder „Field Service Management“ suchen.")
                }

                Section("Produktdokumentation") {
                    ForEach(QuickLink.all.filter { $0.product != nil }) { row($0) }
                }
            }
            .navigationTitle("Links")
            .sheet(item: $openURL) { SafariView(url: $0).ignoresSafeArea() }
        }
    }

    private func row(_ link: QuickLink) -> some View {
        Button {
            openURL = link.url
        } label: {
            HStack(spacing: 14) {
                Image(systemName: link.symbol)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(link.product?.color ?? .teal, in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.title).font(.body.weight(.medium))
                    Text(link.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right").foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// In-app Safari for reading articles.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        return SFSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
