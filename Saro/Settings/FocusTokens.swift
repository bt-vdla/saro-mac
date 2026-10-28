import SaroKit
import SwiftUI

extension FocusArea {
    /// The web's AA focus tokens (globals.css --saro-focus-*), by day and at night.
    var tint: Color {
        switch self {
        case .clarity: Color(0x6A7580, 0xA9B4BF)
        case .steadiness: Color(0x6D6CB4, 0xA9A8EC)
        case .creative: Color(0xA02C5C, 0xE58AB0)
        case .relationships: Color(0xBD534B, 0xEE9A90)
        case .habits: Color(0x4B6B56, 0x8FC0A0)
        case .confidence: Color(0x6B3A7A, 0xC49AD4)
        case .energy: Color(0x1E7A60, 0x6FC7A8)
        case .purpose: Color(0x8E7025, 0xD8B868)
        }
    }
}
