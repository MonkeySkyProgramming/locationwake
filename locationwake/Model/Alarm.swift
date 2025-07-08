import Foundation

struct Location: Codable {
    var latitude: Double
    var longitude: Double
}

struct Alarm: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var repeatWeekdays: [Int]? // 0:日曜〜6:土曜、繰り返し曜日
    var sound: String
    var isAlarmEnabled: Bool // アラーム自体のオンオフ
    var isSoundEnabled: Bool // アラーム音のオンオフ
    var isVibrationEnabled: Bool // バイブレーションのオンオフ
    var location: Location?
    var radius: Double?

    // 再入室時の再トリガー用フラグ（初期値 false）
    var hasTriggered: Bool = false
    var hasTriggeredUntilExit: Bool = false // 領域から出るまでトリガー禁止

    enum CodingKeys: String, CodingKey {
        case id, name, repeatWeekdays, sound, isAlarmEnabled, isSoundEnabled, isVibrationEnabled, location, radius, hasTriggered, hasTriggeredUntilExit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = try container.decode(String.self, forKey: .name)
        repeatWeekdays = try container.decodeIfPresent([Int].self, forKey: .repeatWeekdays)
        sound = try container.decode(String.self, forKey: .sound)
        isAlarmEnabled = try container.decode(Bool.self, forKey: .isAlarmEnabled)
        isSoundEnabled = try container.decode(Bool.self, forKey: .isSoundEnabled)
        isVibrationEnabled = try container.decode(Bool.self, forKey: .isVibrationEnabled)
        location = try container.decodeIfPresent(Location.self, forKey: .location)
        radius = try container.decodeIfPresent(Double.self, forKey: .radius)
        hasTriggered = try container.decodeIfPresent(Bool.self, forKey: .hasTriggered) ?? false
        hasTriggeredUntilExit = try container.decodeIfPresent(Bool.self, forKey: .hasTriggeredUntilExit) ?? false
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        repeatWeekdays: [Int]? = nil,
        sound: String,
        isAlarmEnabled: Bool,
        isSoundEnabled: Bool,
        isVibrationEnabled: Bool,
        location: Location? = nil,
        radius: Double? = nil,
        hasTriggered: Bool = false,
        hasTriggeredUntilExit: Bool = false
    ) {
        self.id = id
        self.name = name
        self.repeatWeekdays = repeatWeekdays
        self.sound = sound
        self.isAlarmEnabled = isAlarmEnabled
        self.isSoundEnabled = isSoundEnabled
        self.isVibrationEnabled = isVibrationEnabled
        self.location = location
        self.radius = radius
        self.hasTriggered = hasTriggered
        self.hasTriggeredUntilExit = hasTriggeredUntilExit
    }

    // default initializer remains available
}
