import XCTest
import AppTrackingTransparency
import CoreLocation
import UIKit
import UserNotifications
@testable import locationwake

final class locationwakeTests: XCTestCase {

    func testNewAlarmDefaultsToNoRepeat() {
        let alarm = Alarm(
            name: "One time destination",
            sound: "modan",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: true
        )

        XCTAssertEqual(alarm.repeatWeekdays, [])
    }

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
        XCTAssertFalse(alarm.needsInitialStateCheck)
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
          "hasTriggeredUntilExit": true,
          "needsInitialStateCheck": true
        }
        """.data(using: .utf8)!

        let alarm = try JSONDecoder().decode(Alarm.self, from: json)

        XCTAssertEqual(alarm.id, "alarm-1")
        XCTAssertEqual(alarm.repeatWeekdays, [])
        XCTAssertTrue(alarm.isVibrationEnabled)
        XCTAssertTrue(alarm.hasTriggered)
        XCTAssertTrue(alarm.hasTriggeredUntilExit)
        XCTAssertTrue(alarm.needsInitialStateCheck)
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
            hasTriggeredUntilExit: false,
            needsInitialStateCheck: true
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
        XCTAssertEqual(decoded.needsInitialStateCheck, original.needsInitialStateCheck)
    }

    func testAlarmEditorSheetUsesAlarmIdAndModeForStableIdentity() {
        let first = Alarm(
            id: "same-id",
            name: "First",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false
        )
        let different = Alarm(
            id: "different-id",
            name: "First",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false
        )

        XCTAssertEqual(
            AppSheetDestination.alarmEditor(alarm: first, isNew: false).id,
            "alarm-editor-same-id-false"
        )
        XCTAssertEqual(
            AppSheetDestination.alarmEditor(alarm: first, isNew: true).id,
            "alarm-editor-same-id-true"
        )
        XCTAssertNotEqual(
            AppSheetDestination.alarmEditor(alarm: first, isNew: false).id,
            AppSheetDestination.alarmEditor(alarm: different, isNew: false).id
        )
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

    func testAlarmInitialiserGeneratesIdentifierWhenGivenAnEmptyId() {
        let alarm = Alarm(
            id: "",
            name: "Station",
            sound: "modan",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false
        )

        XCTAssertFalse(alarm.id.isEmpty)
        XCTAssertNotEqual(alarm.id, alarm.name)
        XCTAssertEqual(AlarmScheduler.notificationIdentifier(for: alarm), alarm.id)
    }

    func testAlarmNormalizesGeofenceRadiusForPersistence() {
        let tooSmall = Alarm(
            id: "small",
            name: "Small",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false,
            radius: 20
        )
        let tooLarge = Alarm(
            id: "large",
            name: "Large",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false,
            radius: 30_000
        )

        XCTAssertEqual(tooSmall.radius, Alarm.minimumGeofenceRadius)
        XCTAssertEqual(tooLarge.radius, Alarm.maximumGeofenceRadius)
    }

    func testAlarmNormalizesWeekdaysToUniqueValuesFromZeroThroughSix() {
        XCTAssertNil(Alarm.normalizedWeekdays(nil))
        XCTAssertEqual(Alarm.normalizedWeekdays([]), [])
        XCTAssertEqual(
            Alarm.normalizedWeekdays([6, 0, 2, 2, -1, 7, 99]),
            [0, 2, 6]
        )

        let alarm = Alarm(
            id: "weekdays",
            name: "Weekdays",
            repeatWeekdays: [7, 6, 0, 6, -1],
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false
        )

        XCTAssertEqual(alarm.repeatWeekdays, [0, 6])

        var mutated = alarm
        mutated.repeatWeekdays = [8, 4, 4, 0, -2]
        XCTAssertEqual(
            Alarm.normalizedForPersistence([mutated]).first?.repeatWeekdays,
            [0, 4]
        )
    }

    func testAlarmStoreLoadsLegacyDataAndRemovesObsoleteSkipState() throws {
        let suiteName = "AlarmStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyJSON = """
        [{
          "id": "legacy-id",
          "name": "Osaka Station",
          "sound": "modan",
          "isAlarmEnabled": true,
          "isSoundEnabled": true,
          "location": { "latitude": 34.702485, "longitude": 135.495951 },
          "radius": 300
        }]
        """.data(using: .utf8)!
        defaults.set(legacyJSON, forKey: AlarmStore.savedAlarmsKey)
        defaults.set(true, forKey: "SkipTrigger_Osaka Station")
        defaults.set(Date(), forKey: "SkipTriggerAt_Osaka Station")
        defaults.set(true, forKey: "SkipTrigger_legacy-id")
        defaults.set(Date(), forKey: "SkipTriggerAt_legacy-id")

        let alarms = AlarmStore.load(from: defaults)
        let alarm = try XCTUnwrap(alarms.first)

        XCTAssertEqual(alarm.id, "legacy-id")
        XCTAssertNil(defaults.object(forKey: "SkipTrigger_Osaka Station"))
        XCTAssertNil(defaults.object(forKey: "SkipTriggerAt_Osaka Station"))
        XCTAssertNil(defaults.object(forKey: "SkipTrigger_legacy-id"))
        XCTAssertNil(defaults.object(forKey: "SkipTriggerAt_legacy-id"))

        let persisted = try XCTUnwrap(defaults.data(forKey: AlarmStore.savedAlarmsKey))
        XCTAssertTrue(String(decoding: persisted, as: UTF8.self).contains("\"id\""))
    }

    func testAlarmNormalizationRegeneratesDuplicateIdentifiers() {
        let alarms = [
            Alarm(id: "duplicate", name: "A", sound: "kind", isAlarmEnabled: true, isSoundEnabled: true, isVibrationEnabled: false),
            Alarm(id: "duplicate", name: "B", sound: "kind", isAlarmEnabled: true, isSoundEnabled: true, isVibrationEnabled: false)
        ]

        let normalized = Alarm.normalizedForPersistence(alarms)
        XCTAssertEqual(normalized[0].id, "duplicate")
        XCTAssertNotEqual(normalized[0].id, normalized[1].id)
    }

    func testAlarmSchedulerBuildsPrimaryArrivalNotificationRequest() throws {
        let alarm = Alarm(
            id: "arrival",
            name: "Destination",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false
        )

        let request = AlarmScheduler.makeNotificationRequest(
            for: alarm,
            isRinging: true
        )
        let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)

        XCTAssertEqual(request.identifier, "arrival")
        XCTAssertEqual(request.content.title, "到着アラーム")
        XCTAssertEqual(
            request.content.body,
            "Destinationに到着しました。アプリを開き、停止ボタンで止めてください。"
        )
        XCTAssertEqual(request.content.userInfo["alarmID"] as? String, "arrival")
        XCTAssertNotNil(request.content.sound)
        XCTAssertEqual(trigger.timeInterval, 1)
        XCTAssertFalse(trigger.repeats)
    }

    func testAlarmSchedulerBuildsSilentSecondaryArrivalNotificationRequest() {
        let alarm = Alarm(
            id: "secondary",
            name: "Second Destination",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: true
        )

        let request = AlarmScheduler.makeNotificationRequest(
            for: alarm,
            isRinging: false
        )

        XCTAssertEqual(request.identifier, "secondary")
        XCTAssertEqual(request.content.title, "目的地に到着しました")
        XCTAssertEqual(
            request.content.body,
            "Second Destinationへの到着を記録しました。"
        )
        XCTAssertEqual(request.content.userInfo["alarmID"] as? String, "secondary")
        XCTAssertNil(request.content.sound)
    }

    func testAlarmSchedulerUsesNoPrimaryNotificationSoundWhenAlarmSoundIsDisabled() {
        let alarm = Alarm(
            id: "silent",
            name: "Silent",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: false,
            isVibrationEnabled: true
        )

        XCTAssertNil(
            AlarmScheduler.makeNotificationRequest(
                for: alarm,
                isRinging: true
            ).content.sound
        )
    }

    func testAlarmPlaybackStateMachineArbitratesAndStopsByExactID() {
        var state = AlarmPlaybackStateMachine()

        XCTAssertEqual(state.registerArrival(alarmID: "first"), .ring)
        XCTAssertEqual(state.activeAlarmID, "first")
        XCTAssertEqual(state.registerArrival(alarmID: "second"), .notifyOnly)
        XCTAssertEqual(state.activeAlarmID, "first")

        XCTAssertFalse(state.stop(alarmID: "second"))
        XCTAssertEqual(state.activeAlarmID, "first")
        XCTAssertTrue(state.stop(alarmID: "first"))
        XCTAssertNil(state.activeAlarmID)

        XCTAssertEqual(state.registerArrival(alarmID: "second"), .ring)
        XCTAssertEqual(state.activeAlarmID, "second")
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

    func testAlarmTriggerPolicyBlocksWhileInitialStateIsPending() {
        let alarm = Alarm(
            id: "pending",
            name: "Pending",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false,
            needsInitialStateCheck: true
        )

        XCTAssertEqual(
            AlarmTriggerPolicy.blockReason(for: alarm, weekday: 1),
            .initialStatePending
        )
        XCTAssertEqual(
            AlarmTriggerPolicy.proximityAction(
                for: alarm,
                distance: 0,
                radius: 100,
                weekday: 1
            ),
            .none
        )
    }

    func testReenablingAlarmRequiresInitialStateCheckInsteadOfImmediatelyArming() {
        var alarm = Alarm(
            id: "reenable",
            name: "Reenable",
            sound: "kind",
            isAlarmEnabled: false,
            isSoundEnabled: true,
            isVibrationEnabled: false,
            hasTriggered: true,
            hasTriggeredUntilExit: true
        )

        alarm.setEnabled(true)

        XCTAssertTrue(alarm.isAlarmEnabled)
        XCTAssertFalse(alarm.hasTriggered)
        XCTAssertFalse(alarm.hasTriggeredUntilExit)
        XCTAssertTrue(alarm.needsInitialStateCheck)
    }

    func testInitialStatePreparationAndResolutionForInsideAndOutside() {
        var alarm = Alarm(
            id: "initial-state",
            name: "Initial State",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false,
            hasTriggered: true,
            hasTriggeredUntilExit: true
        )

        alarm.prepareForInitialStateCheck()
        XCTAssertTrue(alarm.needsInitialStateCheck)
        XCTAssertFalse(alarm.hasTriggered)
        XCTAssertFalse(alarm.hasTriggeredUntilExit)

        var inside = alarm
        inside.resolveInitialState(isInside: true)
        XCTAssertFalse(inside.needsInitialStateCheck)
        XCTAssertFalse(inside.hasTriggered)
        XCTAssertTrue(inside.hasTriggeredUntilExit)

        var outside = alarm
        outside.resolveInitialState(isInside: false)
        XCTAssertFalse(outside.needsInitialStateCheck)
        XCTAssertFalse(outside.hasTriggered)
        XCTAssertFalse(outside.hasTriggeredUntilExit)
    }

    func testPreparedInitialStateCheckResolvesFreshInsideOutsideAndUnknownLocations() {
        let target = Location(latitude: 34.0, longitude: 135.0)
        let alarm = Alarm(
            id: "prepared",
            name: "Prepared",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false,
            location: target,
            radius: 300,
            hasTriggered: true,
            hasTriggeredUntilExit: true
        )
        let now = Date()
        let insideLocation = makeCLLocation(
            latitude: target.latitude,
            longitude: target.longitude,
            timestamp: now
        )
        let outsideLocation = makeCLLocation(
            latitude: target.latitude + 0.01,
            longitude: target.longitude,
            timestamp: now
        )

        let inside = LocationManager.preparedForInitialStateCheck(
            alarm,
            currentLocation: insideLocation
        )
        XCTAssertFalse(inside.needsInitialStateCheck)
        XCTAssertFalse(inside.hasTriggered)
        XCTAssertTrue(inside.hasTriggeredUntilExit)

        let outside = LocationManager.preparedForInitialStateCheck(
            alarm,
            currentLocation: outsideLocation
        )
        XCTAssertFalse(outside.needsInitialStateCheck)
        XCTAssertFalse(outside.hasTriggered)
        XCTAssertFalse(outside.hasTriggeredUntilExit)

        let unknown = LocationManager.preparedForInitialStateCheck(
            alarm,
            currentLocation: nil
        )
        XCTAssertTrue(unknown.needsInitialStateCheck)
        XCTAssertFalse(unknown.hasTriggered)
        XCTAssertFalse(unknown.hasTriggeredUntilExit)

        let stale = LocationManager.preparedForInitialStateCheck(
            alarm,
            currentLocation: makeCLLocation(
                latitude: target.latitude,
                longitude: target.longitude,
                timestamp: now.addingTimeInterval(-31)
            )
        )
        XCTAssertTrue(stale.needsInitialStateCheck)
        XCTAssertFalse(stale.hasTriggeredUntilExit)
    }

    func testProximityPolicyWaitsForExitBeforeAllowingReentryTrigger() {
        var alarm = Alarm(
            id: "reentry",
            name: "Reentry",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false
        )
        alarm.prepareForInitialStateCheck()

        XCTAssertEqual(
            AlarmTriggerPolicy.proximityAction(
                for: alarm,
                distance: 10,
                radius: 100,
                weekday: 1
            ),
            .none
        )

        alarm.resolveInitialState(isInside: true)
        XCTAssertEqual(
            AlarmTriggerPolicy.proximityAction(
                for: alarm,
                distance: 10,
                radius: 100,
                weekday: 1
            ),
            .none
        )
        XCTAssertEqual(
            AlarmTriggerPolicy.proximityAction(
                for: alarm,
                distance: 101,
                radius: 100,
                weekday: 1
            ),
            .resetAfterExit
        )

        alarm.resolveInitialState(isInside: false)
        XCTAssertEqual(
            AlarmTriggerPolicy.proximityAction(
                for: alarm,
                distance: 10,
                radius: 100,
                weekday: 1
            ),
            .trigger
        )
    }

    func testAlarmStoreKeepsValidAlarmsWhenOneSavedItemIsInvalid() throws {
        let suiteName = "AlarmStoreLossyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let json = """
        [
          {"id":"valid-1","name":"First","sound":"kind","isAlarmEnabled":true,"isSoundEnabled":true},
          {"id":"invalid","name":"Broken","isAlarmEnabled":true,"isSoundEnabled":true},
          {"id":"valid-2","name":"Second","sound":"siren","isAlarmEnabled":false,"isSoundEnabled":false}
        ]
        """.data(using: .utf8)!
        defaults.set(json, forKey: AlarmStore.savedAlarmsKey)

        let alarms = AlarmStore.load(from: defaults)

        XCTAssertEqual(alarms.map(\.id), ["valid-1", "valid-2"])
    }

    func testAlarmStoreReportsUnreadableSavedData() throws {
        let suiteName = "AlarmStoreUnreadableTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not-json".utf8), forKey: AlarmStore.savedAlarmsKey)

        switch AlarmStore.loadResult(from: defaults) {
        case .success:
            XCTFail("Unreadable data must not be reported as a successful load")
        case .failure(let error):
            XCTAssertEqual(error, .unreadableData)
            XCTAssertEqual(
                error.errorDescription,
                "保存したアラームを読み込めませんでした。もう一度お試しください。"
            )
        }
        XCTAssertEqual(AlarmStore.load(from: defaults), [])
    }

    func testProximityPolicyTriggersWhenWeekdayBecomesEligibleWhileStillInside() {
        let alarm = Alarm(
            id: "weekday-inside",
            name: "Weekday",
            repeatWeekdays: [2],
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false
        )

        XCTAssertEqual(
            AlarmTriggerPolicy.proximityAction(for: alarm, distance: 50, radius: 100, weekday: 1),
            .none
        )
        XCTAssertEqual(
            AlarmTriggerPolicy.proximityAction(for: alarm, distance: 50, radius: 100, weekday: 2),
            .trigger
        )
    }

    func testProximityPolicyResetsAfterExitEvenOnIneligibleWeekday() {
        let alarm = Alarm(
            id: "exit",
            name: "Exit",
            repeatWeekdays: [2],
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false,
            hasTriggered: true,
            hasTriggeredUntilExit: true
        )

        XCTAssertEqual(
            AlarmTriggerPolicy.proximityAction(for: alarm, distance: 101, radius: 100, weekday: 1),
            .resetAfterExit
        )
    }

    func testContinuousLocationMonitoringRequiresAlwaysAuthorization() {
        let alarm = Alarm(
            id: "monitoring",
            name: "Monitoring",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false,
            location: Location(latitude: 34, longitude: 135),
            radius: 5_000
        )

        XCTAssertTrue(LocationManager.shouldRunContinuousLocationMonitoring(
            for: .authorizedAlways,
            alarms: [alarm],
            maximumGeofenceRadius: 1_000
        ))
        XCTAssertFalse(LocationManager.shouldRunContinuousLocationMonitoring(
            for: .authorizedAlways,
            alarms: [],
            maximumGeofenceRadius: 1_000
        ))
        XCTAssertFalse(LocationManager.shouldRunContinuousLocationMonitoring(
            for: .authorizedWhenInUse,
            alarms: [alarm],
            maximumGeofenceRadius: 1_000
        ))
        XCTAssertFalse(LocationManager.shouldRunContinuousLocationMonitoring(
            for: .denied,
            alarms: [alarm],
            maximumGeofenceRadius: 1_000
        ))

        var geofenceAlarm = alarm
        geofenceAlarm.radius = 300
        XCTAssertFalse(LocationManager.shouldRunContinuousLocationMonitoring(
            for: .authorizedAlways,
            alarms: [geofenceAlarm],
            maximumGeofenceRadius: 1_000
        ))
        geofenceAlarm.repeatWeekdays = [1, 3, 5]
        XCTAssertTrue(LocationManager.shouldRunContinuousLocationMonitoring(
            for: .authorizedAlways,
            alarms: [geofenceAlarm],
            maximumGeofenceRadius: 1_000
        ))
    }

    func testUsableLocationRequiresFreshTimestampAndAcceptableAccuracy() {
        let now = Date(timeIntervalSince1970: 1_000)
        let fresh = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 34, longitude: 135),
            altitude: 0,
            horizontalAccuracy: 50,
            verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-5)
        )
        let stale = CLLocation(
            coordinate: fresh.coordinate,
            altitude: 0,
            horizontalAccuracy: 50,
            verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-31)
        )
        let inaccurate = CLLocation(
            coordinate: fresh.coordinate,
            altitude: 0,
            horizontalAccuracy: 101,
            verticalAccuracy: 10,
            timestamp: now
        )

        XCTAssertTrue(LocationManager.isUsableLocation(fresh, now: now, maximumHorizontalAccuracy: 100))
        XCTAssertFalse(LocationManager.isUsableLocation(stale, now: now, maximumHorizontalAccuracy: 100))
        XCTAssertFalse(LocationManager.isUsableLocation(inaccurate, now: now, maximumHorizontalAccuracy: 100))
    }

    func testHapticRepeatCountUsesNilForContinuousAlarmVibration() {
        XCTAssertNil(HapticManager.normalizedRepeatCount(.max))
        XCTAssertEqual(HapticManager.normalizedRepeatCount(10), 10)
        XCTAssertEqual(HapticManager.normalizedRepeatCount(1_000), 300)
        XCTAssertEqual(HapticManager.normalizedRepeatCount(-1), 0)
    }

    func testSoundPlayerOwnershipRejectsReplacementAndWrongIDStopWithoutAudio() {
        let soundPlayer = SoundPlayer.shared
        if let existingID = soundPlayer.activeAlarmID {
            _ = soundPlayer.stopAlarm(id: existingID)
        }
        let ownerID = "sound-owner-\(UUID().uuidString)"
        defer { _ = soundPlayer.stopAlarm(id: ownerID) }

        XCTAssertTrue(
            soundPlayer.startAlarm(
                id: ownerID,
                sound: "__missing_unit_test_sound__"
            )
        )
        XCTAssertEqual(soundPlayer.activeAlarmID, ownerID)
        XCTAssertFalse(
            soundPlayer.startAlarm(
                id: "different-owner",
                sound: "__missing_unit_test_sound__"
            )
        )
        XCTAssertFalse(soundPlayer.stopAlarm(id: "different-owner"))
        XCTAssertEqual(soundPlayer.activeAlarmID, ownerID)

        XCTAssertFalse(
            soundPlayer.playPreview(
                soundName: "__missing_unit_test_preview__"
            )
        )
        XCTAssertEqual(soundPlayer.activeAlarmID, ownerID)
        XCTAssertTrue(soundPlayer.stopAlarm(id: ownerID))
        XCTAssertNil(soundPlayer.activeAlarmID)
    }

    func testHapticOwnerValidationCanBeTestedWithoutProducingHaptics() {
        if let existingID = HapticManager.activeAlarmID {
            _ = HapticManager.stopAlarm(id: existingID)
        }

        XCTAssertFalse(
            HapticManager.startAlarm(
                id: "",
                type: .systemVibrate,
                count: 1,
                interval: 1
            )
        )
        XCTAssertFalse(
            HapticManager.startAlarm(
                id: "zero-count",
                type: .systemVibrate,
                count: 0,
                interval: 1
            )
        )
        HapticManager.startPreview(.systemVibrate, count: 0, interval: 1)
        XCTAssertNil(HapticManager.activeAlarmID)
        XCTAssertFalse(HapticManager.stopAlarm(id: "not-active"))
    }

    func testAlarmAudioSessionMixesAndDucksOtherAudio() {
        let options = SoundPlayer.alarmCategoryOptions
        XCTAssertTrue(options.contains(.mixWithOthers))
        XCTAssertTrue(options.contains(.duckOthers))
        XCTAssertTrue(options.contains(.interruptSpokenAudioAndMixWithOthers))
    }

    func testArrivalPermissionsRequireNotificationSound() {
        XCTAssertTrue(SettingView.areArrivalPermissionsComplete(
            locationAuthorization: .authorizedAlways,
            notificationAuthorization: .authorized,
            notificationSoundSetting: .enabled
        ))
        XCTAssertFalse(SettingView.areArrivalPermissionsComplete(
            locationAuthorization: .authorizedAlways,
            notificationAuthorization: .authorized,
            notificationSoundSetting: .disabled
        ))
    }

    func testPermissionReadinessPredicatesAndIssueOrdering() {
        let ready = makePermissionSnapshot()
        XCTAssertTrue(ready.hasAlwaysLocationAuthorization)
        XCTAssertTrue(ready.hasPreciseLocationAuthorization)
        XCTAssertTrue(ready.hasNotificationAuthorization)
        XCTAssertTrue(ready.hasNotificationSound)
        XCTAssertTrue(ready.hasBackgroundRefresh)
        XCTAssertTrue(ready.authorizationIssues.isEmpty)
        XCTAssertTrue(ready.issues.isEmpty)
        XCTAssertTrue(ready.isReadyForReliableArrival)

        let missing = makePermissionSnapshot(
            locationAuthorization: .authorizedWhenInUse,
            locationAccuracyAuthorization: .reducedAccuracy,
            notificationAuthorization: .denied,
            notificationSoundSetting: .disabled,
            backgroundRefreshStatus: .denied
        )
        XCTAssertEqual(
            missing.authorizationIssues.map(\.rawValue),
            [
                PermissionReadinessIssue.locationAlways.rawValue,
                PermissionReadinessIssue.notificationAuthorization.rawValue
            ]
        )
        XCTAssertEqual(
            missing.issues.map(\.rawValue),
            [
                PermissionReadinessIssue.locationAlways.rawValue,
                PermissionReadinessIssue.preciseLocation.rawValue,
                PermissionReadinessIssue.notificationAuthorization.rawValue,
                PermissionReadinessIssue.backgroundRefresh.rawValue
            ]
        )
        XCTAssertFalse(missing.isReadyForReliableArrival)

        let notificationsNotLoaded = makePermissionSnapshot(
            notificationAuthorization: .denied,
            notificationSoundSetting: .disabled,
            hasLoadedNotificationSettings: false
        )
        XCTAssertFalse(notificationsNotLoaded.hasNotificationAuthorization)
        XCTAssertTrue(notificationsNotLoaded.issues.isEmpty)
        XCTAssertFalse(notificationsNotLoaded.isReadyForReliableArrival)

        let soundDisabled = makePermissionSnapshot(
            notificationSoundSetting: .disabled
        )
        XCTAssertEqual(
            soundDisabled.issues.map(\.rawValue),
            [PermissionReadinessIssue.notificationSound.rawValue]
        )
    }

    func testATTRequestEligibilityRequiresEveryDeferredPromptCondition() {
        let eligible: (
            ATTrackingManager.AuthorizationStatus,
            Int,
            Int,
            Bool,
            Bool
        ) -> Bool = { status, launches, alarms, onboarding, requested in
            ATTRequestEligibility.shouldRequest(
                authorizationStatus: status,
                coldLaunchCount: launches,
                savedAlarmCount: alarms,
                hasCompletedOnboarding: onboarding,
                hasRequestedTrackingAuthorization: requested
            )
        }

        XCTAssertTrue(
            eligible(
                .notDetermined,
                ATTRequestEligibility.minimumColdLaunchCount,
                1,
                true,
                false
            )
        )
        XCTAssertFalse(eligible(.authorized, 3, 1, true, false))
        XCTAssertFalse(eligible(.notDetermined, 2, 1, true, false))
        XCTAssertFalse(eligible(.notDetermined, 3, 0, true, false))
        XCTAssertFalse(eligible(.notDetermined, 3, 1, false, false))
        XCTAssertFalse(eligible(.notDetermined, 3, 1, true, true))
    }

    func testAppLaunchCounterUsesInjectedDefaults() throws {
        let suiteName = "AppLaunchCounterTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(AppLaunchCounter.coldLaunchCount(in: defaults), 0)
        XCTAssertEqual(AppLaunchCounter.recordColdLaunch(in: defaults), 1)
        XCTAssertEqual(AppLaunchCounter.recordColdLaunch(in: defaults), 2)
        XCTAssertEqual(AppLaunchCounter.coldLaunchCount(in: defaults), 2)
    }

    func testAppRuntimeSuppressesExternalSideEffectsInUnitTests() {
        XCTAssertTrue(AppRuntime.shouldSuppressExternalSideEffects)
    }

    private func makeCLLocation(
        latitude: CLLocationDegrees,
        longitude: CLLocationDegrees,
        timestamp: Date
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            ),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: timestamp
        )
    }

    private func makePermissionSnapshot(
        locationAuthorization: CLAuthorizationStatus = .authorizedAlways,
        locationAccuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy,
        notificationAuthorization: UNAuthorizationStatus = .authorized,
        notificationSoundSetting: UNNotificationSetting = .enabled,
        backgroundRefreshStatus: UIBackgroundRefreshStatus = .available,
        hasLoadedNotificationSettings: Bool = true
    ) -> PermissionReadinessSnapshot {
        PermissionReadinessSnapshot(
            locationAuthorization: locationAuthorization,
            locationAccuracyAuthorization: locationAccuracyAuthorization,
            notificationAuthorization: notificationAuthorization,
            notificationSoundSetting: notificationSoundSetting,
            backgroundRefreshStatus: backgroundRefreshStatus,
            hasLoadedNotificationSettings: hasLoadedNotificationSettings
        )
    }
}
