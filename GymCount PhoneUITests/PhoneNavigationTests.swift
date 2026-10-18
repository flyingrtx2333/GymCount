import XCTest

final class PhoneNavigationTests: XCTestCase {
    @MainActor
    func testWholeTrainingSetsRestRestoreAndReuse() {
        let app = XCUIApplication()
        app.launchArguments = ["--isolated-ui-test", "--ui-test-storage-id=" + UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.buttons["tab-2"].waitForExistence(timeout: 15))
        app.buttons["tab-2"].tap()
        let duration = app.steppers["rest-duration"]
        XCTAssertTrue(duration.waitForExistence(timeout: 5))
        for _ in 0..<5 { duration.buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(app.staticTexts["休息时长：15 秒"].exists)
        app.buttons["tab-0"].tap()
        app.buttons["开始训练"].tap()
        enterSet(app, weight: "60", reps: "10")
        snapshot(app, "training-quick-entry")
        tapVisible(app, "complete-set")
        XCTAssertTrue(app.otherElements["rest-card"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["已保存 1 组 · 10 次"].exists)
        snapshot(app, "training-rest-countdown")

        // Relaunch the actual app with the same isolated storage: timer and sets survive.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["已保存 1 组 · 10 次"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["休息结束，准备下一组"].waitForExistence(timeout: 22))
        enterSet(app, weight: "62.5", reps: "8")
        tapVisible(app, "complete-set")
        tapVisible(app, "撤回上一组")
        XCTAssertTrue(app.staticTexts["已完成 8 次"].exists)
        tapVisible(app, "complete-set")
        tapVisible(app, "active-exercise-squat")
        enterSet(app, weight: "80", reps: "5")
        tapVisible(app, "active-exercise-deadlift")
        XCTAssertTrue(app.buttons["继续本组"].waitForExistence(timeout: 5))
        app.buttons["继续本组"].tap()
        XCTAssertTrue(app.staticTexts["已完成 5 次"].exists)
        tapVisible(app, "complete-set")
        tapVisible(app, "跳过休息")
        XCTAssertFalse(app.otherElements["rest-card"].exists)
        tapVisible(app, "finish-training")
        app.buttons["confirm-finish"].tap()
        XCTAssertTrue(app.staticTexts["23 次"].waitForExistence(timeout: 5))
        app.buttons["tab-1"].tap()
        app.cells.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["训练详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["\(Double(1500).formatted(.number.precision(.fractionLength(0...1)))) 公斤"].exists)
        snapshot(app, "training-multiple-exercise-summary")
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons["tab-0"].tap()
        tapVisible(app, "沿用上次开始")
        XCTAssertTrue(app.staticTexts["已完成 10 次"].waitForExistence(timeout: 5))
        snapshot(app, "training-reuse-last-session")
        tapVisible(app, "complete-set")
        enterSet(app, weight: "65", reps: "6")
        tapVisible(app, "reuse-last-set")
        XCTAssertTrue(app.alerts["替换当前组？"].waitForExistence(timeout: 5))
        app.alerts.buttons["保留本组"].tap()
        XCTAssertTrue(app.staticTexts["已完成 6 次"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["已完成 6 次"].waitForExistence(timeout: 15))
        tapVisible(app, "reuse-last-set")
        app.alerts.buttons["替换本组"].tap()
        XCTAssertTrue(app.staticTexts["已完成 8 次"].exists)
        tapVisible(app, "finish-training")
        app.buttons["confirm-finish"].tap()
        XCTAssertTrue(app.staticTexts["18 次"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab-1"].waitForExistence(timeout: 15))
        app.buttons["tab-1"].tap()
        XCTAssertTrue(app.staticTexts["18 次"].exists)
        XCTAssertTrue(app.staticTexts["23 次"].exists)
        snapshot(app, "training-history-after-relaunch")
    }

    @MainActor
    private func enterSet(_ app: XCUIApplication, weight: String, reps: String) {
        tapVisible(app, "直接填次数")
        let weightInput = app.textFields["set-weight-input"]
        XCTAssertTrue(weightInput.waitForExistence(timeout: 5))
        replaceText(weightInput, with: weight)
        replaceText(app.textFields["set-reps-input"], with: reps)
        app.buttons["confirm-set-input"].tap()
    }

    @MainActor
    private func replaceText(_ field: XCUIElement, with text: String) {
        field.tap()
        let current = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
    }

    @MainActor
    private func tapVisible(_ app: XCUIApplication, _ identifier: String) {
        let button = app.buttons[identifier]
        for _ in 0..<6 {
            if button.exists && button.isHittable { button.tap(); return }
            if button.exists && button.frame.midY < app.frame.midY { app.swipeDown() }
            else { app.swipeUp() }
        }
        XCTFail("Cannot reach button: " + identifier)
    }

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
        tapVisible(app, "finish-training")
        app.buttons["confirm-finish"].tap()
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
