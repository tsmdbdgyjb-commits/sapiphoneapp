import Foundation
import SwiftUI

/// The SAP products the app tracks.
enum Product: String, CaseIterable, Codable, Identifiable, Hashable {
    case salesV2
    case serviceV2
    case fsm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .salesV2: "Sales Cloud V2"
        case .serviceV2: "Service Cloud V2"
        case .fsm: "Field Service Mgmt"
        }
    }

    var shortTitle: String {
        switch self {
        case .salesV2: "Sales V2"
        case .serviceV2: "Service V2"
        case .fsm: "FSM"
        }
    }

    var symbol: String {
        switch self {
        case .salesV2: "chart.line.uptrend.xyaxis"
        case .serviceV2: "headset"
        case .fsm: "wrench.and.screwdriver"
        }
    }

    var color: Color {
        switch self {
        case .salesV2: .blue
        case .serviceV2: .purple
        case .fsm: .orange
        }
    }
}

/// What kind of news an article is.
enum Topic: String, Codable, CaseIterable, Identifiable {
    case release      // Release notes, "what's new", quarterly releases
    case roadmap      // Roadmap, planned, upcoming, pre-release briefings
    case general      // How-tos, announcements, anything else

    var id: String { rawValue }

    var title: String {
        switch self {
        case .release: "Release"
        case .roadmap: "Roadmap"
        case .general: "Artikel"
        }
    }

    var symbol: String {
        switch self {
        case .release: "sparkles"
        case .roadmap: "map"
        case .general: "doc.text"
        }
    }
}

struct NewsItem: Identifiable, Codable, Hashable {
    var id: String { link.absoluteString }
    let title: String
    let link: URL
    let summary: String
    let date: Date?
    let author: String?
    let source: String
    let products: Set<Product>
    let topic: Topic
}
