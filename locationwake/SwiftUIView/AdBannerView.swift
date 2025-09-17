import SwiftUI
import GoogleMobileAds
import Foundation

/// AdMob バナーを下部に固定表示するための最適化ラッパー
/// - 常に `rootViewController` を適切にセット
/// - 画面幅に応じた Anchored Adaptive サイズを使用
/// - 回転/レイアウト変化時に幅を検知してリロード
struct AdBannerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> BannerHostingController {
        let vc = BannerHostingController()
        return vc
    }

    func updateUIViewController(_ uiViewController: BannerHostingController, context: Context) {
        // 特に無し（VC 内でサイズ変化をハンドリング）
    }

    // MARK: - Hosting Controller
    final class BannerHostingController: UIViewController, BannerViewDelegate {
        private var bannerView: BannerView?
        private let bottomBar = UIView()
        private var didSetupOnce = false
        private var lastSafeWidth: CGFloat = 0

        override func viewDidLoad() {
            super.viewDidLoad()
            setupBottomBar()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // rootViewController を安全に設定できるタイミングで 1 回だけセットアップ
            if !didSetupOnce {
                setupBannerIfNeeded()
                didSetupOnce = true
            }
            // 表示直後にも幅を確認して必要なら更新
            refreshBannerIfWidthChanged()
        }

        override func viewSafeAreaInsetsDidChange() {
            super.viewSafeAreaInsetsDidChange()
            refreshBannerIfWidthChanged()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            refreshBannerIfWidthChanged()
        }

        // MARK: - UI
        private func setupBottomBar() {
            bottomBar.translatesAutoresizingMaskIntoConstraints = false
            bottomBar.backgroundColor = UIColor(named: "NavBarColor")
            view.addSubview(bottomBar)

            NSLayoutConstraint.activate([
                bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                bottomBar.heightAnchor.constraint(equalToConstant: 10) // 下の余白（デザインに合わせて調整）
            ])
        }

        private func setupBannerIfNeeded() {
            guard bannerView == nil else { return }

            let banner = BannerView(adSize: AdSizeBanner) // 初期値。あとで適切サイズを設定
            banner.adUnitID = AdMobID.bannerUnitID
            print("Using adUnitID:", AdMobID.bannerUnitID)
            banner.rootViewController = self
            banner.delegate = self
            banner.translatesAutoresizingMaskIntoConstraints = false

            view.addSubview(banner)
            NSLayoutConstraint.activate([
                banner.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),
                banner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                banner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
            ])

            bannerView = banner
            loadAdaptiveAd()
        }

        // 画面のセーフエリア幅に合わせて Anchored Adaptive サイズを設定し直してロード
        private func loadAdaptiveAd() {
            guard let banner = bannerView else { return }
            let width = safeAreaContentWidth()
            guard width > 0 else { return }

            let adSize = currentOrientationAnchoredAdaptiveBanner(width: width)
            if !isAdSizeEqualToSize(size1: banner.adSize, size2: adSize) {
                banner.adSize = adSize
            }
            // rootViewController は毎回保証
            if banner.rootViewController == nil {
                banner.rootViewController = self
            }
            banner.isUserInteractionEnabled = true
            banner.load(Request())
            lastSafeWidth = width
        }

        // セーフエリアを差し引いた実質幅
        private func safeAreaContentWidth() -> CGFloat {
            let insets = view.safeAreaInsets
            let width = view.bounds.inset(by: UIEdgeInsets(top: 0, left: insets.left, bottom: 0, right: insets.right)).width
            return max(0, width.rounded(.down))
        }

        // 幅が変わっていたら再ロード
        private func refreshBannerIfWidthChanged() {
            let width = safeAreaContentWidth()
            guard width > 0 else { return }
            if abs(width - lastSafeWidth) >= 1 { // 1pt 以上の差で更新
                loadAdaptiveAd()
            }
        }

        // MARK: - BannerViewDelegate
        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            print("バナー広告の読み込みに成功しました (size: \(bannerView.adSize.size))")
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            print("バナー広告の読み込みに失敗: \(error.localizedDescription)")
        }

        func bannerViewDidRecordClick(_ bannerView: BannerView) {
            print("バナー広告がタップされました")
        }
    }
}
