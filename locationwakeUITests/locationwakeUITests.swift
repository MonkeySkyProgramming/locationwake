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
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testAlarmListLaunches() throws {
        app.launch()

        XCTAssertTrue(app.buttons["追加"].waitForExistence(timeout: 10))
    }
}
