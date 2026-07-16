import SwiftUI
import CoreLocation
import UIKit

struct OnboardingView: View {
    private struct Page: Identifiable {
        let title: String
        let message: String
        let symbol: String
        let screenshotAsset: String?
        let screenshotAlignment: Alignment
        var id: String { title }
    }

    private let pages = [
        Page(title: "目的地で起きる。", message: "設定した場所に近づくと、アラームでお知らせします。", symbol: "location.circle.fill", screenshotAsset: "onboarding1", screenshotAlignment: .top),
        Page(title: "目的地を検索。", message: "駅名や場所を検索して、目的地を選びます。", symbol: "magnifyingglass", screenshotAsset: "onboarding2", screenshotAlignment: .bottom),
        Page(title: "到着範囲を決める。", message: "地図を見ながら、到着を知らせる範囲を設定できます。", symbol: "scope", screenshotAsset: "onboarding3", screenshotAlignment: .center),
        Page(title: "いつでも見守る。", message: "バックグラウンドで到着を検知するため、位置情報を「常に許可」にしてください。", symbol: "location.fill.viewfinder", screenshotAsset: nil, screenshotAlignment: .center),
        Page(title: "到着をお知らせ。", message: "目的地に近づくと、通知・音・バイブレーションでお知らせします。", symbol: "bell.badge.fill", screenshotAsset: nil, screenshotAlignment: .center)
    ]

    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0
    @State private var locationAuthorization = CLLocationManager().authorizationStatus
    @State private var showsLocationPermissionAlert = false

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    pageContent(page)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button(currentPage == pages.count - 1 ? "はじめる" : "次へ") {
                if currentPage == 3 && locationAuthorization != .authorizedAlways {
                    showsLocationPermissionAlert = true
                } else if currentPage == pages.count - 1 {
                    UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                    dismiss()
                } else {
                    withAnimation { currentPage += 1 }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppDesign.tint)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)

            if currentPage != 3 {
                Button("あとで") {
                    UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                    dismiss()
                }
                .padding(.vertical, 16)
            } else {
                Text("位置情報を「常に許可」にすると次へ進めます")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
            }
        }
        .padding(.top, 8)
        .background(Color(uiColor: .systemBackground))
        .alert("位置情報を「常に許可」にしてください", isPresented: $showsLocationPermissionAlert) {
            Button(locationAuthorization == .notDetermined ? "位置情報を許可" : "設定を開く") {
                requestRequiredLocationAuthorization()
            }
        } message: {
            Text("バックグラウンドで到着を検知するために必要です。許可後も「常に許可」になっていない場合は、設定アプリで変更してください。")
        }
        .onReceive(NotificationCenter.default.publisher(for: .locationAuthorizationDidChange)) { _ in
            refreshLocationAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshLocationAuthorization()
            if currentPage == 3 && locationAuthorization != .authorizedAlways {
                showsLocationPermissionAlert = true
            }
        }
        .onChange(of: currentPage) { _, page in
            if page > 3 && locationAuthorization != .authorizedAlways {
                currentPage = 3
                showsLocationPermissionAlert = true
            }
        }
    }

    private func refreshLocationAuthorization() {
        locationAuthorization = CLLocationManager().authorizationStatus
    }

    @ViewBuilder
    private func pageContent(_ page: Page) -> some View {
        if let screenshotAsset = page.screenshotAsset {
            VStack(spacing: 20) {
                Spacer(minLength: 24)

                OnboardingScreenshot(assetName: screenshotAsset, alignment: page.screenshotAlignment)

                Text(page.title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text(page.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer(minLength: 24)
            }
        } else {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: page.symbol)
                    .font(.system(size: 92, weight: .regular))
                    .foregroundStyle(AppDesign.tint)
                    .accessibilityHidden(true)
                Text(page.title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(page.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            }
        }
    }

    private func requestRequiredLocationAuthorization() {
        if locationAuthorization == .notDetermined {
            LocationManager.shared.locationManager.requestAlwaysAuthorization()
        } else if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
}

private struct OnboardingScreenshot: View {
    let assetName: String
    let alignment: Alignment

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 264, alignment: alignment)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
            .padding(.horizontal, 24)
            .accessibilityHidden(true)
    }
}
