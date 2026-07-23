import Combine
import Foundation

enum AlarmPlaybackDecision: Equatable {
    case ring
    case notifyOnly
}

struct AlarmPlaybackStateMachine: Equatable {
    private(set) var activeAlarmID: String?

    init(activeAlarmID: String? = nil) {
        self.activeAlarmID = activeAlarmID
    }

    mutating func registerArrival(alarmID: String) -> AlarmPlaybackDecision {
        guard activeAlarmID == nil else {
            return .notifyOnly
        }
        activeAlarmID = alarmID
        return .ring
    }

    mutating func stop(alarmID: String) -> Bool {
        guard activeAlarmID == alarmID else { return false }
        activeAlarmID = nil
        return true
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

    private enum DefaultsKey {
        static let activeAlarmID = "ActiveAlarmID"
        static let activeAlarmName = "ActiveAlarmName"
    }

    private let lock = NSLock()
    private let defaults: UserDefaults
    private var stateMachine: AlarmPlaybackStateMachine

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedID = defaults.string(forKey: DefaultsKey.activeAlarmID)
        stateMachine = AlarmPlaybackStateMachine(activeAlarmID: storedID)

        if let storedID {
            activeAlarm = ActiveAlarmPresentation(
                alarmID: storedID,
                name: defaults.string(forKey: DefaultsKey.activeAlarmName) ?? "到着アラーム"
            )
        }
    }

    @discardableResult
    func registerArrival(for alarm: Alarm) -> AlarmPlaybackDecision {
        lock.lock()
        let decision = stateMachine.registerArrival(alarmID: alarm.id)
        if decision == .ring {
            defaults.set(alarm.id, forKey: DefaultsKey.activeAlarmID)
            defaults.set(alarm.name, forKey: DefaultsKey.activeAlarmName)
        }
        lock.unlock()

        if decision == .ring {
            publish(
                ActiveAlarmPresentation(alarmID: alarm.id, name: alarm.name)
            )
        }
        return decision
    }

    /// 通知から開いた時は消音せず、現在鳴っているアラームの停止画面だけを前面に出す。
    func presentCurrentAlarmIfNeeded() {
        lock.lock()
        let alarmID = stateMachine.activeAlarmID
        let alarmName = defaults.string(forKey: DefaultsKey.activeAlarmName) ?? "到着アラーム"
        lock.unlock()

        guard let alarmID else { return }
        publish(ActiveAlarmPresentation(alarmID: alarmID, name: alarmName))
    }

    @discardableResult
    func stop(alarmID: String) -> Bool {
        lock.lock()
        let didStop = stateMachine.stop(alarmID: alarmID)
        if didStop {
            defaults.removeObject(forKey: DefaultsKey.activeAlarmID)
            defaults.removeObject(forKey: DefaultsKey.activeAlarmName)
        }
        lock.unlock()

        guard didStop else { return false }
        DispatchQueue.main.async {
            SoundPlayer.shared.stopAlarm(id: alarmID)
            HapticManager.stopAlarm(id: alarmID)
            AlarmScheduler.cancelNotification(identifier: alarmID)
            self.activeAlarm = nil
            NotificationCenter.default.post(name: .activeAlarmDidChange, object: nil)
        }
        return true
    }

    private func publish(_ presentation: ActiveAlarmPresentation) {
        DispatchQueue.main.async {
            self.activeAlarm = presentation
            NotificationCenter.default.post(name: .activeAlarmDidChange, object: nil)
        }
    }
}

extension Notification.Name {
    static let activeAlarmDidChange = Notification.Name("ActiveAlarmDidChange")
    static let alarmSaved = Notification.Name("AlarmSaved")
    static let alarmMonitoringStatusDidChange = Notification.Name("AlarmMonitoringStatusDidChange")
}
