import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()
    
    // 通知の許可をリクエストするメソッド
    func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("通知の許可が得られました")
            } else {
                print("通知の許可が拒否されました: \(String(describing: error?.localizedDescription))")
            }
        }
    }

    // 通知をスケジュールするメソッド
    func scheduleNotification(withTitle title: String, message: String, identifier: String) {
        // 既存の通知を削除
        removeNotification(identifier: identifier)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("通知のスケジュールに失敗しました: \(error.localizedDescription)")
            } else {
                print("通知が正常にスケジュールされました: \(identifier)")
            }
        }
    }

    // 通知を削除するメソッド
    func removeNotification(identifier: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        print("通知が削除されました: \(identifier)")
    }

    // すべての通知を削除するメソッド
    func removeAllNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        print("すべての通知が削除されました")
    }
    
    // 通知の状態を確認するデバッグ用メソッド（新規追加）
    func printPendingNotifications() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            print("保留中の通知リクエスト:")
            for request in requests {
                print("Identifier: \(request.identifier), Title: \(request.content.title), Body: \(request.content.body)")
            }
        }
    }
}
