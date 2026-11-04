import XCTest

// Exercises the actual editor and persisted records. It does not inject motion
// or treat manually entered software-test records as counting accuracy data.
final class NewExercisesTests: XCTestCase {
    @MainActor func testChineseNewMovements() { check(english: false) }
    @MainActor func testEnglishLargeNewMovements() { check(english: true) }

    @MainActor private func check(english: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        let storage = "new-movements-" + (english ? "en-" : "zh-") + UUID().uuidString
        print("NEW_MOVEMENTS_STORAGE:" + storage)
        app.launchArguments = ["--isolated-ui-test", "--ui-test-storage-id=" + storage,
                               "--reset-record-view-preferences", "-AppleLanguages", english ? "(en)" : "(zh-Hans)",
                               "-AppleLocale", english ? "en_US" : "zh_CN", "-records.appearance", english ? "dark" : "light"]
        if english { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let add = app.buttons["add-record"]
        XCTAssertTrue(add.waitForExistence(timeout: 15)); add.tap()
        let names = english ? ["Overhead Press", "Barbell Row", "Dumbbell Curl"] : ["肩上推举", "杠铃划船", "哑铃弯举"]
        for (index, name) in names.enumerated() {
            if index > 0 { app.buttons["add-record-set"].tap() }
            let picker = app.buttons["record-set-exercise-\(index)"]
            reveal(picker, in: app); picker.tap()
            choose(name, in: app)
            XCTAssertEqual(picker.value as? String, name)
            let weight = app.textFields["record-set-\(index + 1)-weight-field"]
            reveal(weight, in: app); fill(weight, with: ["20", "30", "8"][index])
            let reps = app.textFields["record-set-\(index + 1)-reps-field"]
            reveal(reps, in: app); fill(reps, with: ["8", "10", "12"][index])
        }
        let done = app.buttons[english ? "Done" : "完成"].firstMatch
        if done.exists && done.isHittable { done.tap() }
        let save = app.buttons["save-record"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
        capture(app, english ? "new-movements-editor-en-large" : "new-movements-editor-zh")
        save.tap()
        let row = app.buttons["history-record"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
        for name in names { XCTAssertTrue(app.staticTexts[name].firstMatch.waitForExistence(timeout: 5)) }
        capture(app, english ? "new-movements-detail-en-large" : "new-movements-detail-zh")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["history-record"].firstMatch.waitForExistence(timeout: 12))
        let filter = app.buttons["record-exercise-filter"]
        for name in names {
            filter.tap(); choose(name, in: app)
            XCTAssertTrue(filter.label.contains(name))
            XCTAssertTrue(app.buttons["history-record"].firstMatch.waitForExistence(timeout: 5))
        }
        capture(app, english ? "new-movements-record-filter-en" : "new-movements-record-filter-zh")
        app.recordTab(3).tap()
        let metric = app.buttons["trend-metric"]
        XCTAssertTrue(metric.waitForExistence(timeout: 5)); metric.tap()
        app.buttons["trend-metric-reps"].tap()
        let trendFilter = app.buttons["trend-exercise-filter"]
        for (name, reps) in zip(names, ["8", "10", "12"]) {
            trendFilter.tap(); choose(name, in: app)
            let value = app.descendants(matching: .any)["insights-reps"].firstMatch
            reveal(value, in: app, scrollID: "trends-scroll")
            let correct = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", reps), object: value)
            XCTAssertEqual(XCTWaiter.wait(for: [correct], timeout: 8), .completed)
        }
        let chart = app.descendants(matching: .any)["trend-chart"].firstMatch
        reveal(chart, in: app, scrollID: "trends-scroll")
        XCTAssertGreaterThan(chart.frame.height, 100)
        capture(app, english ? "new-movements-trends-en" : "new-movements-trends-zh")
        app.terminate()
    }

    @MainActor private func fill(_ field: XCUIElement, with text: String) {
        field.tap()
        let old = field.value as? String ?? ""
        if !old.isEmpty && old != "—" {
            field.doubleTap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
        }
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text)
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication, scrollID: String = "record-editor-scroll") {
        let scroll = app.scrollViews[scrollID]
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            if element.exists && element.frame.midY < scroll.frame.midY { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor private func choose(_ name: String, in app: XCUIApplication) {
        // Native menus lazily create lower rows at large accessibility sizes.
        for _ in 0..<6 {
            let matches = app.buttons.matching(NSPredicate(format: "label == %@", name)).allElementsBoundByIndex
            if let option = matches.last(where: { $0.isHittable }) { option.tap(); return }
            app.swipeUp()
        }
        capture(app, "unavailable-native-menu"); XCTFail("Visible option missing: " + name)
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        print("NEW_MOVEMENTS_SCREEN:" + name)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-AX"; tree.lifetime = .keepAlways; add(tree)
    }
}
