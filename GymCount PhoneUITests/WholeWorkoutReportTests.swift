import XCTest

// The runner installs one existing squat capture's measured cycles outside the
// app. These tests neither synthesize motion nor create a new workout record.
final class WholeWorkoutReportPhoneTests: XCTestCase {
    @MainActor
    private func launch(english: Bool = false, dark: Bool = false, large: Bool = false, storage: String = "whole-report-real") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--isolated-ui-test", "--ui-test-storage-id=" + storage, "--reset-record-view-preferences",
                               "-AppleLanguages", english ? "(en)" : "(zh-Hans)", "-AppleLocale", english ? "en_US" : "zh_CN",
                               "-records.appearance", dark ? "dark" : "light"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-UIAccessibilityReduceMotionEnabled", "YES"] }
        app.launch()
        let row = app.buttons["history-record"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Install the actual motion-derived report into the isolated store first")
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["whole-workout-report"].firstMatch.waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<16 {
            let top = app.navigationBars.firstMatch.frame.maxY + 8
            let bottom = app.recordTab(1).frame.minY - 8
            let center = (top + bottom) / 2
            var distance: CGFloat = 120
            if element.exists {
                let frame = element.frame
                if element.isHittable, frame.minY >= top, frame.maxY <= bottom { return }
                distance = min(150, max(-150, frame.midY - center))
            }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: center / app.frame.height))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: (center - distance) / app.frame.height))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func saveEvidence(_ app: XCUIApplication, _ name: String) {
        let screen = XCTAttachment(screenshot: app.screenshot()); screen.name = name; screen.lifetime = .keepAlways; add(screen)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-AX"; tree.lifetime = .keepAlways; add(tree)
    }

    @MainActor
    func testRealReportGroupingAndPersistence() {
        let app = launch()
        let initialReps = app.descendants(matching: .any)["record-total-reps"].firstMatch.value as? String
        XCTAssertNotNil(initialReps)
        XCTAssertFalse(app.descendants(matching: .any)["report-active-energy"].exists, "No HealthKit energy exists in this actual capture")
        XCTAssertFalse(app.descendants(matching: .any)["report-heart-rate"].exists)
        XCTAssertFalse(app.buttons["timeline-sync"].exists)
        saveEvidence(app, "whole-report-real-squat-light")

        let firstMenu = app.buttons["report-set-menu-1"]
        reveal(firstMenu, in: app); firstMenu.tap()
        app.buttons["report-split-set"].tap()
        XCTAssertTrue(app.buttons["report-split-save"].waitForExistence(timeout: 5))
        saveEvidence(app, "whole-report-split-real-cycle")
        app.buttons["report-split-save"].tap()
        let secondSet = app.buttons["report-set-2"]
        reveal(secondSet, in: app)
        XCTAssertTrue(secondSet.isHittable)
        let setChart = app.descendants(matching: .any)["report-set-timeline"].firstMatch
        reveal(setChart, in: app)
        XCTAssertTrue((setChart.value as? String ?? "").contains("第 2 组"))
        saveEvidence(app, "group-regions-single-rep-boundary-light")
        let sensors = app.descendants(matching: .any)["workout-sensor-chart"].firstMatch
        reveal(sensors, in: app)
        XCTAssertTrue((sensors.value as? String ?? "").contains("第 2 组"))
        saveEvidence(app, "group-regions-sensors-split-light")
        reveal(secondSet, in: app)
        secondSet.tap()
        saveEvidence(app, "whole-report-split-selected")
        let secondMenu = app.buttons["report-set-menu-2"]
        reveal(secondMenu, in: app); secondMenu.tap()
        app.buttons["report-merge-previous"].tap()
        XCTAssertFalse(app.buttons["report-set-2"].exists)
        reveal(sensors, in: app)
        XCTAssertFalse((sensors.value as? String ?? "").contains("第 2 组"))
        saveEvidence(app, "group-regions-sensors-merged-light")
        let options = app.buttons["report-grouping-options"]
        reveal(options, in: app); options.tap()
        let reset = app.buttons["report-reset-grouping"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.tap()
        XCTAssertFalse(app.buttons["report-reset-grouping"].exists)
        app.terminate()

        let restored = launch()
        XCTAssertEqual(restored.descendants(matching: .any)["record-total-reps"].firstMatch.value as? String, initialReps)
        XCTAssertFalse(restored.buttons["report-reset-grouping"].exists)
        XCTAssertFalse(restored.buttons["report-set-2"].exists)
        saveEvidence(restored, "whole-report-restart-source-preserved")
    }

    @MainActor
    func testRealReportAccessibilityLayout() {
        let app = launch(english: true, large: true)
        let count = app.descendants(matching: .any)["record-total-reps"].firstMatch
        reveal(count, in: app)
        saveEvidence(app, "report-large-text-summary")
        let row = app.buttons["report-set-1"]
        reveal(row, in: app); row.tap()
        let menu = app.buttons["report-set-menu-1"]
        reveal(menu, in: app); menu.tap()
        XCTAssertTrue(app.buttons["report-split-set"].exists)
        saveEvidence(app, "report-large-text-group-menu")
    }

    @MainActor
    func testRealReportEnglishDark() {
        let app = launch(english: true, dark: true)
        XCTAssertTrue(app.staticTexts["Training Time"].exists)
        XCTAssertFalse(app.staticTexts["Session"].exists)
        XCTAssertFalse(app.staticTexts["Movement"].exists)
        XCTAssertFalse(app.staticTexts["0 kg"].exists, "Capture has no recorded load")
        saveEvidence(app, "whole-report-real-english-dark")
        let row = app.buttons["report-set-1"]
        reveal(row, in: app); row.tap()
        let menu = app.buttons["report-set-menu-1"]
        reveal(menu, in: app); menu.tap()
        XCTAssertTrue(app.buttons["report-split-set"].exists)
        saveEvidence(app, "whole-report-english-group-menu")
    }

    @MainActor
    func testRealReportSetRegionsEnglishDark() {
        let app = launch(english: true, dark: true)
        let menu = app.buttons["report-set-menu-1"]
        reveal(menu, in: app); menu.tap()
        app.buttons["report-split-set"].tap()
        let save = app.buttons["report-split-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        let stepper = app.steppers["report-split-position"]
        XCTAssertTrue(stepper.exists)
        // Use the actual native stepper's plus control inside its current bounds.
        for _ in 0..<3 { stepper.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap() }
        saveEvidence(app, "group-regions-real-split-input")
        save.tap()
        let setChart = app.descendants(matching: .any)["report-set-timeline"].firstMatch
        reveal(setChart, in: app)
        XCTAssertTrue((setChart.value as? String ?? "").contains("Set 2"))
        saveEvidence(app, "group-regions-timeline-english-dark")
        let sensors = app.descendants(matching: .any)["workout-sensor-chart"].firstMatch
        reveal(sensors, in: app)
        XCTAssertTrue((sensors.value as? String ?? "").contains("Set 2"))
        saveEvidence(app, "group-regions-sensors-english-dark")
        let window = app.buttons["timeline-window"]
        reveal(window, in: app); window.tap()
        app.buttons["timeline-window-15"].tap()
        reveal(sensors, in: app)
        saveEvidence(app, "group-regions-clipped-window-english-dark")
        app.terminate()
        let restored = launch(english: true, dark: true, large: true)
        let largeChart = restored.descendants(matching: .any)["workout-sensor-chart"].firstMatch
        reveal(largeChart, in: restored)
        XCTAssertTrue((largeChart.value as? String ?? "").contains("Set 2"))
        saveEvidence(restored, "group-regions-sensors-large-text-dark")
    }

    @MainActor
    func testRealReportSensorInteraction() {
        let app = launch()
        let chart = app.descendants(matching: .any)["workout-sensor-chart"].firstMatch
        reveal(chart, in: app)
        XCTAssertTrue(chart.exists, "The report must show its received samples without opening a disclosure")
        XCTAssertFalse(app.buttons["report-sensor-sync"].exists)
        saveEvidence(app, "whole-report-real-sensors-light")

        let channel = app.descendants(matching: .any)["timeline-channel"].firstMatch
        reveal(channel, in: app); channel.tap()
        let rotation = app.buttons["timeline-channel-rotation"]
        XCTAssertTrue(rotation.waitForExistence(timeout: 3)); rotation.tap()
        XCTAssertTrue(channel.value as? String == "旋转速率" || channel.label.contains("旋转速率"))
        let second = app.buttons["timeline-rep-2"]
        reveal(second, in: app); second.tap()
        XCTAssertTrue(second.isSelected)
        let selectedTime = second.value as? String
        let cursor = app.descendants(matching: .any)["timeline-cursor-time"].firstMatch
        reveal(cursor, in: app)
        XCTAssertEqual(cursor.value as? String, selectedTime)
        saveEvidence(app, "whole-report-real-sensor-selected-rep")

        let window = app.buttons["timeline-window"]
        reveal(window, in: app); window.tap()
        app.buttons["timeline-window-15"].tap()
        XCTAssertTrue(app.buttons["timeline-next-window"].waitForExistence(timeout: 3))
        saveEvidence(app, "whole-report-real-sensor-zoom")

        let expand = app.buttons["timeline-expand-reps"]
        reveal(expand, in: app); expand.tap()
        let last = app.buttons["timeline-rep-9"]
        reveal(last, in: app); last.tap()
        XCTAssertTrue(last.isSelected)
        XCTAssertTrue(app.buttons["record-more-actions"].exists)
        saveEvidence(app, "whole-report-real-detected-last-rep")
    }

    @MainActor
    func testRealReportSensorAccessibility() {
        let app = launch(english: true, dark: true, large: true)
        let channel = app.descendants(matching: .any)["timeline-channel"].firstMatch
        reveal(channel, in: app); channel.tap()
        app.buttons["timeline-channel-attitude"].tap()
        let chart = app.descendants(matching: .any)["workout-sensor-chart"].firstMatch
        reveal(chart, in: app)
        saveEvidence(app, "whole-report-sensor-large-text-dark")
        let rep = app.buttons["timeline-rep-2"]
        reveal(rep, in: app); rep.tap()
        XCTAssertTrue(rep.isSelected)
        saveEvidence(app, "whole-report-sensor-large-text-selected")
        let previous = app.buttons["timeline-rep-1"], next = app.buttons["timeline-rep-3"]
        XCTAssertLessThanOrEqual(previous.frame.maxY, rep.frame.minY + 1, "Large text rows must not overlap")
        XCTAssertLessThanOrEqual(rep.frame.maxY, next.frame.minY + 1, "Large text rows must reserve their full height")
        for text in rep.staticTexts.allElementsBoundByIndex {
            XCTAssertGreaterThanOrEqual(text.frame.minY, rep.frame.minY - 1)
            XCTAssertLessThanOrEqual(text.frame.maxY, rep.frame.maxY + 1)
        }
    }

    @MainActor
    func testReportWithoutReceivedSamples() {
        let app = launch(english: true, storage: "whole-report-no-sensors")
        let status = app.staticTexts["report-sensor-missing-status"]
        reveal(status, in: app)
        XCTAssertFalse(app.descendants(matching: .any)["workout-sensor-chart"].exists)
        XCTAssertFalse(app.buttons["timeline-rep-1"].exists)
        let sync = app.buttons["report-sensor-sync"]
        reveal(sync, in: app)
        XCTAssertTrue(sync.isHittable)
        saveEvidence(app, "whole-report-no-samples-sync-state")
    }
}
