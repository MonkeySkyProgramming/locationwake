import Foundation
import UserNotifications

class AlarmScheduler {

    func scheduleAlarm(alarm: Alarm) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Alarm"
        content.body = "Time to wake up!"
        content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: alarm.sound))

    }

    func cancelAlarm(alarm: Alarm) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [UUID().uuidString])
    }
}
