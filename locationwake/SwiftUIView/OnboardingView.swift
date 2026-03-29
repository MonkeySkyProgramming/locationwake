import SwiftUI

struct OnboardingView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var currentPage = 0
    let images = ["AppStore1", "AppStore2", "AppStore3", "AppStore4", "AppStore5"]

    var body: some View {
        VStack {
            TabView(selection: $currentPage) {
                ForEach(0..<images.count, id: \.self) { index in
                    VStack {
                        Spacer()
                        Image(images[index])
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: UIScreen.main.bounds.height * 0.8)
                            .padding(.horizontal)

                        Spacer()

                        Button(action: {
                            if index < images.count - 1 {
                                currentPage += 1
                            } else {
                                UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                                presentationMode.wrappedValue.dismiss()
                            }
                        }) {
                            Text(index == images.count - 1 ? "終了" : "次へ")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(width: 200, height: 50)
                                .background(Color.blue)
                                .cornerRadius(8)
                        }
                        .padding(.bottom, 40)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
        }
    }
}
