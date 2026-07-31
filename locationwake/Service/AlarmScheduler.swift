import Foundation
import UserNotifications

struct AlarmNotificationOperationToken: Equatable {
    let identifier: String
    let generation: UInt
}

enum AlarmNotificationScheduleResult: Equatable {
    case enqueued
    case cancelled
    case superseded
    case failed
}

enum AlarmNotificationOperationDisposition: Equatable {
    case current
    case explicitlyCancelled
    case superseded
}

struct AlarmNotificationOperationTracker {
    private struct State {
        var generation: UInt
        var shouldExist: Bool
        var inFlightGenerations: Set<UInt>
    }

    private var states: [String: State] = [:]

    var trackedIdentifierCount: Int {
        states.count
    }

    mutating func schedule(identifier: String) -> AlarmNotificationOperationToken {
        let token = update(identifier: identifier, shouldExist: true)
        states[identifier]?.inFlightGenerations.insert(token.generation)
        return token
    }

    mutating func cancel(identifier: String) -> AlarmNotificationOperationToken {
        let token = update(identifier: identifier, shouldExist: false)
        if states[identifier]?.inFlightGenerations.isEmpty == true {
            states.removeValue(forKey: identifier)
        }
        return token
    }

    func shouldRemoveAfterAdd(
        token: AlarmNotificationOperationToken
    ) -> Bool {
        disposition(for: token) == .explicitlyCancelled
    }

    func shouldProceedWithAdd(
        token: AlarmNotificationOperationToken
    ) -> Bool {
        disposition(for: token) == .current
    }

    func disposition(
        for token: AlarmNotificationOperationToken
    ) -> AlarmNotificationOperationDisposition {
        guard let state = states[token.identifier] else {
            return .explicitlyCancelled
        }
        guard state.generation == token.generation else {
            return state.shouldExist ? .superseded : .explicitlyCancelled
        }
        return state.shouldExist ? .current : .explicitlyCancelled
    }

    mutating func complete(
        token: AlarmNotificationOperationToken
    ) -> AlarmNotificationOperationDisposition {
        let result = disposition(for: token)
        guard var state = states[token.identifier] else {
            return result
        }
        state.inFlightGenerations.remove(token.generation)
        if state.inFlightGenerations.isEmpty {
            states.removeValue(forKey: token.identifier)
        } else {
            states[token.identifier] = state
        }
        return result
    }

    private mutating func update(
        identifier: String,
        shouldExist: Bool
    ) -> AlarmNotificationOperationToken {
        let generation = states[identifier, default: State(
            generation: 0,
            shouldExist: false,
            inFlightGenerations: []
        )].generation &+ 1
        var state = states[identifier] ?? State(
            generation: 0,
            shouldExist: false,
            inFlightGenerations: []
        )
        state.generation = generation
        state.shouldExist = shouldExist
        states[identifier] = state
        return AlarmNotificationOperationToken(
            identifier: identifier,
            generation: generation
        )
    }
}

class AlarmScheduler {
    private static let operationLock = NSLock()
    private static var operationTracker = AlarmNotificationOperationTracker()

    static func notificationIdentifier(for alarm: Alarm) -> String {
        guard let occurrenceID = alarm.pendingArrivalOccurrenceID else {
            return alarm.id
        }
        return notificationIdentifier(
            alarmID: alarm.id,
            occurrenceID: occurrenceID
        )
    }

    static func notificationIdentifier(
        alarmID: String,
        occurrenceID: String
    ) -> String {
        "\(alarmID).arrival.\(occurrenceID)"
    }

