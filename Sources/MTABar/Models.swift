import Foundation
import SwiftUI

struct Station: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let line: String
    let borough: String
    let routes: [String]
    let north: String
    let south: String

    static let all: [Station] = (try? JSONDecoder().decode([Station].self, from: Data(stationsJSON.utf8))) ?? []
    static let byID: [String: Station] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    func label(for direction: Direction) -> String {
        direction == .north ? north : south
    }
}

enum Direction: String, Codable, CaseIterable {
    case north = "N"
    case south = "S"
}

struct Watch: Codable, Identifiable, Hashable {
    var id = UUID()
    var stationID: String
    var direction: Direction
    var routes: [String]

    var station: Station? { Station.byID[stationID] }
    var stopID: String { stationID + direction.rawValue }

    var title: String {
        guard let station else { return stationID }
        return "\(station.name) → \(station.label(for: direction))"
    }
}

struct Arrival: Hashable {
    let route: String
    let time: Date
}

enum RouteStyle {
    static func color(_ route: String) -> Color {
        switch route {
        case "1", "2", "3": Color(hex: 0xEE352E)
        case "4", "5", "6": Color(hex: 0x00933C)
        case "7": Color(hex: 0xB933AD)
        case "A", "C", "E", "SI": Color(hex: 0x0039A6)
        case "B", "D", "F", "M": Color(hex: 0xFF6319)
        case "G": Color(hex: 0x6CBE45)
        case "J", "Z": Color(hex: 0x996633)
        case "L": Color(hex: 0xA7A9AC)
        case "N", "Q", "R", "W": Color(hex: 0xFCCC0A)
        default: Color(hex: 0x808183)
        }
    }

    static func textColor(_ route: String) -> Color {
        ["N", "Q", "R", "W"].contains(route) ? .black : .white
    }

    static func displayName(_ route: String) -> String {
        ["GS", "FS", "H"].contains(route) ? "S" : route
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

struct RouteBadge: View {
    let route: String
    var size: CGFloat = 18
    var dimmed = false

    var body: some View {
        Text(RouteStyle.displayName(route))
            .font(.system(size: size * 0.6, weight: .bold))
            .foregroundStyle(RouteStyle.textColor(route))
            .frame(width: size, height: size)
            .background(Circle().fill(RouteStyle.color(route)))
            .opacity(dimmed ? 0.25 : 1)
    }
}
