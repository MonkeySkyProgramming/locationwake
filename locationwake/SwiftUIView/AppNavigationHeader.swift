import SwiftUI

enum AppDesign {
    static let tintUIColor = UIColor { traits in
        if traits.accessibilityContrast == .high {
            return UIColor(red: 0.0, green: 0.34, blue: 0.38, alpha: 1)
        }
        return UIColor(red: 0.0, green: 0.47, blue: 0.52, alpha: 1)
    }
    static let tint = Color(uiColor: tintUIColor)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let adScrollClearance: CGFloat = 0
}

struct AdListClearance: View {
    var body: some View {
        Color.clear
            .frame(height: AppDesign.adScrollClearance)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityHidden(true)
    }
}
