import SwiftUI
import UIKit



extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double

        r = Double((int >> 16) & 0xFF) / 255
        g = Double((int >> 8) & 0xFF) / 255
        b = Double(int & 0xFF) / 255

        self.init(red: r, green: g, blue: b)
    }
}

extension Font {
    static func alexandria(fontStyle: Font.TextStyle =  .body, fontWeight: Weight = .regular) -> Font {
        return Font.custom(CustomFont(weight: fontWeight).rawValue, size: 16)
    }
}

enum CustomFont: String {
    case regular = "alx600"
    case bold = "alx900"
    
    init (weight: Font.Weight) {
        switch weight {
        case .regular:
            self = .regular
        case .bold:
            self = .bold
        default:
            self = .regular
        }
    }
}


extension String {
    var initials: String {
        let parts = self.split(separator: " ")
        guard parts.count >= 2,
              let first = parts.first?.first,
              let last = parts.dropFirst().first?.first
        else { return "" }
        return "\(first)\(last)"
    }
}


struct InitialenKreisView: View {
    let fullName: String

    var body: some View {
        Circle()
            .fill(Color(hex: "add8e6"))
            .stroke(Color(hex: "9ac0cd"), lineWidth: 3)
            .frame(width: 120)
            .overlay(
                Text(fullName.initials)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
            )
    }
}
