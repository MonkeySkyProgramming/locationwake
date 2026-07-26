import SwiftUI
import GoogleMobileAds

struct BaseContainerView<Content: View>: View {
    let content: Content
    @ObservedObject private var trackingAuthorization = ATTAuthorizationCoordinator.shared

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if AppRuntime.shouldShowBannerAds
            && trackingAuthorization.authorizationStatus != .notDetermined {
            content
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        Color.secondary.opacity(0.16)
                            .frame(height: 1) // Top margin above ad

                        AdBannerView()
                            .frame(height: 50)
                            .background(.bar)

                        Color.clear.frame(height: 8)
                    }
                    .frame(maxWidth: .infinity)
                }
                .background(Color(uiColor: .systemGroupedBackground))
        } else {
            content
                .background(Color(uiColor: .systemGroupedBackground))
        }
    }
}
