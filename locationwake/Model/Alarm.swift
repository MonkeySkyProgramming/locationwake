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
    // 空配列またはnilは「繰り返さない」（次回の到着時に一度だけ通知）を表す。
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
    /// 新規保存・目的地変更・再有効化の直後に、現在が領域内かを確定するまで発火を保留する。
    var needsInitialStateCheck: Bool = false

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
            prepareForInitialStateCheck()
        }
    }

    mutating func prepareForInitialStateCheck() {
        hasTriggered = false
        hasTriggeredUntilExit = false
        needsInitialStateCheck = true
    }

    mutating func resolveInitialState(isInside: Bool) {
        needsInitialStateCheck = false
        hasTriggered = false
        hasTriggeredUntilExit = isInside
    }

    static func normalizedWeekdays(_ weekdays: [Int]?) -> [Int]? {
        guard let weekdays else { return nil }
        return Array(Set(weekdays.filter { (0...6).contains($0) })).sorted()
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
            normalized.repeatWeekdays = normalizedWeekdays(normalized.repeatWeekdays)
            return normalized
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, repeatWeekdays, sound, isAlarmEnabled, isSoundEnabled, isVibrationEnabled, location, radius, hasTriggered, hasTriggeredUntilExit, needsInitialStateCheck
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = (try? container.decode(String.self, forKey: .id)) ?? ""
        id = decodedID.isEmpty ? UUID().uuidString : decodedID
        name = try container.decode(String.self, forKey: .name)
        repeatWeekdays = Self.normalizedWeekdays(
            try container.decodeIfPresent([Int].self, forKey: .repeatWeekdays)
        )
        sound = try container.decode(String.self, forKey: .sound)
        isAlarmEnabled = try container.decode(Bool.self, forKey: .isAlarmEnabled)
        isSoundEnabled = try container.decode(Bool.self, forKey: .isSoundEnabled)
        isVibrationEnabled = try container.decodeIfPresent(Bool.self, forKey: .isVibrationEnabled) ?? false
        location = try container.decodeIfPresent(Location.self, forKey: .location)
        radius = try container.decodeIfPresent(Double.self, forKey: .radius)
        hasTriggered = try container.decodeIfPresent(Bool.self, forKey: .hasTriggered) ?? false
        hasTriggeredUntilExit = try container.decodeIfPresent(Bool.self, forKey: .hasTriggeredUntilExit) ?? false
        needsInitialStateCheck = try container.decodeIfPresent(Bool.self, forKey: .needsInitialStateCheck) ?? false
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        repeatWeekdays: [Int]? = [],
        sound: String,
        isAlarmEnabled: Bool,
        isSoundEnabled: Bool,
        isVibrationEnabled: Bool,
        location: Location? = nil,
        radius: Double? = nil,
        hasTriggered: Bool = false,
        hasTriggeredUntilExit: Bool = false,
        needsInitialStateCheck: Bool = false
    ) {
        self.id = id.isEmpty ? UUID().uuidString : id
        self.name = name
        self.repeatWeekdays = Self.normalizedWeekdays(repeatWeekdays)
        self.sound = sound
        self.isAlarmEnabled = isAlarmEnabled
        self.isSoundEnabled = isSoundEnabled
        self.isVibrationEnabled = isVibrationEnabled
        self.location = location
        self.radius = Self.normalizedRadius(radius)
        self.hasTriggered = hasTriggered
        self.hasTriggeredUntilExit = hasTriggeredUntilExit
        self.needsInitialStateCheck = needsInitialStateCheck
    }

    // default initializer remains available
}

enum AlarmStore {
    static let savedAlarmsKey = "SavedAlarms"

    enum LoadError: LocalizedError, Equatable {
        case unreadableData

        var errorDescription: String? {
            "保存したアラームを読み込めませんでした。もう一度お試しください。"
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> [Alarm] {
        switch loadResult(from: defaults) {
        case .success(let alarms):
            return alarms
        case .failure(let error):
#if DEBUG
            print("⚠️ event=alarmStoreLoadFailed reason=\(error.localizedDescription)")
#endif
            return []
        }
    }

    static func loadResult(
        from defaults: UserDefaults = .standard
    ) -> Result<[Alarm], LoadError> {
        guard let data = defaults.data(forKey: savedAlarmsKey) else {
            return .success([])
        }
        guard let decoded = try? JSONDecoder().decode([LossyAlarm].self, from: data) else {
            return .failure(.unreadableData)
        }

        let alarms = Alarm.normalizedForPersistence(decoded.compactMap(\.value))
        let discardedCount = decoded.count - alarms.count
        if discardedCount > 0 {
#if DEBUG
            print("⚠️ event=invalidSavedAlarmsDiscarded count=\(discardedCount)")
#endif
        }
        migrateLegacyTriggerState(for: alarms, defaults: defaults)
        if let normalizedData = try? JSONEncoder().encode(alarms), normalizedData != data {
            defaults.set(normalizedData, forKey: savedAlarmsKey)
        }
        return .success(alarms)
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
        for alarm in alarms {
            let legacySkipKey = "SkipTrigger_\(alarm.name)"
            let legacyTimestampKey = "SkipTriggerAt_\(alarm.name)"
            defaults.removeObject(forKey: legacySkipKey)
            defaults.removeObject(forKey: legacyTimestampKey)
            defaults.removeObject(forKey: "SkipTrigger_\(alarm.id)")
            defaults.removeObject(forKey: "SkipTriggerAt_\(alarm.id)")
        }
    }
}
