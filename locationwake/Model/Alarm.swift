import CoreFoundation
import Foundation

struct Location: Codable, Equatable {
    var latitude: Double
    var longitude: Double
}

struct PendingArrivalDelivery: Codable, Equatable, Identifiable {
    let occurrenceID: String
    var shouldRing: Bool?
    /// falseは鳴動予約を保存済みだが再生開始前、trueは再生開始済み。
    /// nilは旧データまたは通知のみを表す。
    var didActivateRinging: Bool? = nil

    var id: String { occurrenceID }
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
    /// Core Location の遅延 callback を、現在の保存・再有効化世代と照合するためのID。
    var monitoringSessionID: String = UUID().uuidString
    /// 保存前に取得された位置で初期状態を誤って解決しないための開始時刻。
    var initialStateCheckBeganAt: Date?
    /// 発火状態の保存後、通知・鳴動の配送が完了するまで保持するoutbox ID。
    var pendingArrivalOccurrenceID: String?
    /// nilは配送判定前、trueは一次鳴動、falseは後続通知を表す。
    var pendingArrivalShouldRing: Bool?
    /// 同じ繰り返しalarmで前回の通知登録が失敗していても、次の到着を失わない配送queue。
    var pendingArrivalDeliveries: [PendingArrivalDelivery] = []

    var isArrivalDeliveryPending: Bool {
        !pendingArrivalDeliveries.isEmpty || pendingArrivalOccurrenceID != nil
    }

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

    mutating func prepareForInitialStateCheck(
        sessionID: String = UUID().uuidString,
        now: Date = Date()
    ) {
        hasTriggered = false
        hasTriggeredUntilExit = false
        needsInitialStateCheck = true
        monitoringSessionID = sessionID.isEmpty ? UUID().uuidString : sessionID
        initialStateCheckBeganAt = now
    }

    mutating func resolveInitialState(isInside: Bool) {
        needsInitialStateCheck = false
        hasTriggered = false
        hasTriggeredUntilExit = isInside
        initialStateCheckBeganAt = nil
    }

    func canResolveInitialState(usingLocationTimestamp timestamp: Date) -> Bool {
        guard needsInitialStateCheck else { return false }
        guard let initialStateCheckBeganAt else {
            // 旧バージョンで保留中だったデータは、最初の有効な観測で移行する。
            return true
        }
        return timestamp >= initialStateCheckBeganAt
    }

    mutating func rebaseInitialStateCheckIfClockMovedBackward(now: Date) {
        guard needsInitialStateCheck,
              let beganAt = initialStateCheckBeganAt,
              beganAt > now else {
            return
        }
        initialStateCheckBeganAt = now
    }

    mutating func enqueueArrivalDelivery(occurrenceID: String) {
        guard !occurrenceID.isEmpty,
              !pendingArrivalDeliveries.contains(where: {
                  $0.occurrenceID == occurrenceID
              }) else {
            return
        }
        pendingArrivalDeliveries.append(
            PendingArrivalDelivery(
                occurrenceID: occurrenceID,
                shouldRing: nil
            )
        )
        synchronizeLegacyPendingArrivalFields()
    }

    mutating func setArrivalDeliveryDecision(
        occurrenceID: String,
        shouldRing: Bool
    ) {
        guard let index = pendingArrivalDeliveries.firstIndex(where: {
            $0.occurrenceID == occurrenceID
        }) else {
            return
        }
        pendingArrivalDeliveries[index].shouldRing = shouldRing
        pendingArrivalDeliveries[index].didActivateRinging = shouldRing
            ? false
            : nil
        synchronizeLegacyPendingArrivalFields()
    }

    mutating func markArrivalDeliveryActivated(occurrenceID: String) {
        guard let index = pendingArrivalDeliveries.firstIndex(where: {
            $0.occurrenceID == occurrenceID && $0.shouldRing == true
        }) else {
            return
        }
        pendingArrivalDeliveries[index].didActivateRinging = true
        synchronizeLegacyPendingArrivalFields()
    }

    mutating func acknowledgeArrivalDelivery(occurrenceID: String) {
        pendingArrivalDeliveries.removeAll {
            $0.occurrenceID == occurrenceID
        }
        synchronizeLegacyPendingArrivalFields()
    }

