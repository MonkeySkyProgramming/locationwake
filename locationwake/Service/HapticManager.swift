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
    private static var activeTimer: Timer?

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

    static func triggerRepeated(_ type: HapticType, count: Int, interval: TimeInterval) {
        stop()
        let safeCount = min(max(count, 0), 300)
        guard safeCount > 0 else { return }
        var remaining = safeCount
        var currentInterval = max(interval, 0.2)

        func scheduleNext() {
            guard remaining > 0 else {
                activeTimer = nil
                return
            }
            activeTimer = Timer.scheduledTimer(withTimeInterval: currentInterval, repeats: false) { _ in
                activeTimer = nil
                trigger(type)
                remaining -= 1
                currentInterval = max(0.2, currentInterval * 0.8)
                scheduleNext()
            }
        }
        scheduleNext()
    }

    static func stop() {
        activeTimer?.invalidate()
        activeTimer = nil
    }
}
