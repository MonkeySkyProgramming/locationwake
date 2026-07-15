import SwiftUI

enum AppDesign {
    static let tint = Color(red: 0.0, green: 0.54, blue: 0.60)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let cornerRadius: CGFloat = 16
    static let horizontalPadding: CGFloat = 16
    static let adScrollClearance: CGFloat = 112
}

struct AppNavigationHeader<Trailing: View>: View {
    let title: String
    var showsBackButton = false
    var backAction: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if showsBackButton {
                    Button(action: { backAction?() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 19, weight: .semibold))
                            Text("戻る")
                                .font(.system(size: 17))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppDesign.tint)
                } else {
                    trailingLeadingPlaceholder
                }
            }
            .frame(width: 84, height: 52, alignment: .leading)

            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                trailing()
            }
            .frame(width: 84, height: 52, alignment: .trailing)
        }
        .frame(height: 58)
        .padding(.horizontal, 12)
        .background(AppDesign.background)
        // AppNavigationHeader is the app's opaque navigation chrome.
        // Keep NavigationStack's system bar out of the layout on every destination.
        .toolbar(.hidden, for: .navigationBar)
    }

    private var trailingLeadingPlaceholder: some View {
        Color.clear
    }
}

extension AppNavigationHeader where Trailing == EmptyView {
    init(title: String, showsBackButton: Bool = false, backAction: (() -> Void)? = nil) {
        self.title = title
        self.showsBackButton = showsBackButton
        self.backAction = backAction
        self.trailing = { EmptyView() }
    }
}

struct AppIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .regular))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppDesign.tint)
    }
}

struct AppSaveButton: View {
    let action: () -> Void

    var body: some View {
        Button("保存", action: action)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(AppDesign.tint)
            .frame(width: 64, height: 44, alignment: .trailing)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .accessibilityHint("アラームの変更を保存します")
    }
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
