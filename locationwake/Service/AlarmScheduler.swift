import Foundation
import UserNotifications

class AlarmScheduler {
    static func notificationIdentifier(for alarm: Alarm) -> String {
        alarm.id
    }

    static func makeNotificationRequest(
        for alarm: Alarm,
        isRinging: Bool = true
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = isRinging ? "到着アラーム" : "目的地に到着しました"
        content.body = isRinging
            ? "\(alarm.name)に到着しました。アプリを開き、停止ボタンで止めてください。"
            : "\(alarm.name)への到着を記録しました。"
        content.userInfo = ["alarmID": alarm.id]
        // 選択音源は SoundPlayer が音楽再生する。通知側は30秒制限のある
        // カスタム音源を指定せず、再生失敗時にも気づける補助音だけを使う。
        content.sound = isRinging && alarm.isSoundEnabled ? .default : nil

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        return UNNotificationRequest(
            identifier: notificationIdentifier(for: alarm),
            content: content,
            trigger: trigger
        )
    }

    func scheduleAlarm(alarm: Alarm, isRinging: Bool) {
        let center = UNUserNotificationCenter.current()
        let request = Self.makeNotificationRequest(for: alarm, isRinging: isRinging)
        center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
        center.add(request) { error in
            if let error {
#if DEBUG
                print("アラーム通知の登録に失敗しました: \(error.localizedDescription)")
#endif
            }
        }
    }

    func cancelAlarm(alarm: Alarm) {
        Self.cancelNotification(identifier: Self.notificationIdentifier(for: alarm))
    }

    static func cancelNotification(identifier: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