    func arrivalDelivery(
        occurrenceID: String
    ) -> PendingArrivalDelivery? {
        pendingArrivalDeliveries.first {
            $0.occurrenceID == occurrenceID
        }
    }

    private mutating func normalizePendingArrivalDeliveries() {
        if pendingArrivalDeliveries.isEmpty,
           let pendingArrivalOccurrenceID,
           !pendingArrivalOccurrenceID.isEmpty {
            pendingArrivalDeliveries = [
                PendingArrivalDelivery(
                    occurrenceID: pendingArrivalOccurrenceID,
                    shouldRing: pendingArrivalShouldRing
                )
            ]
        }

        var usedOccurrenceIDs = Set<String>()
        pendingArrivalDeliveries = pendingArrivalDeliveries.filter {
            !$0.occurrenceID.isEmpty
                && usedOccurrenceIDs.insert($0.occurrenceID).inserted
        }
        synchronizeLegacyPendingArrivalFields()
    }

    private mutating func synchronizeLegacyPendingArrivalFields() {
        pendingArrivalOccurrenceID = pendingArrivalDeliveries.first?.occurrenceID
        pendingArrivalShouldRing = pendingArrivalDeliveries.first?.shouldRing
    }

    static func normalizedWeekdays(_ weekdays: [Int]?) -> [Int]? {
        guard let weekdays else { return nil }
        return Array(Set(weekdays.filter { (0...6).contains($0) })).sorted()
    }

    static func normalizedForPersistence(_ alarms: [Alarm]) -> [Alarm] {
        var usedIDs = Set<String>()
        var usedMonitoringSessionIDs = Set<String>()
        return alarms.map { alarm in
            var normalized = alarm
            if normalized.id.isEmpty || usedIDs.contains(normalized.id) {
                normalized.id = UUID().uuidString
            }
            usedIDs.insert(normalized.id)
            if normalized.monitoringSessionID.isEmpty
                || usedMonitoringSessionIDs.contains(normalized.monitoringSessionID) {
                let replacementSessionID = UUID().uuidString
                if normalized.isAlarmEnabled {
                    normalized.prepareForInitialStateCheck(
                        sessionID: replacementSessionID
                    )
                } else {
                    normalized.monitoringSessionID = replacementSessionID
                }
            }
            usedMonitoringSessionIDs.insert(normalized.monitoringSessionID)
            normalized.radius = normalizedRadius(normalized.radius)
            normalized.repeatWeekdays = normalizedWeekdays(normalized.repeatWeekdays)
            if !normalized.needsInitialStateCheck {
                normalized.initialStateCheckBeganAt = nil
            }
            normalized.normalizePendingArrivalDeliveries()
            return normalized
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, repeatWeekdays, sound, isAlarmEnabled, isSoundEnabled, isVibrationEnabled, location, radius, hasTriggered, hasTriggeredUntilExit, needsInitialStateCheck, monitoringSessionID, initialStateCheckBeganAt, pendingArrivalOccurrenceID, pendingArrivalShouldRing, pendingArrivalDeliveries
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
        let decodedSessionID = try container.decodeIfPresent(
            String.self,
            forKey: .monitoringSessionID
        )
        let isLegacyMonitoringSession = decodedSessionID?.isEmpty != false
        monitoringSessionID = isLegacyMonitoringSession
            ? UUID().uuidString
            : decodedSessionID ?? UUID().uuidString
        initialStateCheckBeganAt = try container.decodeIfPresent(
            Date.self,
            forKey: .initialStateCheckBeganAt
        )
        if isLegacyMonitoringSession && isAlarmEnabled {
            // 公開済み版のregion callbackと新実装の状態を混同しないよう、
            // 更新後の最初のinside/outside判定までは発火を保留する。
            needsInitialStateCheck = true
            initialStateCheckBeganAt = Date()
        }
        if !needsInitialStateCheck {
            initialStateCheckBeganAt = nil
        }
        pendingArrivalOccurrenceID = try container.decodeIfPresent(
            String.self,
            forKey: .pendingArrivalOccurrenceID
        )
        pendingArrivalShouldRing = try container.decodeIfPresent(
            Bool.self,
            forKey: .pendingArrivalShouldRing
        )
        pendingArrivalDeliveries = try container.decodeIfPresent(
            [PendingArrivalDelivery].self,
            forKey: .pendingArrivalDeliveries
        ) ?? []
        normalizePendingArrivalDeliveries()
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
        needsInitialStateCheck: Bool = false,
        monitoringSessionID: String = UUID().uuidString,
        initialStateCheckBeganAt: Date? = nil,
        pendingArrivalOccurrenceID: String? = nil,
        pendingArrivalShouldRing: Bool? = nil,
        pendingArrivalDeliveries: [PendingArrivalDelivery] = []
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
        self.monitoringSessionID = monitoringSessionID.isEmpty
            ? UUID().uuidString
            : monitoringSessionID
        self.initialStateCheckBeganAt = needsInitialStateCheck
            ? initialStateCheckBeganAt
            : nil
        self.pendingArrivalOccurrenceID = pendingArrivalOccurrenceID
        self.pendingArrivalShouldRing = pendingArrivalOccurrenceID == nil
            ? nil
            : pendingArrivalShouldRing
        self.pendingArrivalDeliveries = pendingArrivalDeliveries
        normalizePendingArrivalDeliveries()
    }

    // default initializer remains available
}

enum AlarmStore {
    // 公開版との永続化契約。アプリ更新時のUserDefaultsをそのまま読み込むため、
    // このキーは移行手段を用意せず変更してはいけない。
    static let savedAlarmsKey = "SavedAlarms"
    static let migrationBackupKey = "SavedAlarmsMigrationBackupV1"
    static let corruptPrimaryBackupKey = "SavedAlarmsCorruptPrimaryV1"
    static let recoveryInProgressKey = "SavedAlarmsRecoveryInProgressV1"

