import Foundation

struct Location: Codable {
    var latitude: Double
    var longitude: Double
}

struct Alarm: Codable {
    var name: String
    var repeatDays: [String]
    var sound: String
    var isAlarmEnabled: Bool // アラーム自体のオンオフ
    var isSoundEnabled: Bool // アラーム音のオンオフ
    var location: Location?
    var radius: Double?
    
    // 再入室時の再トリガー用フラグ（初期値 false）
    var hasTriggered: Bool = false
}
