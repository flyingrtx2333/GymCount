import XCTest

// The runner installs the actual synced 127-record snapshot in isolated storage.
final class RecordPerformanceTests: XCTestCase {
    @MainActor private func launch(tab: Int, storage: String = "sync-repair-real127") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--isolated-ui-test", "--ui-test-storage-id=" + storage,
            "--reset-record-view-preferences", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-records.appearance", "dark"]
        app.launch()
        XCTAssertTrue(app.recordTab(tab).waitForExistence(timeout: 15))
        app.recordTab(tab).tap()
        return app
    }

    @MainActor private func scroll(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.74))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.28))
        for _ in 0..<3 { start.press(forDuration: 0.02, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0.05) }
        for _ in 0..<3 { end.press(forDuration: 0.02, thenDragTo: start, withVelocity: .fast, thenHoldForDuration: 0.05) }
    }

    @MainActor private func measureScroll(_ app: XCUIApplication) {
        let options = XCTMeasureOptions(); options.iterationCount = 3
        var metrics: [any XCTMetric] = [XCTClockMetric(), XCTCPUMetric(application: app)]
        if #available(iOS 26, *) { metrics.append(XCTHitchMetric(application: app)) }
        measure(metrics: metrics, options: options) { scroll(app) }
    }

    @MainActor func testRecordsScrolling() {
        let app = launch(tab: 1)
        XCTAssertTrue(app.buttons["history-record"].firstMatch.waitForExistence(timeout: 8))
        measureScroll(app)
    }

    @MainActor func testTrendsScrolling() {
        let app = launch(tab: 3)
        XCTAssertTrue(app.descendants(matching: .any)["trend-chart"].firstMatch.waitForExistence(timeout: 8))
        measureScroll(app)
    }

    @MainActor func testChartPanning() {
        let app = launch(tab: 3)
        let menu = app.buttons["trend-metric"]
        XCTAssertTrue(menu.waitForExistence(timeout: 8))
        menu.tap(); app.buttons["trend-granularity-day"].tap()
        let chart = app.descendants(matching: .any)["trend-chart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 8))
        let left = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        let right = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        let options = XCTMeasureOptions(); options.iterationCount = 3
        measure(metrics: [XCTCPUMetric(application: app)], options: options) {
            for _ in 0..<2 {
                left.press(forDuration: 0.02, thenDragTo: right, withVelocity: .slow, thenHoldForDuration: 0.05)
                right.press(forDuration: 0.02, thenDragTo: left, withVelocity: .slow, thenHoldForDuration: 0.05)
            }
        }
    }

    @MainActor func testFilteredEditDeleteAndRestart() {
        let storage = "performance-functional-real127"
        var app = launch(tab: 1, storage: storage)
        func selectBench(_ app: XCUIApplication) {
            app.buttons["record-exercise-filter"].tap(); app.buttons["卧推"].firstMatch.tap()
        }
        func rowCount(_ app: XCUIApplication) -> Int {
            let text = app.staticTexts["record-summary"].label
            return Int(text.prefix(while: { $0.isNumber }))!
        }
        selectBench(app)
        let count = rowCount(app)
        app.buttons["history-record"].firstMatch.tap()
        let total = app.descendants(matching: .any)["record-total-reps"].firstMatch
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        let reps = total.value as! String
        app.buttons["edit-record"].tap()
        let field = app.descendants(matching: .any)["record-note-field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Performance check")
        app.buttons["save-record"].tap()
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertEqual(total.value as! String, reps)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["history-record"].firstMatch.label.contains("有备注"))
        app.buttons.matching(identifier: "history-record").element(boundBy: 1).swipeLeft()
        app.buttons["删除"].firstMatch.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["删除"].tap()
        XCTAssertEqual(rowCount(app), count - 1)
        app.terminate()
        app = launch(tab: 1, storage: storage)
        selectBench(app)
        XCTAssertEqual(rowCount(app), count - 1)
        XCTAssertTrue(app.buttons["history-record"].firstMatch.label.contains("有备注"))
        app.buttons["history-record"].firstMatch.tap()
        let restored = app.descendants(matching: .any)["record-total-reps"].firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 5))
        XCTAssertEqual(restored.value as! String, reps)
    }
}
