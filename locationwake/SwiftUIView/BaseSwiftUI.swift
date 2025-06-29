import SwiftUI
import GoogleMobileAds

struct BaseContainerView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color("NavBarColor").edgesIgnoringSafeArea(.all)
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    content
                        .frame(height: geometry.size.height - 60)
                    Spacer(minLength: 0)
                }
            }

            VStack(spacing: 0) {
                Color("NavBarColor")
                    .frame(height: 1) // Top margin above ad
                    .edgesIgnoringSafeArea(.horizontal)

                AdBannerView()
                    .frame(height: 50)
                    .background(Color("NavBarColor"))

                Rectangle()
                    .fill(Color("NavBarColor"))
                    .frame(height: 10)
            }
            .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea(edges: .bottom)
        .overlay(
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        NotificationCenter.default.post(name: NSNotification.Name("ShowHelpOverlay"), object: nil)
                    }) {
                        Image(systemName: "questionmark.circle")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .foregroundColor(.primary)
                            .padding(.bottom, 90)
                            .padding(.trailing)
                    }
                }
            }
        )
    }
}
