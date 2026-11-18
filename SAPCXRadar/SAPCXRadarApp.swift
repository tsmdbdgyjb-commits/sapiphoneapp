import SwiftUI

@main
struct SAPCXRadarApp: App {
    @State private var store = NewsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}

struct ContentView: View {
    @Environment(NewsStore.self) private var store

    var body: some View {
        TabView {
            Tab("News", systemImage: "newspaper") {
                NewsListView(title: "SAP CX News", topics: nil)
            }
            .badge(store.unreadCount(product: nil))

            Tab("Merkliste", systemImage: "bookmark") {
                BookmarksView()
            }

            Tab("Roadmap", systemImage: "map") {
                NewsListView(title: "Roadmap & Releases", topics: [.roadmap, .release])
            }

            Tab("Links", systemImage: "link") {
                LinksView()
            }
        }
        .task {
            // Refresh on launch if the cache is older than 30 minutes.
            if store.lastUpdated.map({ Date.now.timeIntervalSince($0) > 1800 }) ?? true {
                await store.refresh()
            }
        }
    }
}
