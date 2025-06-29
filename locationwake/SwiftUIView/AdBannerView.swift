import SwiftUI
import GoogleMobileAds
import Foundation
import AdSupport
import AppTrackingTransparency

struct AdBannerView: UIViewControllerRepresentable {
    
    func makeUIViewController(context: Context) -> UIViewController {
        return BannerHostingController()
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // 更新処理なし
    }
    
    private class BannerHostingController: UIViewController, BannerViewDelegate {
        var bannerView: BannerView!
        var bottomBar: UIView!
        
        override func viewDidLoad() {
            super.viewDidLoad()
            setupBottomBar()
            setupBannerAd()
        }
        
        private func setupBannerAd() {
            bannerView = BannerView(adSize: AdSizeBanner)
            bannerView.adUnitID = AdMobID.bannerUnitID
            bannerView.rootViewController = self
            bannerView.delegate = self
            bannerView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(bannerView)
            
            NSLayoutConstraint.activate([
                bannerView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),
                bannerView.centerXAnchor.constraint(equalTo: view.centerXAnchor)
            ])
            
            bannerView.load(Request())
        }
        
        private func setupBottomBar() {
            bottomBar = UIView()
            bottomBar.translatesAutoresizingMaskIntoConstraints = false
            bottomBar.backgroundColor = UIColor(named: "NavBarColor")
            view.addSubview(bottomBar)

            NSLayoutConstraint.activate([
                bottomBar.heightAnchor.constraint(equalToConstant: 44),
                bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
        
        // MARK: - GADBannerViewDelegate
        
        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            print("バナー広告の読み込みに成功しました")
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            print("バナー広告の読み込みに失敗しました: \(error.localizedDescription)")
        }
    }
}
