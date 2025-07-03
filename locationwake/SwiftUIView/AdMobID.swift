import Foundation
import AdSupport
import AppTrackingTransparency

struct AdMobID {
    static var bannerUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/2934735716" // Test ID
        #else
        let productionIDs = [
            "ca-app-pub-6138612098991276/9793223407",
            "ca-app-pub-6138612098991276/2985866735"
        ]
        return productionIDs.randomElement()!
        #endif
    }
}

// Rest of the code in AdBannerView.swift

func setupBannerAd() {
    // Rest of the setupBannerAd code
}
