import UIKit
import AudioToolbox

enum HapticType {
    case impactLight
    case impactMedium
    case impactHeavy
    case notificationSuccess
    case notificationWarning
    case notificationError
    case systemVibrate
}

struct HapticManager {
    private(set) static var activeAlarmID: String?
    private static var alarmTimer: Timer?
    private static var alarmType: HapticType?
    private static var alarmRemainingCount: Int?
    private static var alarmInterval: TimeInterval = 1

    private static var previewTimer: Timer?
    private static var previewType: HapticType?
    private static var previewRemainingCount: Int?
    private static var previewInterval: TimeInterval = 1

    static func trigger(_ type: HapticType) {
        switch type {
        case .impactLight:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()
        case .impactMedium:
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
        case .impactHeavy:
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.prepare()
            generator.impactOccurred()
        case .notificationSuccess:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        case .notificationWarning:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.warning)
        case .notificationError:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.error)
        case .systemVibrate:
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    /// Claims repeated haptics for an alarm. A different alarm cannot replace
    /// the current owner. Timer delivery is best-effort and is not guaranteed
    /// while the app is suspended in the background.
    @discardableResult
    static func startAlarm(
        id alarmID: String,
        type: HapticType = .systemVibrate,
        count: Int = .max,
        interval: TimeInterval = 1
    ) -> Bool {
        guard !alarmID.isEmpty else { return false }
        if let activeAlarmID, activeAlarmID != alarmID {
            return false
        }
        if activeAlarmID == alarmID {
            return true
        }

        let remaining = normalizedRepeatCount(count)
        if let remaining, remaining <= 0 {
            return false
        }

        activeAlarmID = alarmID
        alarmType = type
        alarmRemainingCount = remaining
        alarmInterval = max(interval, 0.2)

        trigger(type)
        decrementAlarmRemainingCount()
        scheduleNextAlarmPulse(for: alarmID)
        return true
    }

    /// Stops repeated haptics only when the exact alarm owns them.
    @discardableResult
    static func stopAlarm(id alarmID: String) -> Bool {
        guard activeAlarmID == alarmID else { return false }

        alarmTimer?.invalidate()
        alarmTimer = nil
        alarmType = nil
        alarmRemainingCount = nil
        activeAlarmID = nil
        return true
    }

    /// Starts an isolated preview. It may replace another preview, but never
    /// changes or stops alarm-owned haptics.
    static func startPreview(_ type: HapticType, count: Int, interval: TimeInterval) {
        stopPreview()

        let remaining = normalizedRepeatCount(count)
        if let remaining, remaining <= 0 { return }

        previewType = type
        previewRemainingCount = remaining
        previewInterval = max(interval, 0.2)

        trigger(type)
        decrementPreviewRemainingCount()
        scheduleNextPreviewPulse()
    }

    /// Compatibility API used by the settings screen.
    static func triggerRepeated(_ type: HapticType, count: Int, interval: TimeInterval) {
        startPreview(type, count: count, interval: interval)
    }

    static func stopPreview() {
        previewTimer?.invalidate()
        previewTimer = nil
        previewType = nil
        previewRemainingCount = nil
    }

    static func normalizedRepeatCount(_ count: Int) -> Int? {
        count == .max ? nil : min(max(count, 0), 300)
    }

    /// Legacy unowned stopping is preview-only. Alarm call sites must provide
    /// the exact ID to `stopAlarm(id:)`.
    @available(*, deprecated, message: "Use stopAlarm(id:) for alarms or stopPreview() for previews")
    static func stop() {
        stopPreview()
    }

    private static func decrementAlarmRemainingCount() {
        if let remaining = alarmRemainingCount {
            alarmRemainingCount = remaining - 1
        }
    }

    private static func scheduleNextAlarmPulse(for alarmID: String) {
        guard activeAlarmID == alarmID,
              alarmType != nil else {
            return
        }
        if let remaining = alarmRemainingCount, remaining <= 0 {
            alarmTimer = nil
            return
        }

        alarmTimer = Timer.scheduledTimer(withTimeInterval: alarmInterval, repeats: false) { _ in
            alarmTimer = nil
            guard activeAlarmID == alarmID,
                  let currentType = alarmType else {
                return
            }
            trigger(currentType)
            decrementAlarmRemainingCount()
            scheduleNextAlarmPulse(for: alarmID)
        }
    }

    private static func decrementPreviewRemainingCount() {
        if let remaining = previewRemainingCount {
            previewRemainingCount = remaining - 1
        }
    }

    private static func scheduleNextPreviewPulse() {
        guard previewType != nil else { return }
        if let remaining = previewRemainingCount, remaining <= 0 {
            previewTimer = nil
            return
        }

        previewTimer = Timer.scheduledTimer(withTimeInterval: previewInterval, repeats: false) { _ in
            previewTimer = nil
            guard let currentType = previewType else { return }
            trigger(currentType)
            decrementPreviewRemainingCount()
            scheduleNextPreviewPulse()
        }
    }
}
