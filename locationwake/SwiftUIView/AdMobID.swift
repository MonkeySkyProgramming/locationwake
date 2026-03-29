import Foundation
import AdSupport
import AppTrackingTransparency

struct AdMobID {
    static var bannerUnitID: String {

        let productionIDs = [
            "ca-app-pub-6138612098991276/9793223407",
            "ca-app-pub-6138612098991276/2985866735"
        ]
        return productionIDs.randomElement()!
    }
}

// Rest of the code in AdBannerView.swift

func setupBannerAd() {
    // Rest of the setupBannerAd code
}
