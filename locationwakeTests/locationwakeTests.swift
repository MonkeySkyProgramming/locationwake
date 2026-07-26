import XCTest
import AppTrackingTransparency
import CoreLocation
import UIKit
import UserNotifications
@testable import locationwake

final class locationwakeTests: XCTestCase {

    func testPublishedPersistenceContractKeepsBundleIdentifierAndStorageKey() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "monkey.locationwake")
        XCTAssertEqual(AlarmStore.savedAlarmsKey, "SavedAlarms")
    }

    func testPublishedBundleIdentifierIsLockedForDebugAndRelease() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let projectFile = repositoryRoot
            .appendingPathComponent("locationwake.xcodeproj/project.pbxproj")
        let project = try String(contentsOf: projectFile, encoding: .utf8)
        let contractSetting = "PRODUCT_BUNDLE_IDENTIFIER = monkey.locationwake;"
        let settingCount = project.components(separatedBy: contractSetting).count - 1

        // Debug/Releaseの両方が公開版Bundle IDであることをCIで固定する。
        XCTAssertEqual(settingCount, 2)
    }

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
        XCTAssertTrue(alarm.needsInitialStateCheck)
        XCTAssertFalse(alarm.monitoringSessionID.isEmpty)
        XCTAssertNotNil(alarm.initialStateCheckBeganAt)
        XCTAssertFalse(alarm.isArrivalDeliveryPending)
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
            needsInitialStateCheck: true,
            pendingArrivalOccurrenceID: "round-trip-occurrence",
            pendingArrivalShouldRing: false
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
        XCTAssertEqual(decoded.monitoringSessionID, original.monitoringSessionID)
        XCTAssertEqual(
            decoded.initialStateCheckBeganAt,
            original.initialStateCheckBeganAt
        )
        XCTAssertEqual(
            decoded.pendingArrivalOccurrenceID,
            original.pendingArrivalOccurrenceID
        )
        XCTAssertEqual(
            decoded.pendingArrivalShouldRing,
            original.pendingArrivalShouldRing
        )
    }

    func testArrivalDeliveryQueuePreservesEachOccurrenceUntilItsOwnAcknowledgement() {
        var alarm = Alarm(
            id: "repeat-alarm",
            name: "Destination",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false
        )

        alarm.enqueueArrivalDelivery(occurrenceID: "first")
        alarm.setArrivalDeliveryDecision(
            occurrenceID: "first",
            shouldRing: true
        )
        alarm.enqueueArrivalDelivery(occurrenceID: "second")
        alarm.setArrivalDeliveryDecision(
            occurrenceID: "second",
            shouldRing: false
        )

        XCTAssertEqual(
            alarm.pendingArrivalDeliveries,
            [
                PendingArrivalDelivery(
                    occurrenceID: "first",
                    shouldRing: true,
                    didActivateRinging: false
                ),
                PendingArrivalDelivery(
                    occurrenceID: "second",
                    shouldRing: false
                )
            ]
        )

        alarm.acknowledgeArrivalDelivery(occurrenceID: "first")

        XCTAssertNil(alarm.arrivalDelivery(occurrenceID: "first"))
        XCTAssertEqual(
            alarm.arrivalDelivery(occurrenceID: "second")?.shouldRing,
            false
        )
        XCTAssertEqual(alarm.pendingArrivalOccurrenceID, "second")
        XCTAssertEqual(alarm.pendingArrivalShouldRing, false)
    }

    func testLegacySinglePendingDeliveryMigratesIntoOccurrenceQueue() throws {
        let data = Data(
            """
            {
              "id":"legacy-outbox",
              "name":"Destination",
              "sound":"kind",
              "isAlarmEnabled":true,
              "isSoundEnabled":true,
              "pendingArrivalOccurrenceID":"legacy-occurrence",
              "pendingArrivalShouldRing":false
            }
            """.utf8
        )

        let alarm = try JSONDecoder().decode(Alarm.self, from: data)

        XCTAssertEqual(
            alarm.pendingArrivalDeliveries,
            [
                PendingArrivalDelivery(
                    occurrenceID: "legacy-occurrence",
                    shouldRing: false
                )
            ]
        )
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
          "repeatWeekdays": [1, 3],
          "sound": "modan",
          "isAlarmEnabled": true,
          "isSoundEnabled": true,
          "isVibrationEnabled": true,
          "location": { "latitude": 34.702485, "longitude": 135.495951 },
          "radius": 300,
          "hasTriggered": true,
          "hasTriggeredUntilExit": false
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
        XCTAssertEqual(alarm.name, "Osaka Station")
        XCTAssertEqual(alarm.repeatWeekdays, [1, 3])
        XCTAssertEqual(alarm.sound, "modan")
        XCTAssertTrue(alarm.isAlarmEnabled)
        XCTAssertTrue(alarm.isSoundEnabled)
        XCTAssertTrue(alarm.isVibrationEnabled)
        XCTAssertEqual(alarm.location?.latitude, 34.702485)
        XCTAssertEqual(alarm.location?.longitude, 135.495951)
        XCTAssertEqual(alarm.radius, 300)
        XCTAssertTrue(alarm.hasTriggered)
        XCTAssertFalse(alarm.hasTriggeredUntilExit)
        XCTAssertTrue(alarm.needsInitialStateCheck)
        XCTAssertFalse(alarm.monitoringSessionID.isEmpty)
        XCTAssertNotNil(alarm.initialStateCheckBeganAt)
        XCTAssertNil(defaults.object(forKey: "SkipTrigger_Osaka Station"))
        XCTAssertNil(defaults.object(forKey: "SkipTriggerAt_Osaka Station"))
        XCTAssertNil(defaults.object(forKey: "SkipTrigger_legacy-id"))
        XCTAssertNil(defaults.object(forKey: "SkipTriggerAt_legacy-id"))

        XCTAssertEqual(
            defaults.data(forKey: AlarmStore.migrationBackupKey),
            legacyJSON
        )
        let persisted = try XCTUnwrap(defaults.data(forKey: AlarmStore.savedAlarmsKey))
        XCTAssertTrue(String(decoding: persisted, as: UTF8.self).contains("\"id\""))

        let reloaded = try XCTUnwrap(AlarmStore.load(from: defaults).first)
        XCTAssertEqual(reloaded.id, alarm.id)
        XCTAssertEqual(reloaded.name, alarm.name)
        XCTAssertEqual(reloaded.repeatWeekdays, alarm.repeatWeekdays)
        XCTAssertEqual(reloaded.sound, alarm.sound)
        XCTAssertEqual(reloaded.isAlarmEnabled, alarm.isAlarmEnabled)
        XCTAssertEqual(reloaded.isSoundEnabled, alarm.isSoundEnabled)
        XCTAssertEqual(reloaded.isVibrationEnabled, alarm.isVibrationEnabled)
        XCTAssertEqual(reloaded.location, alarm.location)
        XCTAssertEqual(reloaded.radius, alarm.radius)
        XCTAssertEqual(reloaded.hasTriggered, alarm.hasTriggered)
        XCTAssertEqual(
            reloaded.hasTriggeredUntilExit,
            alarm.hasTriggeredUntilExit
        )
        XCTAssertEqual(
            reloaded.needsInitialStateCheck,
            alarm.needsInitialStateCheck
        )
        XCTAssertEqual(reloaded.monitoringSessionID, alarm.monitoringSessionID)
        XCTAssertEqual(
            reloaded.initialStateCheckBeganAt,
            alarm.initialStateCheckBeganAt
        )
        XCTAssertEqual(
            defaults.data(forKey: AlarmStore.migrationBackupKey),
            legacyJSON
        )
    }

    func testPublishedMultiAlarmPayloadMigratesEnabledDisabledNullAndMissingFields() throws {
        let suiteName = "PublishedAlarmMatrixTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // 公開版のAlarmが生成するキーだけで構成した更新前payload。
        // 全項目あり・Optionalのnull・Optional省略を同時に再現する。
        let publishedData = Data(
            """
            [
              {
                "id":"published-enabled",
                "name":"大阪駅",
                "repeatWeekdays":[0,2,6],
                "sound":"modan",
                "isAlarmEnabled":true,
                "isSoundEnabled":false,
                "isVibrationEnabled":true,
                "location":{"latitude":34.702485,"longitude":135.495951},
                "radius":500,
                "hasTriggered":true,
                "hasTriggeredUntilExit":true
              },
              {
                "id":"published-null-optionals",
                "name":"自宅",
                "repeatWeekdays":null,
                "sound":"siren",
                "isAlarmEnabled":false,
                "isSoundEnabled":true,
                "isVibrationEnabled":false,
                "location":null,
                "radius":null,
                "hasTriggered":false,
                "hasTriggeredUntilExit":false
              },
              {
                "id":"published-missing-optionals",
                "name":"学校",
                "sound":"kind",
                "isAlarmEnabled":false,
                "isSoundEnabled":true
              }
            ]
            """.utf8
        )
        defaults.set(publishedData, forKey: AlarmStore.savedAlarmsKey)

        let alarms = try AlarmStore.loadResult(from: defaults).get()

        XCTAssertEqual(alarms.map(\.id), [
            "published-enabled",
            "published-null-optionals",
            "published-missing-optionals"
        ])

        let enabled = alarms[0]
        XCTAssertEqual(enabled.name, "大阪駅")
        XCTAssertEqual(enabled.repeatWeekdays, [0, 2, 6])
        XCTAssertEqual(enabled.sound, "modan")
        XCTAssertTrue(enabled.isAlarmEnabled)
        XCTAssertFalse(enabled.isSoundEnabled)
        XCTAssertTrue(enabled.isVibrationEnabled)
        XCTAssertEqual(enabled.location, Location(
            latitude: 34.702485,
            longitude: 135.495951
        ))
        XCTAssertEqual(enabled.radius, 500)
        XCTAssertTrue(enabled.hasTriggered)
        XCTAssertTrue(enabled.hasTriggeredUntilExit)
        XCTAssertTrue(enabled.needsInitialStateCheck)
        XCTAssertFalse(enabled.monitoringSessionID.isEmpty)

        let nullOptionals = alarms[1]
        XCTAssertNil(nullOptionals.repeatWeekdays)
        XCTAssertNil(nullOptionals.location)
        XCTAssertNil(nullOptionals.radius)
        XCTAssertFalse(nullOptionals.needsInitialStateCheck)

        let missingOptionals = alarms[2]
        XCTAssertNil(missingOptionals.repeatWeekdays)
        XCTAssertFalse(missingOptionals.isVibrationEnabled)
        XCTAssertNil(missingOptionals.location)
        XCTAssertNil(missingOptionals.radius)
        XCTAssertFalse(missingOptionals.hasTriggered)
        XCTAssertFalse(missingOptionals.hasTriggeredUntilExit)
        XCTAssertFalse(missingOptionals.needsInitialStateCheck)

        XCTAssertEqual(
            defaults.data(forKey: AlarmStore.migrationBackupKey),
            publishedData
        )
        let reloaded = try AlarmStore.loadResult(from: defaults).get()
        XCTAssertEqual(reloaded, alarms)
    }

    func testAlarmNormalizationRegeneratesDuplicateIdentifiers() {
        let alarms = [
            Alarm(id: "duplicate", name: "A", sound: "kind", isAlarmEnabled: true, isSoundEnabled: true, isVibrationEnabled: false, monitoringSessionID: "same-session"),
            Alarm(id: "duplicate", name: "B", sound: "kind", isAlarmEnabled: true, isSoundEnabled: true, isVibrationEnabled: false, monitoringSessionID: "same-session")
        ]

        let normalized = Alarm.normalizedForPersistence(alarms)
        XCTAssertEqual(normalized[0].id, "duplicate")
        XCTAssertNotEqual(normalized[0].id, normalized[1].id)
        XCTAssertEqual(normalized[0].monitoringSessionID, "same-session")
        XCTAssertNotEqual(
            normalized[0].monitoringSessionID,
            normalized[1].monitoringSessionID
        )
        XCTAssertTrue(normalized[1].needsInitialStateCheck)
        XCTAssertNotNil(normalized[1].initialStateCheckBeganAt)
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

    func testAlarmSchedulerKeepsRepeatedArrivalsAsDistinctNotifications() {
        let alarm = Alarm(
            id: "repeat-alarm",
            name: "Destination",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false
        )

        let first = AlarmScheduler.makeNotificationRequest(
            for: alarm,
            isRinging: true,
            occurrenceID: "first"
        )
        let second = AlarmScheduler.makeNotificationRequest(
            for: alarm,
            isRinging: false,
            occurrenceID: "second"
        )

        XCTAssertEqual(first.identifier, "repeat-alarm.arrival.first")
        XCTAssertEqual(second.identifier, "repeat-alarm.arrival.second")
        XCTAssertNotEqual(first.identifier, second.identifier)
        XCTAssertEqual(
            first.content.userInfo["occurrenceID"] as? String,
            "first"
        )
        XCTAssertEqual(
            second.content.userInfo["occurrenceID"] as? String,
            "second"
        )
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

    func testNotificationOperationTrackerCancelsLateAddsWithoutRemovingANewerSchedule() {
        var tracker = AlarmNotificationOperationTracker()
        let firstSchedule = tracker.schedule(identifier: "alarm")
        XCTAssertTrue(tracker.shouldProceedWithAdd(token: firstSchedule))

        _ = tracker.cancel(identifier: "alarm")
        XCTAssertFalse(tracker.shouldProceedWithAdd(token: firstSchedule))
        XCTAssertTrue(tracker.shouldRemoveAfterAdd(token: firstSchedule))

        let newerSchedule = tracker.schedule(identifier: "alarm")
        XCTAssertTrue(tracker.shouldProceedWithAdd(token: newerSchedule))
        XCTAssertFalse(tracker.shouldRemoveAfterAdd(token: firstSchedule))
        XCTAssertFalse(tracker.shouldRemoveAfterAdd(token: newerSchedule))
    }

    func testNotificationOperationTrackerRetiresTerminalIdentifiers() {
        var tracker = AlarmNotificationOperationTracker()
        let completedSchedule = tracker.schedule(identifier: "completed")
        XCTAssertEqual(tracker.trackedIdentifierCount, 1)
        XCTAssertEqual(
            tracker.complete(token: completedSchedule),
            .current
        )
        XCTAssertEqual(tracker.trackedIdentifierCount, 0)

        let cancelledSchedule = tracker.schedule(identifier: "cancelled")
        _ = tracker.cancel(identifier: "cancelled")
        XCTAssertEqual(tracker.trackedIdentifierCount, 1)
        XCTAssertEqual(
            tracker.complete(token: cancelledSchedule),
            .explicitlyCancelled
        )
        XCTAssertEqual(tracker.trackedIdentifierCount, 0)

        _ = tracker.cancel(identifier: "nothing-in-flight")
        XCTAssertEqual(tracker.trackedIdentifierCount, 0)
    }

    func testNotificationScheduleResultPrioritizesCancellationAndSupersessionOverLateErrors() {
        XCTAssertEqual(
            AlarmScheduler.scheduleResult(
                disposition: .explicitlyCancelled,
                hasError: true
            ),
            .cancelled
        )
        XCTAssertEqual(
            AlarmScheduler.scheduleResult(
                disposition: .superseded,
                hasError: true
            ),
            .superseded
        )
        XCTAssertEqual(
            AlarmScheduler.scheduleResult(
                disposition: .current,
                hasError: true
            ),
            .failed
        )
        XCTAssertEqual(
            AlarmScheduler.scheduleResult(
                disposition: .current,
                hasError: false
            ),
            .enqueued
        )
    }

    func testArrivalDeliveryCompletionAcknowledgesAnExplicitStopDuringNotificationAdd() {
        XCTAssertEqual(
            LocationManager.arrivalDeliveryCompletionAction(
                for: .cancelled,
                shouldRing: true,
                ownsPlayback: false
            ),
            .acknowledge
        )
        XCTAssertEqual(
            LocationManager.arrivalDeliveryCompletionAction(
                for: .cancelled,
                shouldRing: true,
                ownsPlayback: true
            ),
            .none
        )
        XCTAssertEqual(
            LocationManager.arrivalDeliveryCompletionAction(
                for: .cancelled,
                shouldRing: false,
                ownsPlayback: false
            ),
            .none
        )
        XCTAssertEqual(
            LocationManager.arrivalDeliveryCompletionAction(
                for: .enqueued,
                shouldRing: false,
                ownsPlayback: false
            ),
            .acknowledge
        )
        XCTAssertEqual(
            LocationManager.arrivalDeliveryCompletionAction(
                for: .failed,
                shouldRing: true,
                ownsPlayback: true
            ),
            .retry
        )
    }

    func testAlarmPlaybackStateMachineArbitratesAndStopsByExactID() {
        var state = AlarmPlaybackStateMachine()

        XCTAssertEqual(
            state.registerArrival(
                alarmID: "first",
                occurrenceID: "first-occurrence"
            ),
            .ring
        )
        XCTAssertEqual(state.activeAlarmID, "first")
        XCTAssertEqual(state.activeOccurrenceID, "first-occurrence")
        XCTAssertEqual(
            state.registerArrival(
                alarmID: "first",
                occurrenceID: "second-occurrence"
            ),
            .notifyOnly
        )
        XCTAssertEqual(
            state.registerArrival(
                alarmID: "first",
                occurrenceID: "first-occurrence",
                recoveringPendingDelivery: true
            ),
            .ring
        )
        XCTAssertEqual(state.activeAlarmID, "first")
        XCTAssertEqual(state.activeOccurrenceID, "first-occurrence")
        XCTAssertEqual(
            state.registerArrival(
                alarmID: "second",
                occurrenceID: "third-occurrence"
            ),
            .notifyOnly
        )
        XCTAssertEqual(state.activeAlarmID, "first")

        XCTAssertFalse(state.stop(alarmID: "second"))
        XCTAssertEqual(state.activeAlarmID, "first")
        XCTAssertTrue(state.stop(alarmID: "first"))
        XCTAssertNil(state.activeAlarmID)
        XCTAssertNil(state.activeOccurrenceID)

        XCTAssertEqual(
            state.registerArrival(
                alarmID: "second",
                occurrenceID: "third-occurrence"
            ),
            .ring
        )
        XCTAssertEqual(state.activeAlarmID, "second")
    }

    func testAlarmActivityCenterRestoresPresentationAcrossProcessState() throws {
        let suiteName = "AlarmActivityCenterTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let alarm = Alarm(
            id: "restored-active",
            name: "Restored",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: false,
            isVibrationEnabled: false
        )

        let firstProcess = AlarmActivityCenter(defaults: defaults)
        XCTAssertEqual(firstProcess.registerArrival(for: alarm), .ring)
        XCTAssertTrue(AlarmActivityCenter.hasPersistedState(in: defaults))

        let relaunchedProcess = AlarmActivityCenter(defaults: defaults)
        XCTAssertEqual(
            relaunchedProcess.activeAlarm,
            ActiveAlarmPresentation(
                alarmID: alarm.id,
                name: alarm.name
            )
        )
        relaunchedProcess.presentCurrentAlarmIfNeeded()
        XCTAssertEqual(
            relaunchedProcess.activeAlarm?.alarmID,
            alarm.id
        )
    }

    func testLegacyActiveAlarmKeysMigrateToAtomicRecord() throws {
        let suiteName = "AlarmActivityLegacyMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("legacy-active", forKey: "ActiveAlarmID")
        defaults.set("legacy-occurrence", forKey: "ActiveAlarmOccurrenceID")
        defaults.set("Legacy alarm", forKey: "ActiveAlarmName")
        defaults.set("kind", forKey: "ActiveAlarmSound")
        defaults.set(false, forKey: "ActiveAlarmSoundEnabled")
        defaults.set(true, forKey: "ActiveAlarmVibrationEnabled")

        let migratedProcess = AlarmActivityCenter(defaults: defaults)

        XCTAssertEqual(
            migratedProcess.activeAlarm,
            ActiveAlarmPresentation(
                alarmID: "legacy-active",
                name: "Legacy alarm"
            )
        )
        XCTAssertTrue(
            migratedProcess.isPlaybackActivated(
                alarmID: "legacy-active",
                occurrenceID: "legacy-occurrence"
            )
        )
        XCTAssertNotNil(defaults.data(forKey: "ActiveAlarmRecordV1"))
        XCTAssertNil(defaults.object(forKey: "ActiveAlarmID"))
        XCTAssertNil(defaults.object(forKey: "ActiveAlarmOccurrenceID"))
        XCTAssertNil(defaults.object(forKey: "ActiveAlarmName"))
        XCTAssertNil(defaults.object(forKey: "ActiveAlarmSound"))
        XCTAssertNil(defaults.object(forKey: "ActiveAlarmSoundEnabled"))
        XCTAssertNil(defaults.object(forKey: "ActiveAlarmVibrationEnabled"))

        let relaunchedProcess = AlarmActivityCenter(defaults: defaults)
        XCTAssertTrue(
            relaunchedProcess.ownsPlayback(
                alarmID: "legacy-active",
                occurrenceID: "legacy-occurrence"
            )
        )
        XCTAssertTrue(relaunchedProcess.stop(alarmID: "legacy-active"))
    }

    func testPartialLegacyActivationWithoutAlarmIDIsIgnored() throws {
        let suiteName = "AlarmActivityCommitMarkerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            "partial-occurrence",
            forKey: "ActiveAlarmOccurrenceID"
        )
        defaults.set("Partial", forKey: "ActiveAlarmName")
        defaults.set("kind", forKey: "ActiveAlarmSound")
        defaults.set(false, forKey: "ActiveAlarmSoundEnabled")
        defaults.set(false, forKey: "ActiveAlarmVibrationEnabled")

        let center = AlarmActivityCenter(defaults: defaults)

        XCTAssertNil(center.activeAlarm)
        XCTAssertFalse(AlarmActivityCenter.hasPersistedState(in: defaults))
        XCTAssertFalse(
            center.ownsPlayback(
                alarmID: "partial-alarm",
                occurrenceID: "partial-occurrence"
            )
        )
    }

    func testArrivalReservationHasNoVisibleOrPersistentSideEffects() throws {
        let suiteName = "AlarmActivityReservationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let center = AlarmActivityCenter(defaults: defaults)

        XCTAssertEqual(
            center.reserveArrival(
                alarmID: "reserved",
                occurrenceID: "reserved-occurrence"
            ),
            .ring
        )
        XCTAssertTrue(
            center.ownsPlayback(
                alarmID: "reserved",
                occurrenceID: "reserved-occurrence"
            )
        )
        XCTAssertNil(center.activeAlarm)
        XCTAssertFalse(AlarmActivityCenter.hasPersistedState(in: defaults))
        XCTAssertNil(defaults.object(forKey: "ActiveAlarmID"))
        XCTAssertNil(defaults.object(forKey: "ActiveAlarmOccurrenceID"))

        XCTAssertTrue(
            center.releaseReservedArrival(
                alarmID: "reserved",
                occurrenceID: "reserved-occurrence"
            )
        )
        XCTAssertFalse(
            center.ownsPlayback(
                alarmID: "reserved",
                occurrenceID: "reserved-occurrence"
            )
        )
    }

    func testArrivalDecisionSaveFailureDoesNotStartAlarm() throws {
        let suiteName = "ArrivalSaveFailureTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let center = AlarmActivityCenter(defaults: defaults)
        let manager = LocationManager()
        manager.alarmActivityCenter = center
        manager.alarmSaveHandler = { _ in .failure(.encodingFailed) }
        var alarm = Alarm(
            id: "save-failure",
            name: "Save failure",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: false,
            isVibrationEnabled: false
        )
        alarm.enqueueArrivalDelivery(occurrenceID: "save-failure-occurrence")
        manager.alarms = [alarm]

        manager.deliverArrival(
            alarmID: alarm.id,
            occurrenceID: "save-failure-occurrence"
        )

        XCTAssertNil(center.activeAlarm)
        XCTAssertFalse(AlarmActivityCenter.hasPersistedState(in: defaults))
        XCTAssertNil(defaults.object(forKey: "ActiveAlarmID"))
        XCTAssertFalse(
            center.ownsPlayback(
                alarmID: alarm.id,
                occurrenceID: "save-failure-occurrence"
            )
        )
        XCTAssertNil(
            manager.alarms[0].arrivalDelivery(
                occurrenceID: "save-failure-occurrence"
            )?.shouldRing
        )
    }

    func testReservedArrivalRecoversWhenProcessEndedBeforeActivation() throws {
        let suiteName = "ArrivalPreActivationRecoveryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let center = AlarmActivityCenter(defaults: defaults)
        let manager = LocationManager()
        manager.alarmActivityCenter = center
        manager.alarmSaveHandler = { _ in .success(()) }
        var alarm = Alarm(
            id: "pre-activation",
            name: "Pre activation",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: false,
            isVibrationEnabled: false
        )
        alarm.enqueueArrivalDelivery(occurrenceID: "pre-activation-occurrence")
        alarm.setArrivalDeliveryDecision(
            occurrenceID: "pre-activation-occurrence",
            shouldRing: true
        )
        manager.alarms = [alarm]

        XCTAssertTrue(
            manager.deliverArrival(
                alarmID: alarm.id,
                occurrenceID: "pre-activation-occurrence",
                recoveringPendingDelivery: true
            )
        )

        XCTAssertEqual(center.activeAlarm?.alarmID, alarm.id)
        XCTAssertTrue(
            center.isPlaybackActivated(
                alarmID: alarm.id,
                occurrenceID: "pre-activation-occurrence"
            )
        )
        XCTAssertEqual(
            manager.alarms[0].arrivalDelivery(
                occurrenceID: "pre-activation-occurrence"
            )?.didActivateRinging,
            true
        )
    }

    func testActivatedArrivalWithoutOwnershipIsRecoveredAsExplicitlyStopped() throws {
        let suiteName = "ArrivalStoppedRecoveryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let center = AlarmActivityCenter(defaults: defaults)
        let manager = LocationManager()
        manager.alarmActivityCenter = center
        manager.alarmSaveHandler = { _ in .success(()) }
        let delegate = LocationManagerDelegateSpy()
        manager.delegate = delegate
        var alarm = Alarm(
            id: "stopped-arrival",
            name: "Stopped arrival",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: false,
            isVibrationEnabled: false
        )
        alarm.enqueueArrivalDelivery(occurrenceID: "stopped-occurrence")
        alarm.setArrivalDeliveryDecision(
            occurrenceID: "stopped-occurrence",
            shouldRing: true
        )
        alarm.markArrivalDeliveryActivated(
            occurrenceID: "stopped-occurrence"
        )
        manager.alarms = [alarm]

        XCTAssertTrue(
            manager.deliverArrival(
                alarmID: alarm.id,
                occurrenceID: "stopped-occurrence",
                recoveringPendingDelivery: true,
                notifyChangeOnSuccess: true
            )
        )

        XCTAssertNil(center.activeAlarm)
        XCTAssertNil(
            manager.alarms[0].arrivalDelivery(
                occurrenceID: "stopped-occurrence"
            )
        )
        XCTAssertEqual(delegate.updatedAlarms.count, 1)
    }

    func testPendingRecoverySaveFailureDoesNotPublishAlarmUpdate() throws {
        let suiteName = "PendingRecoverySaveFailureTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let center = AlarmActivityCenter(defaults: defaults)
        let manager = LocationManager()
        manager.alarmActivityCenter = center
        manager.alarmSaveHandler = { _ in .failure(.encodingFailed) }
        let delegate = LocationManagerDelegateSpy()
        manager.delegate = delegate
        var didPostAlarmUpdate = false
        let token = NotificationCenter.default.addObserver(
            forName: .alarmUpdated,
            object: nil,
            queue: nil
        ) { _ in
            didPostAlarmUpdate = true
        }
        defer { NotificationCenter.default.removeObserver(token) }
        var alarm = Alarm(
            id: "pending-save-failure",
            name: "Pending save failure",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: false,
            isVibrationEnabled: false
        )
        alarm.enqueueArrivalDelivery(occurrenceID: "pending-save-occurrence")

        _ = manager.restoreSavedAlarms(
            reason: "unit-test-pending-save-failure",
            loadResult: .success([alarm])
        )

        XCTAssertTrue(delegate.updatedAlarms.isEmpty)
        XCTAssertFalse(didPostAlarmUpdate)
        XCTAssertNil(center.activeAlarm)
    }

    func testArrivalDeliverySerializesPersistenceOnMainQueue() throws {
        let suiteName = "ArrivalMainQueueTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let center = AlarmActivityCenter(defaults: defaults)
        let manager = LocationManager()
        manager.alarmActivityCenter = center
        let saveExpectation = expectation(description: "arrival saves on main")
        saveExpectation.expectedFulfillmentCount = 2
        manager.alarmSaveHandler = { _ in
            XCTAssertTrue(Thread.isMainThread)
            saveExpectation.fulfill()
            return .success(())
        }
        var alarm = Alarm(
            id: "main-serialized",
            name: "Main serialized",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: false,
            isVibrationEnabled: false
        )
        alarm.enqueueArrivalDelivery(occurrenceID: "main-occurrence")
        manager.alarms = [alarm]
        let completion = expectation(description: "background caller returns")

        DispatchQueue.global(qos: .userInitiated).async {
            _ = manager.deliverArrival(
                alarmID: alarm.id,
                occurrenceID: "main-occurrence"
            )
            completion.fulfill()
        }

        wait(for: [saveExpectation, completion], timeout: 3)
        XCTAssertTrue(
            center.isPlaybackActivated(
                alarmID: alarm.id,
                occurrenceID: "main-occurrence"
            )
        )
        _ = center.stop(alarmID: alarm.id)
    }

    func testConcurrentArrivalsProduceOneRingAndOneNotificationOnlyDecision() throws {
        let suiteName = "ConcurrentArrivalTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let center = AlarmActivityCenter(defaults: defaults)
        let manager = LocationManager()
        manager.alarmActivityCenter = center
        manager.alarmSaveHandler = { _ in .success(()) }
        var scheduledDecisions: [Bool] = []
        manager.alarmScheduleOverride = { _, shouldRing, _ in
            XCTAssertTrue(Thread.isMainThread)
            scheduledDecisions.append(shouldRing)
        }
        var first = Alarm(
            id: "concurrent-first",
            name: "Concurrent first",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: false,
            isVibrationEnabled: false
        )
        var second = Alarm(
            id: "concurrent-second",
            name: "Concurrent second",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: false,
            isVibrationEnabled: false
        )
        first.enqueueArrivalDelivery(occurrenceID: "concurrent-occurrence-1")
        second.enqueueArrivalDelivery(occurrenceID: "concurrent-occurrence-2")
        manager.alarms = [first, second]
        let completion = expectation(description: "both arrivals complete")
        completion.expectedFulfillmentCount = 2

        DispatchQueue.global(qos: .userInitiated).async {
            _ = manager.deliverArrival(
                alarmID: first.id,
                occurrenceID: "concurrent-occurrence-1"
            )
            completion.fulfill()
        }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = manager.deliverArrival(
                alarmID: second.id,
                occurrenceID: "concurrent-occurrence-2"
            )
            completion.fulfill()
        }

        wait(for: [completion], timeout: 3)
        let decisions = manager.alarms.compactMap {
            $0.pendingArrivalDeliveries.first?.shouldRing
        }
        XCTAssertEqual(decisions.filter { $0 }.count, 1)
        XCTAssertEqual(decisions.filter { !$0 }.count, 1)
        XCTAssertEqual(scheduledDecisions.filter { $0 }.count, 1)
        XCTAssertEqual(scheduledDecisions.filter { !$0 }.count, 1)
        if let activeAlarmID = center.activeAlarm?.alarmID {
            _ = center.stop(alarmID: activeAlarmID)
        } else {
            XCTFail("One concurrent arrival must own playback")
        }
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
        let previousSessionID = alarm.monitoringSessionID

        alarm.setEnabled(true)

        XCTAssertTrue(alarm.isAlarmEnabled)
        XCTAssertFalse(alarm.hasTriggered)
        XCTAssertFalse(alarm.hasTriggeredUntilExit)
        XCTAssertTrue(alarm.needsInitialStateCheck)
        XCTAssertNotEqual(alarm.monitoringSessionID, previousSessionID)
        XCTAssertNotNil(alarm.initialStateCheckBeganAt)
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

        let previousSessionID = alarm.monitoringSessionID
        let beganAt = Date(timeIntervalSince1970: 1_000)
        alarm.prepareForInitialStateCheck(
            sessionID: "new-monitoring-session",
            now: beganAt
        )
        XCTAssertTrue(alarm.needsInitialStateCheck)
        XCTAssertFalse(alarm.hasTriggered)
        XCTAssertFalse(alarm.hasTriggeredUntilExit)
        XCTAssertNotEqual(alarm.monitoringSessionID, previousSessionID)
        XCTAssertEqual(alarm.monitoringSessionID, "new-monitoring-session")
        XCTAssertEqual(alarm.initialStateCheckBeganAt, beganAt)

        var inside = alarm
        inside.resolveInitialState(isInside: true)
        XCTAssertFalse(inside.needsInitialStateCheck)
        XCTAssertFalse(inside.hasTriggered)
        XCTAssertTrue(inside.hasTriggeredUntilExit)
        XCTAssertNil(inside.initialStateCheckBeganAt)

        var outside = alarm
        outside.resolveInitialState(isInside: false)
        XCTAssertFalse(outside.needsInitialStateCheck)
        XCTAssertFalse(outside.hasTriggered)
        XCTAssertFalse(outside.hasTriggeredUntilExit)
        XCTAssertNil(outside.initialStateCheckBeganAt)
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
            currentLocation: insideLocation,
            sessionID: "inside-session",
            now: now
        )
        XCTAssertFalse(inside.needsInitialStateCheck)
        XCTAssertFalse(inside.hasTriggered)
        XCTAssertTrue(inside.hasTriggeredUntilExit)

        let outside = LocationManager.preparedForInitialStateCheck(
            alarm,
            currentLocation: outsideLocation,
            sessionID: "outside-session",
            now: now
        )
        XCTAssertFalse(outside.needsInitialStateCheck)
        XCTAssertFalse(outside.hasTriggered)
        XCTAssertFalse(outside.hasTriggeredUntilExit)

        let unknown = LocationManager.preparedForInitialStateCheck(
            alarm,
            currentLocation: nil,
            sessionID: "unknown-session",
            now: now
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
            ),
            sessionID: "stale-session",
            now: now
        )
        XCTAssertTrue(stale.needsInitialStateCheck)
        XCTAssertFalse(stale.hasTriggeredUntilExit)

        let recentlyOutsideBeforeSave = LocationManager.preparedForInitialStateCheck(
            alarm,
            currentLocation: makeCLLocation(
                latitude: target.latitude + 0.01,
                longitude: target.longitude,
                timestamp: now.addingTimeInterval(-1)
            ),
            sessionID: "pre-save-session",
            now: now
        )
        XCTAssertTrue(recentlyOutsideBeforeSave.needsInitialStateCheck)
        XCTAssertFalse(recentlyOutsideBeforeSave.hasTriggeredUntilExit)
        XCTAssertFalse(
            recentlyOutsideBeforeSave.canResolveInitialState(
                usingLocationTimestamp: now.addingTimeInterval(-1)
            )
        )
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

    func testBoundaryAccuracyDoesNotArmResetOrTriggerUntilPositionIsCertain() {
        XCTAssertEqual(
            AlarmTriggerPolicy.boundaryState(
                distance: 105,
                radius: 100,
                horizontalAccuracy: 20
            ),
            .uncertain
        )
        XCTAssertEqual(
            AlarmTriggerPolicy.boundaryState(
                distance: 121,
                radius: 100,
                horizontalAccuracy: 20
            ),
            .outside
        )
        XCTAssertEqual(
            AlarmTriggerPolicy.boundaryState(
                distance: 80,
                radius: 100,
                horizontalAccuracy: 20
            ),
            .inside
        )

        let armedAlarm = Alarm(
            id: "boundary-armed",
            name: "Boundary",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false
        )
        XCTAssertEqual(
            AlarmTriggerPolicy.proximityAction(
                for: armedAlarm,
                distance: 90,
                radius: 100,
                weekday: 1,
                horizontalAccuracy: 20
            ),
            .none
        )
        XCTAssertEqual(
            AlarmTriggerPolicy.proximityAction(
                for: armedAlarm,
                distance: 79,
                radius: 100,
                weekday: 1,
                horizontalAccuracy: 20
            ),
            .trigger
        )

        let latchedAlarm = Alarm(
            id: "boundary-latched",
            name: "Boundary",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false,
            hasTriggered: true,
            hasTriggeredUntilExit: true
        )
        XCTAssertEqual(
            AlarmTriggerPolicy.proximityAction(
                for: latchedAlarm,
                distance: 105,
                radius: 100,
                weekday: 1,
                horizontalAccuracy: 20
            ),
            .none
        )
        XCTAssertEqual(
            AlarmTriggerPolicy.proximityAction(
                for: latchedAlarm,
                distance: 121,
                radius: 100,
                weekday: 1,
                horizontalAccuracy: 20
            ),
            .resetAfterExit
        )
    }

    func testPreparedInitialStateCheckWaitsWhenAccuracyOverlapsBoundary() {
        let target = Location(latitude: 34.0, longitude: 135.0)
        let alarm = Alarm(
            id: "ambiguous-initial-state",
            name: "Ambiguous",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false,
            location: target,
            radius: 100
        )
        let now = Date()
        let nearBoundary = CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: target.latitude + 0.0009,
                longitude: target.longitude
            ),
            altitude: 0,
            horizontalAccuracy: 30,
            verticalAccuracy: 10,
            timestamp: now
        )

        let prepared = LocationManager.preparedForInitialStateCheck(
            alarm,
            currentLocation: nearBoundary,
            sessionID: "ambiguous-session",
            now: now
        )

        XCTAssertTrue(prepared.needsInitialStateCheck)
        XCTAssertFalse(prepared.hasTriggered)
        XCTAssertFalse(prepared.hasTriggeredUntilExit)
    }

    func testAlarmStorePreservesMixedValidAndInvalidSavedDataWithoutPartialRewrite() throws {
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
        let existingBackup = Data("existing-backup".utf8)
        defaults.set(existingBackup, forKey: AlarmStore.migrationBackupKey)
        defaults.set(true, forKey: "SkipTrigger_First")

        XCTAssertEqual(
            AlarmStore.loadResult(from: defaults),
            .failure(.unreadableData)
        )
        XCTAssertEqual(
            defaults.data(forKey: AlarmStore.savedAlarmsKey),
            json
        )
        XCTAssertEqual(
            defaults.data(forKey: AlarmStore.migrationBackupKey),
            existingBackup
        )
        XCTAssertTrue(defaults.bool(forKey: "SkipTrigger_First"))
    }

    func testAlarmStoreEncodingFailureLeavesPublishedDataUntouched() throws {
        let suiteName = "AlarmStoreEncodingFailureTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let publishedData = Data(
            """
            [{"id":"published","name":"Station","sound":"kind","isAlarmEnabled":true,"isSoundEnabled":true}]
            """.utf8
        )
        defaults.set(publishedData, forKey: AlarmStore.savedAlarmsKey)
        let invalidAlarm = Alarm(
            id: "invalid",
            name: "Invalid coordinate",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false,
            location: Location(latitude: .nan, longitude: 135),
            radius: 300
        )

        switch AlarmStore.save([invalidAlarm], to: defaults) {
        case .success:
            XCTFail("Non-finite coordinates must not overwrite saved alarms")
        case .failure(let error):
            XCTAssertEqual(error, .encodingFailed)
        }
        XCTAssertEqual(
            defaults.data(forKey: AlarmStore.savedAlarmsKey),
            publishedData
        )
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

    func testAlarmStoreRejectsExistingNonDataValueInsteadOfTreatingItAsEmpty() throws {
        let suiteName = "AlarmStoreWrongTypeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("not-alarm-data", forKey: AlarmStore.savedAlarmsKey)

        XCTAssertEqual(
            AlarmStore.loadResult(from: defaults),
            .failure(.unreadableData)
        )
        XCTAssertEqual(
            defaults.string(forKey: AlarmStore.savedAlarmsKey),
            "not-alarm-data"
        )
        XCTAssertNil(defaults.object(forKey: AlarmStore.corruptPrimaryBackupKey))
    }

    func testAlarmStoreRecoversFromMigrationBackupAndPreservesCorruptPrimary() throws {
        let suiteName = "AlarmStoreRecoveryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let corruptPrimary = Data("not-json".utf8)
        let publishedBackup = Data(
            """
            [{"name":"Published station","repeatWeekdays":null,"sound":"kind","isAlarmEnabled":true,"isSoundEnabled":true,"location":{"latitude":34.7,"longitude":135.5},"radius":300}]
            """.utf8
        )
        defaults.set(corruptPrimary, forKey: AlarmStore.savedAlarmsKey)
        defaults.set(publishedBackup, forKey: AlarmStore.migrationBackupKey)

        let result = AlarmStore.loadResult(from: defaults)

        guard case .success(let alarms) = result else {
            return XCTFail("Valid published backup must recover the alarm list")
        }
        XCTAssertEqual(alarms.map(\.name), ["Published station"])
        XCTAssertEqual(
            defaults.data(forKey: AlarmStore.corruptPrimaryBackupKey),
            corruptPrimary
        )
        XCTAssertEqual(
            defaults.data(forKey: AlarmStore.migrationBackupKey),
            publishedBackup
        )
        let restoredData = try XCTUnwrap(
            defaults.data(forKey: AlarmStore.savedAlarmsKey)
        )
        XCTAssertEqual(
            try JSONDecoder().decode([Alarm].self, from: restoredData).map(\.name),
            ["Published station"]
        )

        guard case .success(let secondLoad) = AlarmStore.loadResult(
            from: defaults
        ) else {
            return XCTFail("Recovered primary must be idempotently readable")
        }
        XCTAssertEqual(secondLoad.map(\.name), ["Published station"])
        XCTAssertEqual(
            defaults.data(forKey: AlarmStore.savedAlarmsKey),
            restoredData
        )
        XCTAssertEqual(
            defaults.data(forKey: AlarmStore.corruptPrimaryBackupKey),
            corruptPrimary
        )
        XCTAssertEqual(
            defaults.data(forKey: AlarmStore.migrationBackupKey),
            publishedBackup
        )
    }

    func testNonDataPrimaryRecoversOnlyWhenMigrationBackupIsValid() throws {
        let suiteName = "AlarmStoreWrongTypeRecoveryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let wrongTypePrimary = "wrong-type-primary"
        let publishedBackup = Data(
            """
            [{"name":"Backup alarm","sound":"kind","isAlarmEnabled":false,"isSoundEnabled":true}]
            """.utf8
        )
        defaults.set(wrongTypePrimary, forKey: AlarmStore.savedAlarmsKey)
        defaults.set(publishedBackup, forKey: AlarmStore.migrationBackupKey)

        guard case .success(let alarms) = AlarmStore.loadResult(
            from: defaults
        ) else {
            return XCTFail("A valid migration backup should recover a wrong-type primary")
        }

        XCTAssertEqual(alarms.map(\.name), ["Backup alarm"])
        XCTAssertEqual(
            defaults.string(forKey: AlarmStore.corruptPrimaryBackupKey),
            wrongTypePrimary
        )
        let restoredData = try XCTUnwrap(
            defaults.data(forKey: AlarmStore.savedAlarmsKey)
        )
        XCTAssertEqual(
            try JSONDecoder().decode([Alarm].self, from: restoredData).map(\.name),
            ["Backup alarm"]
        )
    }

    func testMissingPrimaryDoesNotResurrectMigrationBackup() throws {
        let suiteName = "AlarmStoreMissingPrimaryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let publishedBackup = Data(
            """
            [{"name":"Old alarm","sound":"kind","isAlarmEnabled":true,"isSoundEnabled":true}]
            """.utf8
        )
        defaults.set(publishedBackup, forKey: AlarmStore.migrationBackupKey)

        XCTAssertEqual(
            AlarmStore.loadResult(from: defaults),
            .success([])
        )
        XCTAssertNil(defaults.object(forKey: AlarmStore.savedAlarmsKey))
        XCTAssertEqual(
            defaults.data(forKey: AlarmStore.migrationBackupKey),
            publishedBackup
        )
    }

    func testSecondCorruptionDoesNotOverwriteNewerPrimaryWithOldBackup() throws {
        let suiteName = "AlarmStoreRepeatedCorruptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let currentCorruptPrimary = Data("newer-corrupt-primary".utf8)
        let firstCorruptPrimary = Data("first-corrupt-primary".utf8)
        let publishedBackup = Data(
            """
            [{"name":"Old alarm","sound":"kind","isAlarmEnabled":true,"isSoundEnabled":true}]
            """.utf8
        )
        defaults.set(
            currentCorruptPrimary,
            forKey: AlarmStore.savedAlarmsKey
        )
        defaults.set(
            firstCorruptPrimary,
            forKey: AlarmStore.corruptPrimaryBackupKey
        )
        defaults.set(
            "stale-recovery",
            forKey: AlarmStore.recoveryInProgressKey
        )
        defaults.set(publishedBackup, forKey: AlarmStore.migrationBackupKey)

        XCTAssertEqual(
            AlarmStore.loadResult(from: defaults),
            .failure(.unreadableData)
        )
        XCTAssertEqual(
            defaults.data(forKey: AlarmStore.savedAlarmsKey),
            currentCorruptPrimary
        )
        XCTAssertEqual(
            defaults.data(forKey: AlarmStore.corruptPrimaryBackupKey),
            firstCorruptPrimary
        )
        XCTAssertNil(defaults.object(forKey: AlarmStore.recoveryInProgressKey))

        // transactionを中止した後にprimaryが旧snapshotと一致しても、
        // 古いbackupを復活させない。
        defaults.set(firstCorruptPrimary, forKey: AlarmStore.savedAlarmsKey)
        XCTAssertEqual(
            AlarmStore.loadResult(from: defaults),
            .failure(.unreadableData)
        )
        XCTAssertEqual(
            defaults.data(forKey: AlarmStore.savedAlarmsKey),
            firstCorruptPrimary
        )
    }

    func testInterruptedFirstRecoveryResumesWhenSnapshotMatchesPrimary() throws {
        let suiteName = "AlarmStoreInterruptedRecoveryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let corruptPrimary = Data("same-corrupt-primary".utf8)
        let publishedBackup = Data(
            """
            [{"name":"Recovered","sound":"kind","isAlarmEnabled":true,"isSoundEnabled":true}]
            """.utf8
        )
        defaults.set(corruptPrimary, forKey: AlarmStore.savedAlarmsKey)
        defaults.set(
            corruptPrimary,
            forKey: AlarmStore.corruptPrimaryBackupKey
        )
        defaults.set(
            "interrupted-recovery",
            forKey: AlarmStore.recoveryInProgressKey
        )
        defaults.set(publishedBackup, forKey: AlarmStore.migrationBackupKey)

        guard case .success(let alarms) = AlarmStore.loadResult(
            from: defaults
        ) else {
            return XCTFail("Interrupted first recovery should resume")
        }

        XCTAssertEqual(alarms.map(\.name), ["Recovered"])
        XCTAssertEqual(
            defaults.data(forKey: AlarmStore.corruptPrimaryBackupKey),
            corruptPrimary
        )
        let restoredPrimary = try XCTUnwrap(
            defaults.data(forKey: AlarmStore.savedAlarmsKey)
        )
        XCTAssertEqual(
            try JSONDecoder().decode([Alarm].self, from: restoredPrimary)
                .map(\.name),
            ["Recovered"]
        )
    }

    func testInterruptedRecoverySupportsEveryPropertyListContainerType() throws {
        let corruptedPrimaries: [Any] = [
            Date(timeIntervalSince1970: 1_700_000_000),
            [
                "broken",
                ["enabled": true, "count": 2] as [String: Any]
            ] as [Any],
            [
                "createdAt": Date(timeIntervalSince1970: 1_700_000_001),
                "values": [1, 2, 3]
            ] as [String: Any]
        ]
        let publishedBackup = Data(
            """
            [{"name":"Recovered property list","sound":"kind","isAlarmEnabled":true,"isSoundEnabled":true}]
            """.utf8
        )

        for (index, corruptPrimary) in corruptedPrimaries.enumerated() {
            let suiteName = "AlarmStorePropertyListRecoveryTests.\(index).\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set(corruptPrimary, forKey: AlarmStore.savedAlarmsKey)
            defaults.set(
                corruptPrimary,
                forKey: AlarmStore.corruptPrimaryBackupKey
            )
            defaults.set(
                "interrupted-recovery",
                forKey: AlarmStore.recoveryInProgressKey
            )
            defaults.set(publishedBackup, forKey: AlarmStore.migrationBackupKey)

            guard case .success(let alarms) = AlarmStore.loadResult(
                from: defaults
            ) else {
                XCTFail("Property-list type at index \(index) must resume recovery")
                continue
            }
            XCTAssertEqual(alarms.map(\.name), ["Recovered property list"])
            XCTAssertNil(
                defaults.object(forKey: AlarmStore.recoveryInProgressKey)
            )
        }
    }

    func testRecoverySnapshotDistinguishesBooleanFromNumericOne() throws {
        let suiteName = "AlarmStoreBooleanSnapshotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let publishedBackup = Data(
            """
            [{"name":"Must not recover","sound":"kind","isAlarmEnabled":true,"isSoundEnabled":true}]
            """.utf8
        )
        defaults.set(
            NSNumber(value: Int8(1)),
            forKey: AlarmStore.savedAlarmsKey
        )
        defaults.set(true, forKey: AlarmStore.corruptPrimaryBackupKey)
        defaults.set(
            "stale-recovery",
            forKey: AlarmStore.recoveryInProgressKey
        )
        defaults.set(publishedBackup, forKey: AlarmStore.migrationBackupKey)

        XCTAssertEqual(
            AlarmStore.loadResult(from: defaults),
            .failure(.unreadableData)
        )
        XCTAssertNil(defaults.object(forKey: AlarmStore.recoveryInProgressKey))
        XCTAssertNil(defaults.data(forKey: AlarmStore.savedAlarmsKey))
        XCTAssertEqual(
            defaults.object(forKey: AlarmStore.savedAlarmsKey) as? NSNumber,
            NSNumber(value: Int8(1))
        )
    }

    func testMigrationBackupWriteOncePreservesExistingNonDataValue() throws {
        let suiteName = "AlarmStoreBackupTypeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let publishedData = Data(
            """
            [{"name":"Published","sound":"kind","isAlarmEnabled":true,"isSoundEnabled":true}]
            """.utf8
        )
        defaults.set(publishedData, forKey: AlarmStore.savedAlarmsKey)
        defaults.set("reserved-backup-value", forKey: AlarmStore.migrationBackupKey)

        guard case .success(let alarms) = AlarmStore.loadResult(from: defaults) else {
            return XCTFail("Valid published data should still migrate")
        }

        XCTAssertEqual(alarms.map(\.name), ["Published"])
        XCTAssertEqual(
            defaults.string(forKey: AlarmStore.migrationBackupKey),
            "reserved-backup-value"
        )
    }

    func testAlarmMigrationLeavesPublishedPreferencesUntouched() throws {
        let suiteName = "AlarmStorePreferenceContractTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let publishedData = Data(
            """
            [{"name":"Home","sound":"kind","isAlarmEnabled":false,"isSoundEnabled":true}]
            """.utf8
        )
        defaults.set(publishedData, forKey: AlarmStore.savedAlarmsKey)
        defaults.set(500.0, forKey: "defaultRadius")
        defaults.set(false, forKey: "isSoundEnabled")
        defaults.set(true, forKey: "hasSeenOnboarding")

        _ = AlarmStore.loadResult(from: defaults)

        XCTAssertEqual(defaults.double(forKey: "defaultRadius"), 500)
        XCTAssertFalse(defaults.bool(forKey: "isSoundEnabled"))
        XCTAssertTrue(defaults.bool(forKey: "hasSeenOnboarding"))
    }

    func testAlarmStoreTreatsAnEntirelyInvalidNonemptyArrayAsUnreadable() throws {
        let suiteName = "AlarmStoreAllInvalidTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let invalid = Data(
            """
            [
              {"id":"broken-1","name":"Missing sound"},
              {"id":"broken-2","sound":"kind"}
            ]
            """.utf8
        )
        defaults.set(invalid, forKey: AlarmStore.savedAlarmsKey)

        XCTAssertEqual(
            AlarmStore.loadResult(from: defaults),
            .failure(.unreadableData)
        )
        XCTAssertEqual(
            defaults.data(forKey: AlarmStore.savedAlarmsKey),
            invalid
        )
        XCTAssertNil(defaults.data(forKey: AlarmStore.migrationBackupKey))
    }

    func testAlarmStoreMigrationBackupIsWrittenOnlyOnce() throws {
        let suiteName = "AlarmStoreBackupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstLegacyData = Data(
            """
            [{"id":"first","name":"First","sound":"kind","isAlarmEnabled":true,"isSoundEnabled":true}]
            """.utf8
        )
        let secondLegacyData = Data(
            """
            [{"id":"second","name":"Second","sound":"siren","isAlarmEnabled":true,"isSoundEnabled":false}]
            """.utf8
        )

        defaults.set(firstLegacyData, forKey: AlarmStore.savedAlarmsKey)
        _ = AlarmStore.load(from: defaults)
        XCTAssertEqual(
            defaults.data(forKey: AlarmStore.migrationBackupKey),
            firstLegacyData
        )

        defaults.set(secondLegacyData, forKey: AlarmStore.savedAlarmsKey)
        _ = AlarmStore.load(from: defaults)
        XCTAssertEqual(
            defaults.data(forKey: AlarmStore.migrationBackupKey),
            firstLegacyData
        )
    }

    func testUnreadableRestorePreservesTheLastUsableAlarmSnapshot() {
        let manager = LocationManager()
        let existing = Alarm(
            id: "existing",
            name: "Existing",
            sound: "kind",
            isAlarmEnabled: true,
            isSoundEnabled: true,
            isVibrationEnabled: false,
            location: Location(latitude: 34, longitude: 135),
            radius: 300
        )
        manager.alarms = [existing]

        let result = manager.restoreSavedAlarms(
            reason: "unit-test-corruption",
            loadResult: .failure(.unreadableData)
        )

        XCTAssertEqual(result, .failure(.unreadableData))
        XCTAssertEqual(manager.alarms, [existing])
    }

    func testLegacyEnabledAlarmWaitsWhenTheOnlyLocationPredatesMigration() throws {
        let legacyData = Data(
            """
            {
              "id":"published-alarm",
              "name":"Published",
              "sound":"kind",
              "isAlarmEnabled":true,
              "isSoundEnabled":true,
              "location":{"latitude":34.0,"longitude":135.0},
              "radius":300
            }
            """.utf8
        )
        let locationBeforeMigration = makeCLLocation(
            latitude: 34,
            longitude: 135,
            timestamp: Date().addingTimeInterval(-1)
        )

        let migrated = try JSONDecoder().decode(Alarm.self, from: legacyData)

        XCTAssertTrue(migrated.needsInitialStateCheck)
        XCTAssertFalse(
            migrated.canResolveInitialState(
                usingLocationTimestamp: locationBeforeMigration.timestamp
            )
        )
        XCTAssertEqual(
            AlarmTriggerPolicy.proximityAction(
                for: migrated,
                distance: 0,
                radius: 300,
                weekday: 1
            ),
            .none
        )
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

    func testContinuousLocationMonitoringUsesAvailableForegroundAuthorization() {
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
        XCTAssertTrue(LocationManager.shouldRunContinuousLocationMonitoring(
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
        XCTAssertTrue(LocationManager.shouldRunContinuousLocationMonitoring(
            for: .authorizedWhenInUse,
            alarms: [geofenceAlarm],
            maximumGeofenceRadius: 1_000
        ))
    }

    func testMonitoringRetryIsBoundedAndCapacityDoesNotDoubleCountPendingRegions() {
        XCTAssertTrue(
            LocationManager.shouldRetryMonitoring(afterFailureCount: 0)
        )
        XCTAssertTrue(
            LocationManager.shouldRetryMonitoring(
                afterFailureCount: LocationManager.maximumMonitoringRetryAttempts
            )
        )
        XCTAssertFalse(
            LocationManager.shouldRetryMonitoring(
                afterFailureCount: LocationManager.maximumMonitoringRetryAttempts + 1
            )
        )

        let current = Set((0..<19).map { "region-\($0)" })
        let pending = Set(["region-18", "region-19"])
        XCTAssertEqual(
            LocationManager.remainingGeofenceCapacity(
                currentRegionIDs: current,
                pendingRegionIDs: pending
            ),
            0
        )
        XCTAssertEqual(
            LocationManager.remainingGeofenceCapacity(
                currentRegionIDs: Set(["same"]),
                pendingRegionIDs: Set(["same"])
            ),
            LocationManager.maximumMonitoredGeofences - 1
        )
    }

    func testMonitoringAttemptsWaitForAuthorizationAndResetWhenPermissionImproves() {
        XCTAssertFalse(
            LocationManager.canAttemptLocationMonitoring(for: .notDetermined)
        )
        XCTAssertFalse(
            LocationManager.canAttemptLocationMonitoring(for: .denied)
        )
        XCTAssertTrue(
            LocationManager.canAttemptLocationMonitoring(
                for: .authorizedWhenInUse
            )
        )
        XCTAssertTrue(
            LocationManager.shouldResetMonitoringAttempts(
                previousStatus: .denied,
                currentStatus: .authorizedAlways
            )
        )
        XCTAssertTrue(
            LocationManager.shouldResetMonitoringAttempts(
                previousStatus: .authorizedWhenInUse,
                currentStatus: .authorizedAlways
            )
        )
        XCTAssertFalse(
            LocationManager.shouldResetMonitoringAttempts(
                previousStatus: .authorizedAlways,
                currentStatus: .authorizedAlways
            )
        )
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
                PermissionReadinessIssue.notificationAuthorization.rawValue
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

private final class LocationManagerDelegateSpy: LocationManagerDelegate {
    private(set) var updatedAlarms: [Alarm] = []

    func didUpdateAlarmStatus(_ alarm: Alarm) {
        updatedAlarms.append(alarm)
    }
}
