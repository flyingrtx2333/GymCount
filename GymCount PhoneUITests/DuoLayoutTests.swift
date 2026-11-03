import XCTest

final class DuoLayoutTests: XCTestCase {
    @MainActor func testRecordsAndTrends() {
        let app = XCUIApplication()
        app.launchArguments = ["--isolated-ui-test", "--ui-test-storage-id=duo-real-v1", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-records.appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["add-record"].waitForExistence(timeout: 15))
        let rows = app.buttons.matching(identifier: "history-record")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "Requires real history in isolated storage")
        guard let row = rows.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
            return XCTFail("No visible training record")
        }
        capture(app, "records")
        row.tap()
        XCTAssertTrue(app.buttons["edit-record"].waitForExistence(timeout: 5))
        capture(app, "detail")
        app.buttons["edit-record"].tap()
        XCTAssertTrue(app.buttons["save-record"].waitForExistence(timeout: 5))
        capture(app, "editor")
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["edit-record"].waitForExistence(timeout: 5))
        let back = app.buttons["BackButton"].firstMatch
        if back.exists {
            back.tap()
            XCTAssertTrue(app.buttons["record-select"].waitForExistence(timeout: 5))
        }
        app.recordTab(3).tap()
        XCTAssertTrue(app.buttons["trend-metric"].waitForExistence(timeout: 5))
        app.buttons["trend-metric"].tap()
        app.buttons["trend-metric-reps"].tap()
        capture(app, "trends")
        let breakdown = app.buttons["trend-breakdown-disclosure"]
        let trends = app.scrollViews["trends-scroll"]
        for _ in 0..<3 where !breakdown.isHittable { trends.swipeUp() }
        XCTAssertTrue(breakdown.isHittable, "Trend page must scroll to its last section")
        capture(app, "trends-bottom")
        app.recordTab(2).tap()
        XCTAssertTrue(app.buttons["records-backup"].waitForExistence(timeout: 5))
        capture(app, "settings")
    }
    @MainActor func testEnglishDarkLargeText() {
        let app = XCUIApplication()
        app.launchArguments = ["--isolated-ui-test", "--ui-test-storage-id=duo-real-v1", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-records.appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["add-record"].waitForExistence(timeout: 15))
        capture(app, "english-records")
        app.recordTab(3).tap()
        XCTAssertTrue(app.buttons["trend-metric"].waitForExistence(timeout: 5))
        capture(app, "english-trends")
        app.recordTab(2).tap()
        XCTAssertTrue(app.buttons["records-backup"].waitForExistence(timeout: 5))
        capture(app, "english-settings")
    }
    @MainActor func testResizeKeepsUnsavedInput() {
        let app = XCUIApplication()
        app.launchArguments = ["--isolated-ui-test", "--ui-test-storage-id=duo-resize-" + UUID().uuidString, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-records.appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["add-record"].waitForExistence(timeout: 15))
        app.buttons["add-record"].tap()
        let note = app.textFields["record-note-field"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap(); note.typeText("Duo layout")
        let width = app.windows.firstMatch.frame.width
        print("DUO_READY_FOR_POSE_CHANGE")
        let resized = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(app.windows.firstMatch.frame.width - width) > 100
        }, object: app)
        // Change the real Duo pose in Device Hub while the native editor remains open.
        XCTAssertEqual(XCTWaiter.wait(for: [resized], timeout: 60), .completed)
        XCTAssertEqual(note.value as? String, "Duo layout")
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            note.isHittable && note.frame.maxY <= app.keyboards.firstMatch.frame.minY
        }, object: note)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed)
        capture(app, "resized-unsaved-editor")
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["放弃修改"].waitForExistence(timeout: 5))
        app.buttons["放弃修改"].tap()
        XCTAssertTrue(app.buttons["add-record"].waitForExistence(timeout: 5))
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "duo-" + name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "duo-" + name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
}

// Native tab buttons move to a vertical rail on Duo; identify them independently of placement.
extension XCUIApplication {
    @MainActor func recordTab(_ index: Int) -> XCUIElement {
        let labels = [1: ["记录", "Records"], 2: ["设置", "Settings"], 3: ["趋势", "Trends"]]
        return buttons.matching(NSPredicate(format: "label IN %@", labels[index]!)).firstMatch
    }
}
