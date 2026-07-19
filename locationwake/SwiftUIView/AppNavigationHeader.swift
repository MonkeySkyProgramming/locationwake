import SwiftUI

enum AppDesign {
    static let tint = Color(red: 0.0, green: 0.54, blue: 0.60)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let adScrollClearance: CGFloat = 112
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