    enum LoadError: LocalizedError, Equatable {
        case unreadableData

        var errorDescription: String? {
            "保存したアラームを読み込めませんでした。もう一度お試しください。"
        }
    }

    enum SaveError: LocalizedError, Equatable {
        case encodingFailed

        var errorDescription: String? {
            "アラームを保存できませんでした。入力内容を確認して、もう一度お試しください。"
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
        guard let storedPrimary = defaults.object(
            forKey: savedAlarmsKey
        ) else {
            return .success([])
        }

        guard let data = defaults.data(forKey: savedAlarmsKey) else {
            return recoverFromMigrationBackup(
                corruptedPrimary: storedPrimary,
                defaults: defaults
            ) ?? .failure(.unreadableData)
        }
        guard let payload = decodePayload(data) else {
            return recoverFromMigrationBackup(
                corruptedPrimary: storedPrimary,
                defaults: defaults
            ) ?? .failure(.unreadableData)
        }

        if payload.normalizedData != data {
            if defaults.object(forKey: migrationBackupKey) == nil {
                defaults.set(data, forKey: migrationBackupKey)
            }
            defaults.set(payload.normalizedData, forKey: savedAlarmsKey)
        }
        // 正規化データと移行前バックアップを保存できた後にだけ、旧版の
        // 一時状態を削除する。途中終了でも公開版データを復元可能に保つ。
        defaults.removeObject(forKey: recoveryInProgressKey)
        migrateLegacyTriggerState(for: payload.alarms, defaults: defaults)
        return .success(payload.alarms)
    }

    private struct DecodedPayload {
        let alarms: [Alarm]
        let normalizedData: Data
    }

    private static func decodePayload(_ data: Data) -> DecodedPayload? {
        guard let decoded = try? JSONDecoder().decode(
            [LossyAlarm].self,
            from: data
        ) else {
            return nil
        }

        let alarms = Alarm.normalizedForPersistence(decoded.compactMap(\.value))
        let discardedCount = decoded.count - alarms.count
        guard !((!decoded.isEmpty && alarms.isEmpty) || discardedCount > 0),
              let normalizedData = try? encode(alarms) else {
            return nil
        }
        return DecodedPayload(
            alarms: alarms,
            normalizedData: normalizedData
        )
    }

