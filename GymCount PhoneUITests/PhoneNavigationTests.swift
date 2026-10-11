import XCTest

final class PhoneNavigationTests: XCTestCase {
    @MainActor
    func testWatchHealthGuideNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["--isolated-ui-test"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-2"].waitForExistence(timeout: 10))
        app.buttons["tab-2"].tap()
        app.buttons["手表健康权限"].tap()
        XCTAssertTrue(app.navigationBars["手表健康权限"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["在手表本机操作"].exists)
        XCTAssertTrue(app.staticTexts["设置 → 健康 → 数据来源、App 和服务 → 健身计数器"].exists)
        XCTAssertTrue(app.staticTexts["开启「允许写入」中的「体能训练」。"].exists)
        snapshot(app, "watch-health-permission-guide")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["设置"].exists)
    }

    @MainActor
    func testCaptureStartTimeoutCancellationAndLateReply() {
        let app = XCUIApplication()
        app.launchArguments = ["--isolated-ui-test", "--capture-start-timeout-test"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-2"].waitForExistence(timeout: 10))
        app.buttons["tab-2"].tap()
        app.buttons["开发者工具"].tap()
        app.buttons["同步录像与采样"].tap()
        let start = app.buttons["开始采集"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(app.staticTexts["正在连接手表…"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["连接超时，请打开手表采集页后重试"].waitForExistence(timeout: 10))
        XCTAssertTrue(start.isEnabled)
        snapshot(app, "capture-start-timeout")

        start.tap()
        let cancel = app.buttons["取消启动"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 2))
        cancel.tap()
        XCTAssertTrue(app.staticTexts["已取消，可重新开始"].waitForExistence(timeout: 3))
        XCTAssertTrue(start.isEnabled)
        // Late replies from both attempts must not change state or start the camera.
        let staleReply = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["已取消，可重新开始"])
        staleReply.isInverted = true
        wait(for: [staleReply], timeout: 9)
        XCTAssertFalse(app.buttons["结束采集"].exists)
        XCTAssertFalse(app.buttons["取消启动"].exists)
        snapshot(app, "capture-start-cancelled")
    }

    @MainActor
    func testTrainingHomeAndDeveloperNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["--isolated-ui-test"]
        app.launch()
        XCTAssertTrue(app.buttons["开始训练"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["开始训练"].exists)
        XCTAssertFalse(app.tabBars.buttons["同步采集"].exists)
        XCTAssertFalse(app.buttons["开发者工具"].exists)
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists)
        app.buttons["深蹲"].tap()
        snapshot(app, "training-home")

        app.buttons["tab-2"].tap()
        XCTAssertTrue(app.navigationBars["设置"].exists)
        snapshot(app, "settings")
        app.buttons["开发者工具"].tap()
        XCTAssertTrue(app.navigationBars["开发者工具"].exists)
        XCTAssertTrue(app.buttons["同步录像与采样"].exists)
        XCTAssertTrue(app.buttons["采集记录与标注"].exists)
        snapshot(app, "developer-tools")

        app.buttons["采集记录与标注"].tap()
        XCTAssertTrue(app.navigationBars["采集记录"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["同步录像与采样"].tap()
        XCTAssertTrue(app.navigationBars["同步采集"].waitForExistence(timeout: 5))
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["允许"]
        if allow.waitForExistence(timeout: 2) { allow.tap() }
        snapshot(app, "developer-capture")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["开发者工具"].waitForExistence(timeout: 5))
        app.buttons["tab-0"].tap()
        XCTAssertTrue(app.buttons["开始训练"].exists)
        XCTAssertFalse(app.buttons["开始采集"].exists)

        app.buttons["开始训练"].tap()
        XCTAssertTrue(app.buttons["增加一次"].waitForExistence(timeout: 5))
        app.buttons["增加一次"].tap()
        XCTAssertTrue(app.staticTexts["已完成 1 次"].exists)
        snapshot(app, "active-training")
        app.buttons["结束并保存"].tap()
        let confirm = app.buttons.matching(identifier: "结束并保存").allElementsBoundByIndex.first(where: { $0.isHittable })
        XCTAssertNotNil(confirm)
        confirm?.tap()
        app.buttons["tab-1"].tap()
        XCTAssertTrue(app.navigationBars["训练记录"].exists)
        XCTAssertTrue(app.staticTexts["1 次"].exists)
        snapshot(app, "saved-history")
    }

    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
