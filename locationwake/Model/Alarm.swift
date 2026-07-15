import Foundation

struct Location: Codable, Equatable {
    var latitude: Double
    var longitude: Double
}

struct Alarm: Codable, Identifiable, Equatable {
    static let minimumGeofenceRadius = 100.0
    static let maximumGeofenceRadius = 10_000.0
    static let defaultGeofenceRadius = 300.0
    static let maximumSavedAlarms = 20

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

    mutating func setEnabled(_ enabled: Bool) {
        let isBeingReenabled = enabled && !isAlarmEnabled
        isAlarmEnabled = enabled
        if isBeingReenabled {
            hasTriggered = false
            hasTriggeredUntilExit = false
        }
    }

    static func normalizedForPersistence(_ alarms: [Alarm]) -> [Alarm] {
        var usedIDs = Set<String>()
        return alarms.map { alarm in
            var normalized = alarm
            if normalized.id.isEmpty || usedIDs.contains(normalized.id) {
                normalized.id = UUID().uuidString
            }
            usedIDs.insert(normalized.id)
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

enum AlarmStore {
    static let savedAlarmsKey = "SavedAlarms"

    static func load(from defaults: UserDefaults = .standard) -> [Alarm] {
        guard let data = defaults.data(forKey: savedAlarmsKey),
              let decoded = try? JSONDecoder().decode([LossyAlarm].self, from: data) else {
            return []
        }

        let alarms = Alarm.normalizedForPersistence(decoded.compactMap(\.value))
        let discardedCount = decoded.count - alarms.count
        if discardedCount > 0 {
            print("⚠️ event=invalidSavedAlarmsDiscarded count=\(discardedCount)")
        }
        migrateLegacyTriggerState(for: alarms, defaults: defaults)
        if let normalizedData = try? JSONEncoder().encode(alarms), normalizedData != data {
            defaults.set(normalizedData, forKey: savedAlarmsKey)
        }
        return alarms
    }

    private struct LossyAlarm: Decodable {
        let value: Alarm?

        init(from decoder: Decoder) throws {
            value = try? Alarm(from: decoder)
        }
    }

    static func save(_ alarms: [Alarm], to defaults: UserDefaults = .standard) {
        let normalized = Alarm.normalizedForPersistence(alarms)
        if let data = try? JSONEncoder().encode(normalized) {
            defaults.set(data, forKey: savedAlarmsKey)
        }
    }

    private static func migrateLegacyTriggerState(for alarms: [Alarm], defaults: UserDefaults) {
        let nameCounts = Dictionary(grouping: alarms, by: \.name).mapValues(\.count)
        for alarm in alarms {
            let legacySkipKey = "SkipTrigger_\(alarm.name)"
            let legacyTimestampKey = "SkipTriggerAt_\(alarm.name)"

            if nameCounts[alarm.name] == 1 {
                if defaults.bool(forKey: legacySkipKey) {
                    defaults.set(true, forKey: "SkipTrigger_\(alarm.id)")
                }
                if let timestamp = defaults.object(forKey: legacyTimestampKey) as? Date,
                   Date().timeIntervalSince(timestamp) < AlarmTriggerPolicy.saveSkipInterval {
                    defaults.set(timestamp, forKey: "SkipTriggerAt_\(alarm.id)")
                }
            }

            defaults.removeObject(forKey: legacySkipKey)
            defaults.removeObject(forKey: legacyTimestampKey)
        }
    }
}
