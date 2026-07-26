import SwiftUI

enum AppDesign {
    static let tintUIColor = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            if traits.accessibilityContrast == .high {
                return UIColor(red: 0.34, green: 0.86, blue: 0.88, alpha: 1)
            }
            return UIColor(red: 0.20, green: 0.73, blue: 0.76, alpha: 1)
        }
        if traits.accessibilityContrast == .high {
            return UIColor(red: 0.0, green: 0.27, blue: 0.30, alpha: 1)
        }
        return UIColor(red: 0.0, green: 0.38, blue: 0.42, alpha: 1)
    }
    static let tint = Color(uiColor: tintUIColor)
    static let prominentButtonTint = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return traits.accessibilityContrast == .high
                ? UIColor(red: 0.0, green: 0.45, blue: 0.49, alpha: 1)
                : UIColor(red: 0.0, green: 0.40, blue: 0.44, alpha: 1)
        }
        return traits.accessibilityContrast == .high
            ? UIColor(red: 0.0, green: 0.27, blue: 0.30, alpha: 1)
            : UIColor(red: 0.0, green: 0.36, blue: 0.40, alpha: 1)
    })
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
