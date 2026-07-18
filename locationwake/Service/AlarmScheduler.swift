import Foundation
import UserNotifications

class AlarmScheduler {
    static func notificationIdentifier(for alarm: Alarm) -> String {
        alarm.id
    }

    static func makeNotificationRequest(for alarm: Alarm) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "アラーム"
        content.body = "\(alarm.name)に到達しました！アプリを起動してアラームを止めてください。"
        // 選択音源は SoundPlayer が音楽再生する。通知側は30秒制限のある
        // カスタム音源を指定せず、再生失敗時にも気づける補助音だけを使う。
        content.sound = alarm.isSoundEnabled ? .default : nil

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
