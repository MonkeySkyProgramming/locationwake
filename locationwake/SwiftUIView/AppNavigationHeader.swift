import SwiftUI

enum AppDesign {
    static let tint = Color(red: 0.0, green: 0.54, blue: 0.60)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let cornerRadius: CGFloat = 16
    static let horizontalPadding: CGFloat = 16
    static let adScrollClearance: CGFloat = 112
}

struct AppCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(AppDesign.card)
            .clipShape(RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            }
    }
}

struct AppSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 17))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppDesign.horizontalPadding + 4)
    }
}

struct AdScrollClearance: View {
    var body: some View {
        Color.clear
            .frame(height: AppDesign.adScrollClearance)
            .accessibilityHidden(true)
    }
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
