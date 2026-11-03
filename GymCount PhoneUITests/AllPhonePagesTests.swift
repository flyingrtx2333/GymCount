import XCTest

/// Uses existing isolated history/capture files and never uploads training data.
final class AllPhonePagesTests: XCTestCase {
    @MainActor private func launch(english: Bool = false, large: Bool = false, storage: String = "duo-real-v1") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--isolated-ui-test", "--ui-test-storage-id=" + storage, "--reset-record-view-preferences",
                               "-AppleLanguages", english ? "(en)" : "(zh-Hans)", "-AppleLocale", english ? "en_US" : "zh_CN",
                               "-records.appearance", english ? "dark" : "light"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.recordTab(2).waitForExistence(timeout: 15))
        return app
    }

    @MainActor private func back(_ app: XCUIApplication) {
        let candidates = app.buttons.matching(identifier: "BackButton").allElementsBoundByIndex
        let button = candidates.last(where: { $0.isHittable }) ?? app.navigationBars.buttons.firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
    }

    @MainActor private func tap(_ label: String, in app: XCUIApplication) {
        let element = app.buttons[label]
        for _ in 0..<10 {
            if element.exists && element.isHittable { element.tap(); return }
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTFail("Unreachable control: " + label)
    }

    @MainActor private func cancelFileDialog(_ app: XCUIApplication) {
        if !app.buttons["取消"].exists, app.buttons["浏览"].exists { app.buttons["浏览"].tap() }
        XCTAssertTrue(app.buttons["取消"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
    }

    @MainActor private func waitStable(_ element: XCUIElement) {
        var previous: CGRect?
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard element.exists, element.isEnabled, element.isHittable else { return false }
            let frame = element.frame
            defer { previous = frame }
            return previous == frame
        }, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
    }

    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        // External capture reads the active Duo display; XCTest can return its inactive screen.
        print("ALL_PAGES_SCREEN:" + name)
        Thread.sleep(forTimeInterval: 1.5)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-AX"; tree.lifetime = .keepAlways; add(tree)
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = name; screen.lifetime = .keepAlways; add(screen)
    }

    @MainActor func testSecondaryChinese() { secondary(english: false, large: false) }
    @MainActor func testSecondaryEnglishAccessibility() { secondary(english: true, large: true) }

    @MainActor func testCaptureVisibilityMatchesBuild() {
        let app = launch()
        app.recordTab(2).tap()
        let version = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "版本")).firstMatch
        for _ in 0..<6 {
            if version.exists && version.isHittable { break }
            app.collectionViews.firstMatch.swipeUp()
        }
        shot(app, "settings-build-boundary")
        XCTAssertTrue(version.exists && version.isHittable)
        #if DEBUG
        XCTAssertTrue(app.buttons["开发者工具"].exists)
        shot(app, "settings-debug-capture")
        #else
        XCTAssertFalse(app.buttons["开发者工具"].exists)
        XCTAssertFalse(app.staticTexts["高级"].exists)
        shot(app, "settings-release-no-capture")
        #endif
    }

    @MainActor func testCaptureReviewWithoutVideo() {
        let app = launch()
        app.recordTab(2).tap()
        tap("开发者工具", in: app)
        app.buttons["采集记录与标注"].tap()
        let row = app.buttons["capture-record-E474907B-D701-46FA-AC59-D399BFE87AE6"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Requires the isolated incomplete copy of real capture 24")
        row.tap()
        XCTAssertTrue(app.staticTexts["录像未完成"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["capture-reference-mark"].isEnabled)
        XCTAssertFalse(app.buttons["capture-upload"].isEnabled)
        shot(app, "capture-review-incomplete")
    }

    @MainActor private func secondary(english: Bool, large: Bool) {
        let app = launch(english: english, large: large)
        let suffix = english ? "en-large" : "zh"
        app.recordTab(2).tap()
        tap(english ? "Watch sync" : "手表同步", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["watch-setup-heading"].firstMatch.waitForExistence(timeout: 5))
        shot(app, "sync-" + suffix)
        tap("sync-now", in: app)
        shot(app, "sync-bottom-" + suffix); back(app)
        tap(english ? "Help" : "使用帮助", in: app)
        shot(app, "help-" + suffix); back(app)
        tap(english ? "Watch Health Access" : "手表健康权限", in: app)
        shot(app, "health-" + suffix); back(app)
        tap(english ? "Developer Tools" : "开发者工具", in: app)
        shot(app, "developer-" + suffix)
        app.buttons[english ? "Recordings & Annotations" : "采集记录与标注"].tap()
        shot(app, "capture-history-" + suffix); back(app)
        app.buttons[english ? "Sync Video & Motion" : "同步录像与采样"].tap()
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons.matching(
            NSPredicate(format: "label IN %@", ["不允许", "Don't Allow", "Don’t Allow"])).firstMatch
        if permission.waitForExistence(timeout: 3) { permission.tap() }
        shot(app, "capture-" + suffix)
        let exercise = app.buttons["capture-exercise-picker"]
        XCTAssertTrue(exercise.waitForExistence(timeout: 5))
        exercise.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        shot(app, "capture-exercise-menu-" + suffix)
        let option = app.descendants(matching: .any).matching(identifier: english ? "Bench Press" : "卧推").firstMatch
        if option.waitForExistence(timeout: 3) {
            option.tap()
        } else if english, large, app.frame.width == 375 {
            // iOS 26.5 exposes the menu window without children. The captured native
            // screen places the second option here; assert the resulting selection.
            print("ALL_PAGES_LEGACY_MENU_VISUAL_TAP")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.51)).tap()
        } else {
            XCTFail("The exercise menu option is unavailable")
        }
        XCTAssertTrue(exercise.label.contains(english ? "Bench Press" : "卧推"))
        shot(app, "capture-exercise-selected-" + suffix); back(app); back(app)
        XCTAssertTrue(app.staticTexts["settings-heading"].waitForExistence(timeout: 5))
    }

    @MainActor func testRecordSheetsAndSelection() {
        let app = launch()
        app.buttons["record-select"].tap()
        app.buttons["全选"].tap()
        app.buttons["删除所选记录"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        shot(app, "record-delete-confirmation")
        app.alerts.buttons["取消"].tap()
        app.buttons["record-select"].tap()
        app.buttons["选择日期"].tap()
        shot(app, "record-calendar")
        app.buttons["取消"].tap()
        app.buttons["record-period-filter"].tap(); app.buttons["自定义日期"].tap()
        shot(app, "record-date-range")
        app.buttons["取消"].tap()
        app.buttons["add-record"].tap()
        XCTAssertTrue(app.buttons["save-record"].waitForExistence(timeout: 5))
        shot(app, "record-entry")
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["add-record"].waitForExistence(timeout: 5))
    }

    @MainActor func testFileDialogsWithoutWriting() {
        let app = launch()
        app.recordTab(2).tap()
        app.buttons["records-backup"].tap()
        XCTAssertTrue(app.buttons["保存"].waitForExistence(timeout: 10))
        shot(app, "backup-system-dialog")
        cancelFileDialog(app)
        waitStable(app.buttons["records-restore"])
        app.buttons["records-restore"].tap()
        _ = app.buttons["取消"].waitForExistence(timeout: 3)
        shot(app, "restore-system-dialog")
        cancelFileDialog(app)
        waitStable(app.buttons["records-export"])
        app.buttons["records-export"].tap(); app.buttons["训练汇总 CSV"].tap()
        XCTAssertTrue(app.buttons["保存"].waitForExistence(timeout: 10))
        shot(app, "csv-system-dialog")
        cancelFileDialog(app)
        XCTAssertTrue(app.staticTexts["settings-heading"].waitForExistence(timeout: 5))
    }

    @MainActor func testWholeReportAndSplitSheet() {
        let app = launch(storage: "duo-whole-real-audit")
        let row = app.buttons.matching(identifier: "history-record").allElementsBoundByIndex.first(where: { $0.isHittable })
        XCTAssertNotNil(row); row?.tap()
        XCTAssertTrue(app.descendants(matching: .any)["whole-workout-report"].firstMatch.waitForExistence(timeout: 10))
        shot(app, "whole-report")
        func reveal(_ element: XCUIElement) {
            for _ in 0..<8 {
                let scroll = app.collectionViews.allElementsBoundByIndex.max { $0.frame.minX < $1.frame.minX }!
                let visible = scroll.frame.insetBy(dx: 4, dy: 8)
                if element.exists, element.isHittable, element.frame.minY >= visible.minY, element.frame.maxY <= visible.maxY { return }
                let distance = element.exists ? min(150, max(-150, element.frame.midY - visible.midY)) : 120
                let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5))
                let end = start.withOffset(CGVector(dx: 0, dy: -distance))
                start.press(forDuration: 0.1, thenDragTo: end)
            }
            XCTFail("Report control is outside the visible detail column")
        }
        let menu = app.buttons["report-set-menu-1"]
        reveal(menu); menu.tap(); app.buttons["report-split-set"].tap()
        XCTAssertTrue(app.buttons["report-split-save"].waitForExistence(timeout: 5))
        shot(app, "whole-report-split-sheet")
        app.buttons["取消"].tap()
        let chart = app.descendants(matching: .any)["workout-sensor-chart"].firstMatch
        reveal(chart)
        shot(app, "whole-report-sensors")
    }

    @MainActor func testSensorDetailAndReferenceEvents() {
        let app = launch(storage: "duo-full-timeline-20261103")
        let row = app.buttons.matching(identifier: "history-record").allElementsBoundByIndex.first(where: { $0.isHittable })
        XCTAssertNotNil(row); row?.tap()
        let chart = app.descendants(matching: .any)["workout-sensor-chart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        shot(app, "sensor-acceleration")
        app.buttons["timeline-channel"].tap(); app.buttons["timeline-channel-rotation"].tap()
        shot(app, "sensor-rotation")
        app.buttons["timeline-event-source"].tap(); app.buttons["人工标注"].tap()
        shot(app, "sensor-video-events")
        let second = app.buttons["timeline-rep-2"]
        XCTAssertTrue(second.exists); second.tap()
        XCTAssertTrue(second.isSelected)
        shot(app, "sensor-selected-event")
    }
}
