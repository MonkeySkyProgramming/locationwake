import SwiftUI

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
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Color("NavBarTintColor"))
                } else {
                    trailingLeadingPlaceholder
                }
            }
            .frame(width: 56, height: 44)

            Text(title)
                .font(.headline)
                .foregroundColor(Color("NavBarTintColor"))
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                trailing()
            }
            .frame(width: 56, height: 44)
        }
        .frame(height: 44)
        .background(Color("NavBarColor"))
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
        .foregroundColor(Color("NavBarTintColor"))
    }
}
