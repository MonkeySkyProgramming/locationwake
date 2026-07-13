import SwiftUI
import GoogleMobileAds

struct BaseContainerView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Color("NavBarColor")
                        .frame(height: 1) // Top margin above ad

                    AdBannerView()
                        .frame(height: 50)
                        .background(Color("NavBarColor"))

                    Rectangle()
                        .fill(Color("NavBarColor"))
                        .frame(height: 10)
                }
                .frame(maxWidth: .infinity)
            }
            .background(Color.white)
            .overlay(alignment: .bottomTrailing) {
                Button(action: {
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first {
                        let onboardingView = UIHostingController(rootView: OnboardingView())
                        onboardingView.modalPresentationStyle = .pageSheet
                        window.rootViewController?.present(onboardingView, animated: true, completion: nil)
                    }
                }) {
                    Image(systemName: "questionmark.circle")
                        .resizable()
                        .frame(width: 32, height: 32)
                        .foregroundColor(.primary)
                }
                .allowsHitTesting(true)
                .padding(.bottom, 76)
                .padding(.trailing)
            }
    }
}
