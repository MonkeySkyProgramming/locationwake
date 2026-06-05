import XCTest
import UserNotifications
@testable import locationwake

final class locationwakeTests: XCTestCase {

    func testAlarmDecodesLegacyPayloadWithGeneratedAndDefaultFields() throws {
        let json = """
        {
          "name": "Osaka Station",
          "repeatWeekdays": [1, 3, 5],
          "sound": "modan",
          "isAlarmEnabled": true,
          "isSoundEnabled": false,
          "location": {
            "latitude": 34.702485,
            "longitude": 135.495951
          },
          "radius": 300.0
        }
        """.data(using: .utf8)!

        let alarm = try JSONDecoder().decode(Alarm.self, from: json)

        XCTAssertFalse(alarm.id.isEmpty)
        XCTAssertEqual(alarm.name, "Osaka Station")
        XCTAssertEqual(alarm.repeatWeekdays, [1, 3, 5])
        XCTAssertEqual(alarm.sound, "modan")
        XCTAssertTrue(alarm.isAlarmEnabled)
        XCTAssertFalse(alarm.isSoundEnabled)
        XCTAssertFalse(alarm.isVibrationEnabled)
        XCTAssertEqual(alarm.location?.latitude, 34.702485)
        XCTAssertEqual(alarm.location?.longitude, 135.495951)
        XCTAssertEqual(alarm.radius, 300.0)
        XCTAssertFalse(alarm.hasTriggered)
        XCTAssertFalse(alarm.hasTriggeredUntilExit)
    }

    func testAlarmDecodingPreservesExplicitTriggerAndVibrationState() throws {
        let json = """
        {
          "id": "alarm-1",
          "name": "Home",
          "repeatWeekdays": [],
          "sound": "siren",
          "isAlarmEnabled": false,
          "isSoundEnabled": true,
          "isVibrationEnabled": true,
          "location": {
            "latitude": 35.0,
            "longitude": 139.0
          },
          "radius": 1000.0,
          "hasTriggered": true,
          "hasTriggeredUntilExit": true
        }
        """.data(using: .utf8)!

        let alarm = try JSONDecoder().decode(Alarm.self, from: json)

        XCTAssertEqual(alarm.id, "alarm-1")
        XCTAssertEqual(alarm.repeatWeekdays, [])
        XCTAssertTrue(alarm.isVibrationEnabled)
        XCTAssertTrue(alarm.hasTriggered)
        XCTAssertTrue(alarm.hasTriggeredUntilExit)
    }

    func testAlarmRoundTripsThroughJSON() throws {
        let original = Alarm(
            id: "round-trip",
            name: "Destination",
            repeatWeekdays: [0, 6],
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false,
            location: Location(latitude: 34.0, longitude: 135.0),
            radius: 750.0,
            hasTriggered: true,
            hasTriggeredUntilExit: false
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Alarm.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.repeatWeekdays, original.repeatWeekdays)
        XCTAssertEqual(decoded.sound, original.sound)
        XCTAssertEqual(decoded.isAlarmEnabled, original.isAlarmEnabled)
        XCTAssertEqual(decoded.isSoundEnabled, original.isSoundEnabled)
        XCTAssertEqual(decoded.isVibrationEnabled, original.isVibrationEnabled)
        XCTAssertEqual(decoded.location?.latitude, original.location?.latitude)
        XCTAssertEqual(decoded.location?.longitude, original.location?.longitude)
        XCTAssertEqual(decoded.radius, original.radius)
        XCTAssertEqual(decoded.hasTriggered, original.hasTriggered)
        XCTAssertEqual(decoded.hasTriggeredUntilExit, original.hasTriggeredUntilExit)
    }

    func testNavigationRouteUsesAlarmIdForEquality() {
        let first = Alarm(
            id: "same-id",
            name: "First",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false
        )
        let second = Alarm(
            id: "same-id",
            name: "Second",
            sound: "siren",
            isAlarmEnabled: false,
            isSoundEnabled: false,
            isVibrationEnabled: true
        )
        let different = Alarm(
            id: "different-id",
            name: "First",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false
        )

        XCTAssertEqual(NavigationRoute.alarmDetail(alarm: first), NavigationRoute.alarmDetail(alarm: second))
        XCTAssertNotEqual(NavigationRoute.alarmDetail(alarm: first), NavigationRoute.alarmDetail(alarm: different))
    }

    func testAlarmSchedulerUsesStableAlarmIdentifier() {
        let alarm = Alarm(
            id: "alarm-id",
            name: "Station",
            sound: "modan",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false
        )

        XCTAssertEqual(AlarmScheduler.notificationIdentifier(for: alarm), "alarm-id")
    }

