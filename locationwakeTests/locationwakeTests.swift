import XCTest
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
}
