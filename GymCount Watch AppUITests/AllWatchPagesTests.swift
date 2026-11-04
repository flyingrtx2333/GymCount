import XCTest

/// Visits production pages in an isolated installation; never injects motion or uploads data.
final class AllWatchPagesTests: XCTestCase {
    @MainActor func testSecondaryPagesChinese() { visit(english: false) }
    @MainActor func testSecondaryPagesEnglish() { visit(english: true) }

    @MainActor func testCompactHomeAndHistoryFilters() {
        continueAfterFailure = false
        for english in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["-AppleLanguages", english ? "(en)" : "(zh-Hans)", "-AppleLocale", english ? "en_US" : "zh_CN"]
            app.launch()
            XCTAssertTrue(app.buttons["workout.start.bench_press"].waitForExistence(timeout: 10))
            XCTAssertLessThanOrEqual(app.buttons["workout.start.bench_press"].frame.minY, 86)
            shot(app, english ? "compact-home-en" : "compact-home-zh")
            app.buttons[english ? "History" : "历史"].tap()
            let exercise = app.buttons["history.exercise-filter"]
            let week = app.buttons["history.week-filter"]
            XCTAssertTrue(week.waitForExistence(timeout: 5))
            XCTAssertEqual(exercise.frame.midY, week.frame.midY, accuracy: 1)
            XCTAssertLessThanOrEqual(exercise.frame.maxX, week.frame.minX)
            XCTAssertGreaterThanOrEqual(exercise.frame.height, 44)
            XCTAssertGreaterThanOrEqual(week.frame.height, 44)
            let originalWeek = week.value as? String
            shot(app, english ? "compact-history-en" : "compact-history-zh")
            week.tap()
            let previous = app.buttons["history.week.previous"]
            let next = app.buttons["history.week.next"]
            XCTAssertTrue(previous.waitForExistence(timeout: 5))
            XCTAssertFalse(next.isEnabled)
            previous.tap()
            XCTAssertTrue(next.isEnabled)
            shot(app, english ? "compact-week-selector-en" : "compact-week-selector-zh")
            app.buttons["history.week-back"].tap()
            XCTAssertTrue(week.waitForExistence(timeout: 5))
            XCTAssertNotEqual(week.value as? String, originalWeek)
            week.tap(); app.buttons["history.week.current"].tap()
            XCTAssertTrue(week.waitForExistence(timeout: 5))
            XCTAssertEqual(week.value as? String, originalWeek)
            let records = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "feedback.history."))
            for _ in 0..<12 {
                if records.count > 0 { break }
                week.tap(); previous.tap(); app.buttons["history.week-back"].firstMatch.tap()
                XCTAssertTrue(week.waitForExistence(timeout: 5))
            }
            shot(app, english ? "plain-history-inspected-en" : "plain-history-inspected-zh")
            XCTAssertGreaterThan(records.count, 0, "Uses the original history copied into isolated preview storage")
            XCTAssertGreaterThanOrEqual(records.firstMatch.frame.minY, exercise.frame.maxY)
            XCTAssertLessThanOrEqual(records.firstMatch.frame.minY - exercise.frame.maxY, 2)
            XCTAssertLessThanOrEqual(records.firstMatch.frame.maxY, app.frame.maxY - 6)
            if records.count > 1 {
                XCTAssertLessThanOrEqual(records.element(boundBy: 1).frame.maxY, app.frame.maxY - 6)
            }
            shot(app, english ? "plain-real-history-en" : "plain-real-history-zh")
            week.tap()
            let chart = app.descendants(matching: .any).matching(identifier: "history.week.chart").firstMatch
            reveal(chart, app)
            XCTAssertTrue(chart.exists)
            shot(app, english ? "plain-week-summary-en" : "plain-week-summary-zh")
            app.buttons["history.week-back"].firstMatch.tap()
            exercise.tap()
            let curl = app.buttons["history.exercise.bicep_curl"]
            reveal(curl, app); curl.tap()
            XCTAssertTrue(week.waitForExistence(timeout: 5))
            XCTAssertEqual(exercise.frame.midY, week.frame.midY, accuracy: 1)
            XCTAssertLessThanOrEqual(exercise.frame.maxX, week.frame.minX)
            shot(app, english ? "compact-history-long-exercise-en" : "compact-history-long-exercise-zh")
            app.terminate()
        }
    }

    @MainActor func testCompactEnglishHeadings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["History"].waitForExistence(timeout: 12))
        app.buttons["History"].tap()
        app.buttons["history.exercise-filter"].tap()
        header(app, title: "Exercise")
        shot(app, "compact-exercise-heading-en")
        close(app, title: "Exercise")
        close(app, title: "History")
        app.buttons["Settings"].tap()
        let weight = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Weight")).firstMatch
        XCTAssertTrue(weight.waitForExistence(timeout: 5)); weight.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == %@ AND value == %@", "weight-input-back", "Weight")).firstMatch.waitForExistence(timeout: 5))
        shot(app, "compact-weight-heading-en")
        app.buttons["weight-input-back"].tap()
        close(app, title: "Settings")
    }

    @MainActor func testWeightFormVisibleControls() {
        continueAfterFailure = false
        for english in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["-AppleLanguages", english ? "(en)" : "(zh-Hans)", "-AppleLocale", english ? "en_US" : "zh_CN"]
            app.launch()
            let settings = app.buttons[english ? "Settings" : "设置"]
            XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
            let weight = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", english ? "Weight" : "器械重量")).firstMatch
            XCTAssertTrue(weight.waitForExistence(timeout: 5)); weight.tap()
            let save = app.buttons["weight-input-save"]
            let plus = app.buttons["weight-step-plus"]
            let minus = app.buttons["weight-step-minus"]
            XCTAssertTrue(save.waitForExistence(timeout: 5))
            XCTAssertTrue(plus.isHittable); XCTAssertTrue(minus.isHittable)
            XCTAssertLessThanOrEqual(plus.frame.maxY, save.frame.minY)
            XCTAssertLessThanOrEqual(minus.frame.maxY, save.frame.minY)
            XCTAssertLessThanOrEqual(save.frame.maxY, app.frame.maxY)
            shot(app, english ? "all-weight-form-en" : "all-weight-form-zh-Hans")
            app.buttons["weight-input-back"].tap()
            shot(app, english ? "all-final-settings-en" : "all-final-settings-zh-Hans")
            close(app, title: english ? "Settings" : "设置")
            app.terminate()
        }
    }

    @MainActor private func visit(english: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        let language = english ? "en" : "zh-Hans"
        app.launchArguments = ["-AppleLanguages", "(" + language + ")", "-AppleLocale", english ? "en_US" : "zh_CN"]
        app.launch()
        defer { app.terminate() }
        let settings = app.buttons[english ? "Settings" : "设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 12))
        app.buttons[english ? "History" : "历史"].tap()
        header(app, title: english ? "History" : "历史")
        shot(app, "all-history-" + language)
        app.buttons["history.exercise-filter"].tap()
        header(app, title: english ? "Exercise" : "选择动作")
        shot(app, "all-history-picker-" + language)
        let squat = app.buttons["history.exercise.squat"]
        reveal(squat, app); squat.tap()
        close(app, title: english ? "History" : "历史")
        XCTAssertTrue(settings.waitForExistence(timeout: 5)); settings.tap()
        header(app, title: english ? "Settings" : "设置")
        XCTAssertFalse(app.buttons["settings.save"].exists, "Unchanged settings do not reserve a save bar")
        shot(app, "all-settings-" + language)
        let guide = app.buttons["settings.healthGuide"]
        reveal(guide, app); guide.tap()
        header(app, title: english ? "Health Access" : "健康权限")
        shot(app, "all-health-guide-" + language)
        close(app, title: english ? "Health Access" : "健康权限")
        header(app, title: english ? "Settings" : "设置")
        let help = app.buttons["settings.help"]
        reveal(help, app); help.tap()
        XCTAssertTrue(back(app).waitForExistence(timeout: 5))
        shot(app, "all-help-" + language)
        for (key, title) in [("training", english ? "Start a workout" : "开始训练"),
                             ("siri", "Siri"), ("records", english ? "View records" : "查看记录"),
                             ("health", english ? "Health sync" : "健康同步"),
                             ("review", english ? "Check the count" : "计数核对")] {
            let topic = app.buttons["help.topic." + key]
            reveal(topic, app); topic.tap()
            header(app, title: title)
            shot(app, "all-help-topic-" + key + "-" + language)
            app.swipeUp()
            close(app, title: title)
        }
        shot(app, "all-help-bottom-" + language)
        close(app, title: english ? "Help" : "使用帮助")
        #if DEBUG
        let advanced = app.buttons["settings.advanced"]
        reveal(advanced, app); advanced.tap()
        XCTAssertTrue(back(app).waitForExistence(timeout: 5))
        shot(app, "all-advanced-" + language)
        app.buttons["settings.capture"].tap()
        XCTAssertTrue(app.buttons["capture.exercise"].waitForExistence(timeout: 5))
        // The unsigned native preview truthfully reports unavailable HealthKit.
        // Inspect and dismiss that real system alert before operating the page.
        let permission = app.buttons[english ? "Got It" : "知道了"]
        if permission.waitForExistence(timeout: 4) {
            shot(app, "all-capture-permission-" + language)
            permission.tap()
        }
        shot(app, "all-capture-" + language)
        app.buttons["capture.exercise"].tap()
        XCTAssertTrue(back(app).waitForExistence(timeout: 5))
        shot(app, "all-capture-picker-" + language)
        app.swipeUp(); app.swipeUp()
        shot(app, "all-capture-picker-bottom-" + language)
        close(app, title: english ? "Exercise" : "选择动作")
        header(app, title: english ? "Capture" : "采集")
        let notes = app.buttons["capture.notes"]
        reveal(notes, app); notes.tap()
        XCTAssertTrue(back(app).waitForExistence(timeout: 5))
        shot(app, "all-capture-notes-" + language)
        close(app, title: english ? "Notes" : "备注")
        close(app, title: english ? "Capture" : "采集")
        close(app, title: english ? "Advanced" : "高级")
        #else
        XCTAssertFalse(app.buttons["settings.advanced"].exists)
        #endif
        let version = app.descendants(matching: .any).matching(identifier: "settings.version").firstMatch
        reveal(version, app)
        shot(app, "all-settings-bottom-" + language)
        let reminder = app.switches[english ? "Daily reminder" : "每日提醒"].firstMatch
        reveal(reminder, app); reminder.tap()
        let save = app.buttons["settings.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isHittable, "Changed settings expose a reachable save action")
        XCTAssertGreaterThanOrEqual(save.frame.height, 44)
        shot(app, "all-settings-edited-" + language)
        close(app, title: english ? "Settings" : "设置") // no settings or training data changes
        XCTAssertTrue(settings.waitForExistence(timeout: 5)); settings.tap()
        XCTAssertFalse(app.buttons["settings.save"].exists, "Cancel leaves settings unchanged")
        close(app, title: english ? "Settings" : "设置")
    }

    @MainActor private func back(_ app: XCUIApplication) -> XCUIElement {
        let query = app.buttons.matching(identifier: "watch.back")
        return query.allElementsBoundByIndex.last(where: { $0.isHittable }) ?? query.element(boundBy: 0)
    }
    @MainActor private func close(_ app: XCUIApplication, title: String) {
        let button = app.buttons.matching(NSPredicate(format: "identifier == %@ AND value == %@", "watch.back", title)).element(boundBy: 0)
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }
    @MainActor private func header(_ app: XCUIApplication, title: String) {
        let button = app.buttons.matching(NSPredicate(format: "identifier == %@ AND value == %@", "watch.back", title)).element(boundBy: 0)
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertEqual(button.value as? String, title)
        XCTAssertLessThan(button.frame.minY, 20)
        XCTAssertGreaterThanOrEqual(button.frame.height, 44)
    }
    @MainActor private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<24 {
            let save = app.buttons["settings.save"]
            let bottom = save.exists && save.isHittable ? save.frame.minY - 3 : app.frame.maxY - 8
            if element.exists, element.isHittable, element.frame.minY >= 44, element.frame.maxY <= bottom { return }
            let down = element.exists && element.frame.minY < 44
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: down ? 0.33 : 0.55))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: down ? 0.55 : 0.33))
            from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        shot(app, "unreachable-page-control")
        XCTAssertTrue(element.exists)
        XCTAssertTrue(element.isHittable)
    }
    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-AX"; tree.lifetime = .keepAlways; add(tree)
    }
}
