import Foundation

struct Location: Codable, Equatable {
    var latitude: Double
    var longitude: Double
}

struct Alarm: Codable, Identifiable, Equatable {
    static let minimumGeofenceRadius = 100.0
    static let maximumGeofenceRadius = 1_000.0
    static let defaultGeofenceRadius = 300.0

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

    static func normalizedRadius(_ radius: Double?) -> Double? {
        guard let radius else { return nil }
        return min(max(radius, minimumGeofenceRadius), maximumGeofenceRadius)
    }

    var geofenceRadius: Double? {
        Self.normalizedRadius(radius)
    }

    static func normalizedForPersistence(_ alarms: [Alarm]) -> [Alarm] {
        alarms.map { alarm in
            var normalized = alarm
            if normalized.id.isEmpty {
                normalized.id = UUID().uuidString
            }
            normalized.radius = normalizedRadius(normalized.radius)
            return normalized
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, repeatWeekdays, sound, isAlarmEnabled, isSoundEnabled, isVibrationEnabled, location, radius, hasTriggered, hasTriggeredUntilExit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = (try? container.decode(String.self, forKey: .id)) ?? ""
        id = decodedID.isEmpty ? UUID().uuidString : decodedID
        name = try container.decode(String.self, forKey: .name)
        repeatWeekdays = try container.decodeIfPresent([Int].self, forKey: .repeatWeekdays)
        sound = try container.decode(String.self, forKey: .sound)
        isAlarmEnabled = try container.decode(Bool.self, forKey: .isAlarmEnabled)
        isSoundEnabled = try container.decode(Bool.self, forKey: .isSoundEnabled)
        isVibrationEnabled = try container.decodeIfPresent(Bool.self, forKey: .isVibrationEnabled) ?? false
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
        self.id = id.isEmpty ? UUID().uuidString : id
        self.name = name
        self.repeatWeekdays = repeatWeekdays
        self.sound = sound
        self.isAlarmEnabled = isAlarmEnabled
        self.isSoundEnabled = isSoundEnabled
        self.isVibrationEnabled = isVibrationEnabled
        self.location = location
        self.radius = Self.normalizedRadius(radius)
        self.hasTriggered = hasTriggered
        self.hasTriggeredUntilExit = hasTriggeredUntilExit
    }

    // default initializer remains available
}
