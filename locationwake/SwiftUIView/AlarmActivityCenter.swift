import Combine
import Foundation

enum AlarmPlaybackDecision: Equatable {
    case ring
    case notifyOnly
}

struct AlarmPlaybackStateMachine: Equatable {
    private(set) var activeAlarmID: String?
    private(set) var activeOccurrenceID: String?

    init(
        activeAlarmID: String? = nil,
        activeOccurrenceID: String? = nil
    ) {
        self.activeAlarmID = activeAlarmID
        self.activeOccurrenceID = activeAlarmID == nil
            ? nil
            : activeOccurrenceID
    }

    mutating func registerArrival(
        alarmID: String,
        occurrenceID: String,
        recoveringPendingDelivery: Bool = false
    ) -> AlarmPlaybackDecision {
        if recoveringPendingDelivery
            && activeAlarmID == alarmID
            && activeOccurrenceID == occurrenceID {
            // outbox再配送は同じ所有者の冪等な再開として扱う。
            return .ring
        }
        guard activeAlarmID == nil else {
            return .notifyOnly
        }
        activeAlarmID = alarmID
        activeOccurrenceID = occurrenceID
        return .ring
    }

    mutating func stop(alarmID: String) -> Bool {
        guard activeAlarmID == alarmID else { return false }
        activeAlarmID = nil
        activeOccurrenceID = nil
        return true
    }

    func ownsPlayback(
        alarmID: String,
        occurrenceID: String
    ) -> Bool {
        activeAlarmID == alarmID && activeOccurrenceID == occurrenceID
    }
}

struct ActiveAlarmPresentation: Identifiable, Equatable {
    let alarmID: String
    let name: String

    var id: String { alarmID }
}

/// 到着アラームの再生状態を一か所で管理する。
///
/// 最初に到着した1件だけが音・振動を開始し、その後の到着は通知だけを残す。
/// 停止は、表示中のアラームIDと一致する停止ボタンからのみ受け付ける。
final class AlarmActivityCenter: ObservableObject {
    static let shared = AlarmActivityCenter()

    @Published private(set) var activeAlarm: ActiveAlarmPresentation?

    private struct PlaybackConfiguration {
        let sound: String
        let isSoundEnabled: Bool
        let isVibrationEnabled: Bool
    }

    /// 再生所有権と再開設定を1つのDataとして保存し、部分書き込みを防ぐ。
    private struct PersistedActiveAlarm: Codable {
        let alarmID: String
        let occurrenceID: String
        let name: String
        let sound: String?
        let isSoundEnabled: Bool?
        let isVibrationEnabled: Bool?
    }

    private enum DefaultsKey {
        static let activeAlarmRecord = "ActiveAlarmRecordV1"
        // 公開済み版・開発途中版からのactive state移行用legacy keys。
        static let activeAlarmID = "ActiveAlarmID"
        static let activeOccurrenceID = "ActiveAlarmOccurrenceID"
        static let activeAlarmName = "ActiveAlarmName"
        static let activeAlarmSound = "ActiveAlarmSound"
        static let activeAlarmSoundEnabled = "ActiveAlarmSoundEnabled"
        static let activeAlarmVibrationEnabled = "ActiveAlarmVibrationEnabled"
    }

    private let defaults: UserDefaults
    private var stateMachine: AlarmPlaybackStateMachine

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let persistedRecord: PersistedActiveAlarm?
        if let currentRecord = Self.persistedRecord(in: defaults) {
            persistedRecord = currentRecord
            Self.clearLegacyPersistedState(in: defaults)
        } else if let legacyRecord = Self.legacyPersistedRecord(in: defaults) {
            persistedRecord = legacyRecord
            if Self.persist(legacyRecord, in: defaults) {
                Self.clearLegacyPersistedState(in: defaults)
            }
        } else {
            persistedRecord = nil
        }
        stateMachine = AlarmPlaybackStateMachine(
            activeAlarmID: persistedRecord?.alarmID,
            activeOccurrenceID: persistedRecord?.occurrenceID
        )

