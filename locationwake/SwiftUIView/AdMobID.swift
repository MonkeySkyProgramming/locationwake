import Foundation
import AdSupport
import AppTrackingTransparency

struct AdMobID {
    static var bannerUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/2934735716" // Test ID
        #else
        return "ca-app-pub-6138612098991276/9793223407" // Production ID
        #endif
    }
}

// Rest of the code in AdBannerView.swift

func setupBannerAd() {
    // Rest of the setupBannerAd code
}
