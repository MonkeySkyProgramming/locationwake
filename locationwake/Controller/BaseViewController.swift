import UIKit
import GoogleMobileAds

class BaseViewController: UIViewController, BannerViewDelegate {

    var bannerView: BannerView!
    var bottomBar: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupBottomBar()
        setupBannerAd()
    }
    
    /// バナー広告のセットアップ処理
    func setupBannerAd() {
        // バナーのインスタンスを生成（ここでは標準サイズを利用）
        bannerView = BannerView(adSize: AdSizeBanner)
        // テスト用ユニットID（実際の運用時は自分の広告ユニットIDに変更）
        bannerView.adUnitID = "ca-app-pub-6138612098991276/9793223407"
        bannerView.rootViewController = self
        bannerView.delegate = self
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        
        // 画面の下部に広告バナーを配置するため、ビューに追加
        view.addSubview(bannerView)
        
        // Auto Layout を利用して、画面下部（安全エリア内）の中央に配置する
        NSLayoutConstraint.activate([
            bannerView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),
            bannerView.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        
        // 広告のリクエストを発行
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