    static func makeNotificationRequest(
        for alarm: Alarm,
        isRinging: Bool = true,
        occurrenceID: String? = nil
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = isRinging
            ? AppStrings.text("到着アラーム")
            : AppStrings.text("目的地に到着しました")
        content.body = isRinging
            ? AppStrings.format(
                "%@に到着しました。アプリを開き、停止ボタンで止めてください。",
                alarm.name
            )
            : AppStrings.format("%@への到着を記録しました。", alarm.name)
        content.userInfo = [
            "alarmID": alarm.id,
            "occurrenceID": occurrenceID
                ?? alarm.pendingArrivalOccurrenceID
                ?? ""
        ]
        // 選択音源は SoundPlayer が音楽再生する。通知側は30秒制限のある
        // カスタム音源を指定せず、再生失敗時にも気づける補助音だけを使う。
        content.sound = isRinging && alarm.isSoundEnabled ? .default : nil

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        return UNNotificationRequest(
            identifier: occurrenceID.map {
                notificationIdentifier(
                    alarmID: alarm.id,
                    occurrenceID: $0
                )
            } ?? notificationIdentifier(for: alarm),
            content: content,
            trigger: trigger
        )
    }

    func scheduleAlarm(
        alarm: Alarm,
        isRinging: Bool,
        occurrenceID: String? = nil,
        completion: @escaping (AlarmNotificationScheduleResult) -> Void = { _ in }
    ) {
        let center = UNUserNotificationCenter.current()
        let request = Self.makeNotificationRequest(
            for: alarm,
            isRinging: isRinging,
            occurrenceID: occurrenceID
        )
        let token = Self.recordScheduled(identifier: request.identifier)
        center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
        switch Self.disposition(token: token) {
        case .current:
            break
        case .explicitlyCancelled:
            completion(Self.scheduleResult(
                disposition: Self.complete(token: token),
                hasError: false
            ))
            return
        case .superseded:
            completion(Self.scheduleResult(
                disposition: Self.complete(token: token),
                hasError: false
            ))
            return
        }
        center.add(request) { error in
            let disposition = Self.complete(token: token)
            let result = Self.scheduleResult(
                disposition: disposition,
                hasError: error != nil
            )
            if let error, disposition == .current {
#if DEBUG
                print("アラーム通知の登録に失敗しました: \(error.localizedDescription)")
#endif
            }
            switch disposition {
            case .explicitlyCancelled:
                center.removePendingNotificationRequests(
                    withIdentifiers: [request.identifier]
                )
                center.removeDeliveredNotifications(
                    withIdentifiers: [request.identifier]
                )
            case .superseded:
                // 同じidentifierの新しいaddを消さない。新しいoperationの完了が
                // outboxをackする。
                break
            case .current:
                break
            }
            completion(result)
        }
    }

    static func scheduleResult(
        disposition: AlarmNotificationOperationDisposition,
        hasError: Bool
    ) -> AlarmNotificationScheduleResult {
        switch disposition {
        case .explicitlyCancelled:
            return .cancelled
        case .superseded:
            return .superseded
        case .current:
            return hasError ? .failed : .enqueued
        }
    }

    func cancelAlarm(alarm: Alarm) {
        Self.cancelNotification(identifier: alarm.id)
        for delivery in alarm.pendingArrivalDeliveries {
            Self.cancelNotification(
                identifier: Self.notificationIdentifier(
                    alarmID: alarm.id,
                    occurrenceID: delivery.occurrenceID
                )
            )
        }
    }

    static func cancelNotification(identifier: String) {
        _ = recordCancelled(identifier: identifier)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private static func recordScheduled(
        identifier: String
    ) -> AlarmNotificationOperationToken {
        operationLock.lock()
        defer { operationLock.unlock() }
        return operationTracker.schedule(identifier: identifier)
    }

    private static func recordCancelled(
        identifier: String
    ) -> AlarmNotificationOperationToken {
        operationLock.lock()
        defer { operationLock.unlock() }
        return operationTracker.cancel(identifier: identifier)
    }

    private static func disposition(
        token: AlarmNotificationOperationToken
    ) -> AlarmNotificationOperationDisposition {
        operationLock.lock()
        defer { operationLock.unlock() }
        return operationTracker.disposition(for: token)
    }

    private static func complete(
        token: AlarmNotificationOperationToken
    ) -> AlarmNotificationOperationDisposition {
        operationLock.lock()
        defer { operationLock.unlock() }
        return operationTracker.complete(token: token)
    }
}
