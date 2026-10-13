import Foundation

/// Shared by the menu-bar renderer and its settings preview, including selected source order.
enum MiniDisplayFormatter {
    static func line(values: [String], units: [String], style: String, mode: String) -> (primary: String, accent: String) {
        let numbers = values.joined(separator: "｜")
        let withUnits = units.joined(separator: "｜")
        switch style {
        case "value": return (numbers, "")
        case "unit": return (withUnits, "")
        case "mode": return (numbers + "｜", mode)
        default: return (withUnits + "｜", mode)
        }
    }
}
