import Foundation
import UserNotifications

class AlarmScheduler {
    static func notificationIdentifier(for alarm: Alarm) -> String {
        alarm.id.isEmpty ? alarm.name : alarm.id
    }

    static func makeNotificationRequest(for alarm: Alarm) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "アラーム"
        content.body = "\(alarm.name)に到達しました！"
        content.sound = alarm.isSoundEnabled
            ? UNNotificationSound(named: UNNotificationSoundName(rawValue: "\(alarm.sound).mp3"))
            : nil

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        return UNNotificationRequest(
            identifier: notificationIdentifier(for: alarm),
            content: content,
            trigger: trigger
        )
    }

    func scheduleAlarm(alarm: Alarm) {
        let center = UNUserNotificationCenter.current()
        let request = Self.makeNotificationRequest(for: alarm)
        center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
        center.add(request) { error in
            if let error {
                print("アラーム通知の登録に失敗しました: \(error.localizedDescription)")
            }
        }
    }

    func cancelAlarm(alarm: Alarm) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.notificationIdentifier(for: alarm)]
        )
    }
}