    /// 正規化前の公開版データから自動復旧する。破損したprimaryも別キーへ
    /// write-onceで保全し、復旧によって調査可能な元データを失わない。
    private static func recoverFromMigrationBackup(
        corruptedPrimary: Any?,
        defaults: UserDefaults
    ) -> Result<[Alarm], LoadError>? {
        guard let backupData = defaults.data(forKey: migrationBackupKey),
              let payload = decodePayload(backupData),
              let corruptedPrimary else {
            return nil
        }

        if let existingCorruptPrimary = defaults.object(
            forKey: corruptPrimaryBackupKey
        ) {
            // 明示的なtransaction markerがあり、snapshotと現primaryが
            // 型も含めて同一の場合だけ、中断した初回復旧を再開する。
            guard defaults.string(forKey: recoveryInProgressKey) != nil else {
                defaults.removeObject(forKey: recoveryInProgressKey)
                return nil
            }
            guard storedValuesAreStrictlyEqual(
                existingCorruptPrimary,
                corruptedPrimary
            ) else {
                // snapshot後にprimaryが変わった場合は別の破損として扱い、
                // 古いbackupを後から誤適用しないようtransactionを破棄する。
                defaults.removeObject(forKey: recoveryInProgressKey)
                return nil
            }
        } else {
            if defaults.string(forKey: recoveryInProgressKey) == nil {
                defaults.set(
                    UUID().uuidString,
                    forKey: recoveryInProgressKey
                )
            }
            defaults.set(corruptedPrimary, forKey: corruptPrimaryBackupKey)
        }
        defaults.set(payload.normalizedData, forKey: savedAlarmsKey)
        defaults.removeObject(forKey: recoveryInProgressKey)
        migrateLegacyTriggerState(for: payload.alarms, defaults: defaults)
#if DEBUG
        print("ℹ️ event=alarmStoreRecoveredFromMigrationBackup count=\(payload.alarms.count)")
#endif
        return .success(payload.alarms)
    }

    private static func storedValuesAreStrictlyEqual(
        _ lhs: Any,
        _ rhs: Any
    ) -> Bool {
        switch (lhs, rhs) {
        case let (lhsData as Data, rhsData as Data):
            return lhsData == rhsData
        case let (lhsString as String, rhsString as String):
            return lhsString == rhsString
        case let (lhsDate as Date, rhsDate as Date):
            return lhsDate == rhsDate
        case let (lhsArray as [Any], rhsArray as [Any]):
            guard lhsArray.count == rhsArray.count else { return false }
            return zip(lhsArray, rhsArray).allSatisfy {
                storedValuesAreStrictlyEqual($0, $1)
            }
        case let (
            lhsDictionary as [String: Any],
            rhsDictionary as [String: Any]
        ):
            guard lhsDictionary.count == rhsDictionary.count,
                  Set(lhsDictionary.keys) == Set(rhsDictionary.keys) else {
                return false
            }
            return lhsDictionary.allSatisfy { key, lhsValue in
                guard let rhsValue = rhsDictionary[key] else { return false }
                return storedValuesAreStrictlyEqual(lhsValue, rhsValue)
            }
        case let (lhsNumber as NSNumber, rhsNumber as NSNumber):
            let lhsIsBoolean = CFGetTypeID(lhsNumber) == CFBooleanGetTypeID()
            let rhsIsBoolean = CFGetTypeID(rhsNumber) == CFBooleanGetTypeID()
            return lhsIsBoolean == rhsIsBoolean
                && String(cString: lhsNumber.objCType)
                == String(cString: rhsNumber.objCType)
                && lhsNumber.isEqual(rhsNumber)
        default:
            return false
        }
    }

    private static func encode(_ alarms: [Alarm]) throws -> Data {
        let encoder = JSONEncoder()
        // 同じ状態を読み込むたびにkey順だけで再書き込みしないよう固定する。
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(alarms)
    }

    private struct LossyAlarm: Decodable {
        let value: Alarm?

        init(from decoder: Decoder) throws {
            value = try? Alarm(from: decoder)
        }
    }

    @discardableResult
    static func save(
        _ alarms: [Alarm],
        to defaults: UserDefaults = .standard
    ) -> Result<Void, SaveError> {
        let normalized = Alarm.normalizedForPersistence(alarms)
        do {
            let data = try encode(normalized)
            defaults.set(data, forKey: savedAlarmsKey)
            return .success(())
        } catch {
#if DEBUG
            print("⚠️ event=alarmStoreSaveFailed reason=\(error.localizedDescription)")
#endif
            return .failure(.encodingFailed)
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