        if let persistedRecord {
            activeAlarm = ActiveAlarmPresentation(
                alarmID: persistedRecord.alarmID,
                name: persistedRecord.name
            )
        }
    }

    static func hasPersistedState(
        in defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.object(forKey: DefaultsKey.activeAlarmRecord) != nil
            || defaults.object(forKey: DefaultsKey.activeAlarmID) != nil
    }

    static func resetPersistedState(
        in defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: DefaultsKey.activeAlarmRecord)
        clearLegacyPersistedState(in: defaults)
    }

    func isPlaybackActivated(
        alarmID: String,
        occurrenceID: String
    ) -> Bool {
        performOnMainSynchronously {
            guard let record = Self.persistedRecord(in: defaults) else {
                return false
            }
            return record.alarmID == alarmID
                && record.occurrenceID == occurrenceID
        }
    }

    @discardableResult
    func registerArrival(
        for alarm: Alarm,
        occurrenceID: String = UUID().uuidString,
        recoveringPendingDelivery: Bool = false
    ) -> AlarmPlaybackDecision {
        let decision = reserveArrival(
            alarmID: alarm.id,
            occurrenceID: occurrenceID,
            recoveringPendingDelivery: recoveringPendingDelivery
        )
        if decision == .ring {
            _ = activateReservedArrival(
                for: alarm,
                occurrenceID: occurrenceID
            )
        }
        return decision
    }

    /// 最初の到着に再生所有権だけを予約し、音・振動・画面・永続状態は変更しない。
    /// 呼び出し元は到着判断の保存に成功した後で `activateReservedArrival` を呼ぶ。
    @discardableResult
    func reserveArrival(
        alarmID: String,
        occurrenceID: String,
        recoveringPendingDelivery: Bool = false
    ) -> AlarmPlaybackDecision {
        performOnMainSynchronously {
            stateMachine.registerArrival(
                alarmID: alarmID,
                occurrenceID: occurrenceID,
                recoveringPendingDelivery: recoveringPendingDelivery
            )
        }
    }

    /// 保存済みの予約だけを実際の鳴動へ昇格する。
    @discardableResult
    func activateReservedArrival(
        for alarm: Alarm,
        occurrenceID: String
    ) -> Bool {
        performOnMainSynchronously {
            guard stateMachine.ownsPlayback(
                alarmID: alarm.id,
                occurrenceID: occurrenceID
            ) else {
                return false
            }

            let record = PersistedActiveAlarm(
                alarmID: alarm.id,
                occurrenceID: occurrenceID,
                name: alarm.name,
                sound: alarm.sound,
                isSoundEnabled: alarm.isSoundEnabled,
                isVibrationEnabled: alarm.isVibrationEnabled
            )
            guard Self.persist(record, in: defaults) else {
                return false
            }
            activeAlarm = ActiveAlarmPresentation(
                alarmID: alarm.id,
                name: alarm.name
            )
            startPlayback(
                alarmID: alarm.id,
                configuration: PlaybackConfiguration(
                    sound: alarm.sound,
                    isSoundEnabled: alarm.isSoundEnabled,
                    isVibrationEnabled: alarm.isVibrationEnabled
                )
            )
            NotificationCenter.default.post(
                name: .activeAlarmDidChange,
                object: nil
            )
            return true
        }
    }

    /// 保存に失敗した予約を、ユーザーに見える副作用を発生させず解放する。
    @discardableResult
    func releaseReservedArrival(
        alarmID: String,
        occurrenceID: String
    ) -> Bool {
        performOnMainSynchronously {
            guard stateMachine.ownsPlayback(
                alarmID: alarmID,
                occurrenceID: occurrenceID
            ) else {
                return false
            }
            return stateMachine.stop(alarmID: alarmID)
        }
    }

    /// 通知から開いた時は消音せず、現在鳴っているアラームの停止画面だけを前面に出す。
    func presentCurrentAlarmIfNeeded() {
        performOnMainSynchronously {
            guard let alarmID = stateMachine.activeAlarmID else { return }
            let alarmName = Self.persistedRecord(in: defaults)?.name
                ?? "到着アラーム"
            activeAlarm = ActiveAlarmPresentation(
                alarmID: alarmID,
                name: alarmName
            )
            if let configuration = playbackConfiguration(for: alarmID) {
                startPlayback(
                    alarmID: alarmID,
                    configuration: configuration
                )
            }
            NotificationCenter.default.post(
                name: .activeAlarmDidChange,
                object: nil
            )
        }
    }

    @discardableResult
    func stop(alarmID: String) -> Bool {
        performOnMainSynchronously {
            let occurrenceID = stateMachine.activeOccurrenceID
            guard stateMachine.stop(alarmID: alarmID) else { return false }

            Self.resetPersistedState(in: defaults)
            SoundPlayer.shared.stopAlarm(id: alarmID)
            HapticManager.stopAlarm(id: alarmID)
            AlarmScheduler.cancelNotification(identifier: alarmID)
            if let occurrenceID {
                AlarmScheduler.cancelNotification(
                    identifier: AlarmScheduler.notificationIdentifier(
                        alarmID: alarmID,
                        occurrenceID: occurrenceID
                    )
                )
            }
            if activeAlarm?.alarmID == alarmID {
                activeAlarm = nil
            }
            NotificationCenter.default.post(
                name: .activeAlarmDidChange,
                object: nil
            )
            return true
        }
    }

    func ownsPlayback(
        alarmID: String,
        occurrenceID: String
    ) -> Bool {
        performOnMainSynchronously {
            stateMachine.ownsPlayback(
                alarmID: alarmID,
                occurrenceID: occurrenceID
            )
        }
    }

    private func playbackConfiguration(
        for alarmID: String
    ) -> PlaybackConfiguration? {
        if let record = Self.persistedRecord(in: defaults),
           record.alarmID == alarmID,
           let sound = record.sound,
           let isSoundEnabled = record.isSoundEnabled,
           let isVibrationEnabled = record.isVibrationEnabled {
            return PlaybackConfiguration(
                sound: sound,
                isSoundEnabled: isSoundEnabled,
                isVibrationEnabled: isVibrationEnabled
            )
        }

        guard case .success(let alarms) = AlarmStore.loadResult(from: defaults),
              let alarm = alarms.first(where: { $0.id == alarmID }) else {
            return nil
        }
        return PlaybackConfiguration(
            sound: alarm.sound,
            isSoundEnabled: alarm.isSoundEnabled,
            isVibrationEnabled: alarm.isVibrationEnabled
        )
    }

    private static func persistedRecord(
        in defaults: UserDefaults
    ) -> PersistedActiveAlarm? {
        guard let data = defaults.data(forKey: DefaultsKey.activeAlarmRecord)
        else {
            return nil
        }
        return try? JSONDecoder().decode(PersistedActiveAlarm.self, from: data)
    }

    private static func legacyPersistedRecord(
        in defaults: UserDefaults
    ) -> PersistedActiveAlarm? {
        guard let alarmID = defaults.string(
            forKey: DefaultsKey.activeAlarmID
        ) else {
            return nil
        }
        let occurrenceID = defaults.string(
            forKey: DefaultsKey.activeOccurrenceID
        ) ?? "legacy-active:\(alarmID)"
        return PersistedActiveAlarm(
            alarmID: alarmID,
            occurrenceID: occurrenceID,
            name: defaults.string(forKey: DefaultsKey.activeAlarmName)
                ?? "到着アラーム",
            sound: defaults.string(forKey: DefaultsKey.activeAlarmSound),
            isSoundEnabled: defaults.object(
                forKey: DefaultsKey.activeAlarmSoundEnabled
            ).map { _ in
                defaults.bool(forKey: DefaultsKey.activeAlarmSoundEnabled)
            },
            isVibrationEnabled: defaults.object(
                forKey: DefaultsKey.activeAlarmVibrationEnabled
            ).map { _ in
                defaults.bool(
                    forKey: DefaultsKey.activeAlarmVibrationEnabled
                )
            }
        )
    }

    @discardableResult
    private static func persist(
        _ record: PersistedActiveAlarm,
        in defaults: UserDefaults
    ) -> Bool {
        guard let data = try? JSONEncoder().encode(record) else {
            return false
        }
        defaults.set(data, forKey: DefaultsKey.activeAlarmRecord)
        return true
    }

    private static func clearLegacyPersistedState(in defaults: UserDefaults) {
        defaults.removeObject(forKey: DefaultsKey.activeAlarmID)
        defaults.removeObject(forKey: DefaultsKey.activeOccurrenceID)
        defaults.removeObject(forKey: DefaultsKey.activeAlarmName)
        defaults.removeObject(forKey: DefaultsKey.activeAlarmSound)
        defaults.removeObject(forKey: DefaultsKey.activeAlarmSoundEnabled)
        defaults.removeObject(forKey: DefaultsKey.activeAlarmVibrationEnabled)
    }

    private func startPlayback(
        alarmID: String,
        configuration: PlaybackConfiguration
    ) {
        if configuration.isSoundEnabled {
            SoundPlayer.shared.startAlarm(
                id: alarmID,
                sound: configuration.sound
            )
        }
        if configuration.isVibrationEnabled {
            HapticManager.startAlarm(
                id: alarmID,
                type: .systemVibrate,
                count: .max,
                interval: 1
            )
        }
    }

    private func performOnMainSynchronously<T>(
        _ operation: () -> T
    ) -> T {
        if Thread.isMainThread {
            return operation()
        }
        return DispatchQueue.main.sync(execute: operation)
    }
}

extension Notification.Name {
    static let activeAlarmDidChange = Notification.Name("ActiveAlarmDidChange")
    static let alarmSaved = Notification.Name("AlarmSaved")
    static let alarmMonitoringStatusDidChange = Notification.Name("AlarmMonitoringStatusDidChange")
}
