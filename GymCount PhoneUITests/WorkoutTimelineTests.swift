import XCTest

// Seeded outside the app from an existing private capture export. No generated
// motion or time-distributed repetitions are used by these native checks.
final class WorkoutTimelinePhoneTests: XCTestCase {
    @MainActor private func launch(english: Bool = false, dark: Bool = false, large: Bool = false, storage: String = "timeline-real-bench") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--isolated-ui-test", "--ui-test-storage-id=" + storage, "--reset-record-view-preferences",
                               "-AppleLanguages", english ? "(en)" : "(zh-Hans)", "-AppleLocale", english ? "en_US" : "zh_CN",
                               "-records.appearance", dark ? "dark" : "light"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-UIAccessibilityReduceMotionEnabled", "YES"] }
        app.launch()
        let record = app.buttons["history-record"].firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 15), "Seed the isolated store with the real capture before running")
        record.tap()
        XCTAssertTrue(app.buttons["record-more-actions"].waitForExistence(timeout: 5))
        return app
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<14 {
            let top = app.navigationBars.firstMatch.frame.maxY + 8
            let bottom = app.recordTab(1).frame.minY - 8
            let center = (top + bottom) / 2
            var distance: CGFloat = 120
            if element.exists {
                let frame = element.frame
                if element.isHittable, frame.minY >= top, frame.maxY <= bottom { return }
                distance = min(150, max(-150, frame.midY - center))
            }
            // Short drags in the List margin avoid both Charts selection and
            // overshooting a compact-screen control at accessibility text sizes.
            let height = app.frame.height
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: center / height))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: (center - distance) / height))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        let screen = XCTAttachment(screenshot: app.screenshot()); screen.name = name; screen.lifetime = .keepAlways; add(screen)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-AX"; tree.lifetime = .keepAlways; add(tree)
    }
    @MainActor func testRealTimelineInteraction() {
        let app = launch()
        let chart = app.descendants(matching: .any)["workout-sensor-chart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        shot(app, "timeline-real-bench-light")
        let second = app.buttons["timeline-rep-2"]
        reveal(second, in: app); second.tap()
        XCTAssertTrue(app.buttons["timeline-clear-selection"].exists)
        XCTAssertTrue(second.isSelected)
        shot(app, "timeline-real-selected-rep")
        let channel = app.descendants(matching: .any)["timeline-channel"].firstMatch
        for _ in 0..<5 { if channel.isHittable { break }; app.swipeDown() }
        channel.tap(); app.buttons["timeline-channel-rotation"].tap()
        XCTAssertTrue(channel.value as? String == "旋转速率" || channel.label.contains("旋转速率"))
        shot(app, "timeline-real-rotation")
        let window = app.buttons["timeline-window"]
        reveal(window, in: app); window.tap(); app.buttons["timeline-window-15"].tap()
        XCTAssertTrue(app.buttons["timeline-next-window"].waitForExistence(timeout: 5))
        app.buttons["timeline-next-window"].tap()
        shot(app, "timeline-real-zoom")
        let source = app.buttons["timeline-event-source"]
        reveal(source, in: app); source.tap(); app.buttons["人工标注"].tap()
        XCTAssertTrue(app.buttons["timeline-rep-5"].exists)
        shot(app, "timeline-real-reference-events")
    }
    @MainActor func testDarkAndLargeEnglish() {
        var app = launch(dark: true)
        XCTAssertTrue(app.descendants(matching: .any)["workout-sensor-chart"].firstMatch.waitForExistence(timeout: 5))
        shot(app, "timeline-real-dark")
        app.terminate()
        app = launch(english: true, large: true)
        let channel = app.descendants(matching: .any)["timeline-channel"].firstMatch
        reveal(channel, in: app)
        XCTAssertTrue(channel.isHittable)
        shot(app, "timeline-real-accessibility-english")
        channel.tap(); app.buttons["timeline-channel-attitude"].tap()
        let chart = app.descendants(matching: .any)["workout-sensor-chart"].firstMatch
        reveal(chart, in: app)
        shot(app, "timeline-real-accessibility-chart")
        let rep = app.buttons["timeline-rep-2"]
        reveal(rep, in: app); rep.tap()
        XCTAssertTrue(app.buttons["record-more-actions"].exists, "The selection must remain in workout details")
        XCTAssertTrue(rep.isSelected)
        shot(app, "timeline-real-accessibility-selected")
    }
    @MainActor func testSmallEnglishAndSummaryOnly() {
        var app = launch(english: true)
        XCTAssertTrue(app.descendants(matching: .any)["workout-sensor-chart"].firstMatch.waitForExistence(timeout: 5))
        shot(app, "timeline-real-small-english")
        let chart = app.descendants(matching: .any)["workout-sensor-chart"].firstMatch
        let begin = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        let end = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5))
        begin.press(forDuration: 0.2, thenDragTo: end)
        shot(app, "timeline-real-small-after-drag")
        let clear = app.buttons["timeline-clear-selection"]
        // The chart footer starts below the compact screen's visible list area.
        // Bring the resulting selection into view before checking its control.
        if !clear.exists { app.swipeUp() }
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        let selected = chart.value as? String ?? ""
        XCTAssertTrue(selected.contains(":"))
        XCTAssertFalse(selected.contains(" – "), "The inspected time must remain selected after touch-up")
        let readings = app.descendants(matching: .any).matching(identifier: "timeline-axis-values").allElementsBoundByIndex
            .filter { ["X", "Y", "Z"].contains($0.label) }
        XCTAssertEqual(readings.count, 3)
        for reading in readings {
            XCTAssertNotNil((reading.value as? String)?.range(of: "[0-9]", options: .regularExpression), "A real nearby sample must be inspected")
        }
        shot(app, "timeline-real-small-scrub")
        reveal(clear, in: app)
        clear.tap()
        XCTAssertTrue(app.buttons["record-more-actions"].exists)
        XCTAssertFalse(clear.exists)
        app.terminate()
        app = launch(english: true, storage: "timeline-summary-only")
        XCTAssertFalse(app.descendants(matching: .any)["workout-sensor-chart"].firstMatch.exists)
        XCTAssertFalse(app.buttons["timeline-rep-1"].exists)
        shot(app, "timeline-summary-missing-state")
        XCTAssertTrue(app.buttons["timeline-sync"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["timeline-missing-status"].label.contains("Samples not received"))
        app.buttons["timeline-sync"].tap()
        shot(app, "timeline-summary-without-invented-data")
    }
    @MainActor func testTimelineFocusedPreview() {
        let app = launch()
        let channel = app.descendants(matching: .any)["timeline-channel"].firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 5))
        let desired = app.navigationBars.firstMatch.frame.maxY + 16
        let distance = max(0, channel.frame.minY - desired)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: 12, dy: app.frame.height * 0.78))
        let end = origin.withOffset(CGVector(dx: 12, dy: app.frame.height * 0.78 - distance))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        let fifth = app.buttons["timeline-rep-5"]
        XCTAssertTrue(fifth.isHittable)
        XCTAssertTrue(app.buttons["record-more-actions"].exists)
        Thread.sleep(forTimeInterval: 0.4)
        shot(app, "timeline-real-focused-light")
    }
    @MainActor func testActionTimeDoesNotUseElapsedFallback() {
        let app = launch(storage: "timeline-summary-only")
        XCTAssertTrue(app.staticTexts["训练总用时"].exists)
        XCTAssertFalse(app.staticTexts["动作时长（估计）"].exists)
        shot(app, "duration-summary-retains-total-only")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["history-record"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["record-action-duration"].exists)
        shot(app, "duration-list-omits-unmeasured-action-time")
        app.recordTab(3).tap()
        let metric = app.buttons["trend-metric"]
        for _ in 0..<5 { if metric.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(metric.label.contains("动作时长"))
        shot(app, "duration-default-active-trend")
    }
}