    func testAlarmSchedulerFallsBackToNameWhenIdIsEmpty() {
        let alarm = Alarm(
            id: "",
            name: "Station",
            sound: "modan",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false
        )

        XCTAssertEqual(AlarmScheduler.notificationIdentifier(for: alarm), "Station")
    }

    func testAlarmSchedulerBuildsArrivalNotificationRequest() throws {
        let alarm = Alarm(
            id: "arrival",
            name: "Destination",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false
        )

        let request = AlarmScheduler.makeNotificationRequest(for: alarm)
        let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)

        XCTAssertEqual(request.identifier, "arrival")
        XCTAssertEqual(request.content.title, "アラーム")
        XCTAssertEqual(request.content.body, "Destinationに到達しました！")
        XCTAssertEqual(trigger.timeInterval, 1)
        XCTAssertFalse(trigger.repeats)
    }

    func testGeofenceEligibleAlarmsOnlyIncludesEnabledAlarmsWithLocationAndRadius() {
        let eligible = Alarm(
            id: "eligible",
            name: "Eligible",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false,
            location: Location(latitude: 34.0, longitude: 135.0),
            radius: 300
        )
        let disabled = Alarm(
            id: "disabled",
            name: "Disabled",
            sound: "kind",
            isAlarmEnabled: false,
            isSoundEnabled: true,
            isVibrationEnabled: false,
            location: Location(latitude: 34.0, longitude: 135.0),
            radius: 300
        )
        let missingLocation = Alarm(
            id: "missing-location",
            name: "Missing Location",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false,
            radius: 300
        )
        let missingRadius = Alarm(
            id: "missing-radius",
            name: "Missing Radius",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false,
            location: Location(latitude: 34.0, longitude: 135.0)
        )

        let result = LocationManager.geofenceEligibleAlarms(
            from: [eligible, disabled, missingLocation, missingRadius]
        )

        XCTAssertEqual(result.map(\.id), ["eligible"])
    }

    func testAlarmTriggerPolicyAllowsEnabledSingleAlarm() {
        let alarm = Alarm(
            id: "enabled",
            name: "Enabled",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false
        )

        XCTAssertNil(AlarmTriggerPolicy.blockReason(for: alarm, weekday: 1))
    }

    func testAlarmTriggerPolicyBlocksDisabledWeekdayMismatchAndUntilExit() {
        let disabled = Alarm(
            id: "disabled",
            name: "Disabled",
            sound: "kind",
            isAlarmEnabled: false,
            isSoundEnabled: true,
            isVibrationEnabled: false
        )
        let weekdayMismatch = Alarm(
            id: "weekday",
            name: "Weekday",
            repeatWeekdays: [2],
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false
        )
        let untilExit = Alarm(
            id: "until-exit",
            name: "Until Exit",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false,
            hasTriggeredUntilExit: true
        )

        XCTAssertEqual(AlarmTriggerPolicy.blockReason(for: disabled, weekday: 1), .disabled)
        XCTAssertEqual(AlarmTriggerPolicy.blockReason(for: weekdayMismatch, weekday: 1), .weekdayMismatch)
        XCTAssertEqual(AlarmTriggerPolicy.blockReason(for: untilExit, weekday: 1), .triggeredUntilExit)
    }

    func testAlarmTriggerPolicyBlocksSaveSkipStates() {
        let alarm = Alarm(
            id: "skip",
            name: "Skip",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false
        )
        let now = Date(timeIntervalSince1970: 100)

        XCTAssertEqual(
            AlarmTriggerPolicy.blockReason(for: alarm, weekday: 1, hasMemorySkip: true),
            .memorySkip
        )
        XCTAssertEqual(
            AlarmTriggerPolicy.blockReason(for: alarm, weekday: 1, hasStoredSkipFlag: true),
            .storedSkipFlag
        )
        XCTAssertEqual(
            AlarmTriggerPolicy.blockReason(
                for: alarm,
                weekday: 1,
                savedAt: Date(timeIntervalSince1970: 95),
                now: now
            ),
            .savedTooRecently
        )
        XCTAssertNil(
            AlarmTriggerPolicy.blockReason(
                for: alarm,
                weekday: 1,
                savedAt: Date(timeIntervalSince1970: 80),
                now: now
            )
        )
    }

    func testAppRuntimeSuppressesExternalSideEffectsInUnitTests() {
        XCTAssertTrue(AppRuntime.shouldSuppressExternalSideEffects)
    }
}
