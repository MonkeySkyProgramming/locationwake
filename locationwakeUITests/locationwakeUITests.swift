//
//  locationwakeUITests.swift
//  locationwakeUITests
//
//  Created by 井上晴斗 on 2024/09/03.
//

import XCTest

final class locationwakeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launchArguments.append("--ui-test-reset-data")
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testAlarmListLaunchesAndOpensLocationSearch() throws {
        app.launch()

        XCTAssertTrue(app.navigationBars["アラーム"].waitForExistence(timeout: 10))

        let addDestinationButton = app.buttons["目的地を追加"].firstMatch
        XCTAssertTrue(addDestinationButton.waitForExistence(timeout: 10))
        XCTAssertTrue(addDestinationButton.isEnabled)
        XCTAssertTrue(addDestinationButton.isHittable)

        addDestinationButton.tap()

        XCTAssertTrue(app.navigationBars["目的地を検索"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.descendants(matching: .any)["locationSelection.screen"]
                .waitForExistence(timeout: 10)
        )
    }

    func testFirstOnboardingScreenHasOnlyThePreparationAction() throws {
        app.launchArguments.append("--show-onboarding")
        app.launch()

        let prepareButton = app.buttons.matching(
            identifier: "onboarding.prepare"
        ).firstMatch
        XCTAssertTrue(prepareButton.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["あとで"].exists)
        XCTAssertFalse(app.buttons["まず使ってみる"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)

        prepareButton.tap()

        XCTAssertTrue(
            app.buttons.matching(
                identifier: "onboarding.location.request"
            ).firstMatch.waitForExistence(timeout: 10)
        )
    }

    func testActiveAlarmRequiresTheExplicitStopButton() throws {
        app.launchEnvironment["SIMULATE_ACTIVE_ALARM"] = "1"
        app.launch()

        let stopButton = app.buttons.matching(
            identifier: "alarm.stop"
        ).firstMatch
        XCTAssertTrue(stopButton.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["テスト目的地に到着しました"].exists)
        XCTAssertFalse(app.navigationBars["アラーム"].exists)

        stopButton.tap()

        XCTAssertTrue(stopButton.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["アラーム"].exists)
    }

    func testDirtyEditorAsksBeforeDiscardingChanges() throws {
        app.launchArguments.append("--ui-test-seed-alarm")
        app.launch()

        let savedAlarm = app.buttons.matching(
            identifier: "home.alarm.ui-test-saved-alarm"
        ).firstMatch
        XCTAssertTrue(savedAlarm.waitForExistence(timeout: 10))
        savedAlarm.tap()

        XCTAssertTrue(app.navigationBars["アラームを編集"].waitForExistence(timeout: 10))
        let nameField = app.textFields["alarmEditor.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        nameField.typeText(" 変更")

        app.buttons["キャンセル"].tap()
        XCTAssertTrue(app.staticTexts["変更を破棄しますか？"].waitForExistence(timeout: 10))
        app.buttons["編集を続ける"].tap()
        XCTAssertTrue(app.navigationBars["アラームを編集"].exists)

        app.buttons["キャンセル"].tap()
        XCTAssertTrue(app.buttons["変更を破棄"].waitForExistence(timeout: 10))
        app.buttons["変更を破棄"].tap()

        XCTAssertTrue(app.navigationBars["アラーム"].waitForExistence(timeout: 10))
        let restoredAlarm = app.buttons.matching(
            identifier: "home.alarm.ui-test-saved-alarm"
        ).firstMatch
        XCTAssertTrue(restoredAlarm.exists)
        XCTAssertEqual(restoredAlarm.label, "テスト駅")
    }
}
