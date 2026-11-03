import XCTest

final class TrainingReminderTests: XCTestCase {
    @MainActor private func launch(english: Bool, large: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--isolated-ui-test", "--ui-test-storage-id=insights-real82",
            "--inspect-training-reminders", "--reset-record-view-preferences",
            "-AppleLanguages", english ? "(en)" : "(zh-Hans)", "-AppleLocale", english ? "en_US" : "zh_CN",
            "-records.appearance", english ? "dark" : "light"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.recordTab(2).waitForExistence(timeout: 12))
        return app
    }

    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.4)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-AX"; tree.lifetime = .keepAlways; add(tree)
    }

    @MainActor private func waitReady(_ item: XCUIElement) {
        let ready = expectation(for: NSPredicate { _, _ in item.exists && item.isEnabled && item.isHittable }, evaluatedWith: item)
        wait(for: [ready], timeout: 15)
    }

    @MainActor func testChineseStreakAndReminder() {
        let app = launch(english: false)
        let streak = app.descendants(matching: .any).matching(identifier: "records-streak").firstMatch
        XCTAssertTrue(streak.waitForExistence(timeout: 8)); XCTAssertNotNil(streak.label.range(of: "[0-9]+", options: .regularExpression))
        shot(app, "records-streak-zh")
        app.recordTab(2).tap()
        let toggle = app.switches["training-reminder-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5)); waitReady(toggle)
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.switches.firstMatch.tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = system.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "允许"])).firstMatch
        if allow.waitForExistence(timeout: 4) { allow.tap() }
        waitReady(toggle)
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "training-reminder-status").firstMatch.exists)
        shot(app, "reminder-enabled-zh")
        toggle.switches.firstMatch.tap(); waitReady(toggle)
        XCTAssertEqual(toggle.value as? String, "0")
        shot(app, "reminder-disabled-zh")
    }

    @MainActor func testEnglishLargeType() {
        let app = launch(english: true, large: true)
        let streak = app.descendants(matching: .any).matching(identifier: "records-streak").firstMatch
        XCTAssertTrue(streak.waitForExistence(timeout: 8))
        shot(app, "records-streak-en-large")
        XCTAssertLessThanOrEqual(streak.frame.maxX, app.frame.maxX - 12)
        app.recordTab(2).tap()
        let toggle = app.switches["training-reminder-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5)); waitReady(toggle)
        XCTAssertTrue(toggle.isHittable)
        shot(app, "reminder-en-large")
        XCTAssertLessThanOrEqual(toggle.switches.firstMatch.frame.maxX, app.frame.maxX - 12)
    }
}
