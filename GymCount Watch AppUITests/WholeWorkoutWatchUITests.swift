import XCTest

/// Runs against the normal Watch app in the isolated preview installation.
/// Does not inject samples, add repetitions, or save a generated workout.
final class WholeWorkoutWatchUITests: XCTestCase {
    @MainActor func testNewExerciseMenusAndSwitching() throws {
        continueAfterFailure = false
        for language in ["zh-Hans", "en"] {
            let app = XCUIApplication()
            app.launchArguments = ["-is_first_launch", "YES", "-AppleLanguages", "(" + language + ")", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
            app.launch()
            let discardLabel = language == "en" ? "Discard workout" : "放弃训练"
            let recovered = app.buttons["workout.recovery.discard"]
            if recovered.waitForExistence(timeout: 2) {
                recovered.tap()
                let confirm = app.alerts.buttons[discardLabel]
                if confirm.waitForExistence(timeout: 2) { confirm.tap() }
                else { try tapSystemAction(discardLabel, in: app) }
            }
            let settings = app.buttons[language == "en" ? "Settings" : "设置"]
            XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
            let health = app.switches[language == "en" ? "Sync to Activity Rings" : "同步到运动圆环"].firstMatch
            reveal(health, in: app)
            if health.value as? String == "1" { health.tap() }
            app.buttons[language == "en" ? "Save" : "保存"].tap()
            let start = app.buttons["workout.start.overhead_press"]
            reveal(start, in: app); capture(app, "new-movements-watch-home-" + language); start.tap()
            XCTAssertTrue(app.staticTexts["whole.count"].waitForExistence(timeout: 8))
            let exercise = app.buttons["whole.exercise"]
            let choices = language == "en" ? ["Barbell Row", "Dumbbell Curl", "Overhead Press"] : ["杠铃划船", "哑铃弯举", "肩上推举"]
            for (id, label) in zip(["barbell_row", "bicep_curl", "overhead_press"], choices) {
                reveal(exercise, in: app); exercise.tap()
                let option = app.buttons["whole.switch." + id]
                reveal(option, in: app); option.tap()
                let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", label), object: exercise)
                XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 8), .completed)
                XCTAssertEqual(app.staticTexts["whole.count"].label, "0")
                capture(app, "new-movements-watch-" + id + "-" + language)
            }
            let actions = app.buttons["whole.actions"]
            reveal(actions, in: app); actions.tap()
            try tapSystemAction(language == "en" ? "Discard workout" : "放弃训练", in: app)
            try tapSystemAction(language == "en" ? "Discard workout" : "放弃训练", in: app)
            XCTAssertTrue(app.buttons["workout.start.bench_press"].waitForExistence(timeout: 8))
            app.terminate()
        }
    }

    @MainActor func testNativeHeadersAndSummary() throws {
        continueAfterFailure = false
        for language in ["zh-Hans", "en"] {
            let app = XCUIApplication()
            app.launchArguments = ["-AppleLanguages", "(" + language + ")", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
            app.launch()
            let start = app.buttons["workout.start.squat"]
            XCTAssertTrue(start.waitForExistence(timeout: 10))
            capture(app, "headers-home-" + language)
            app.buttons[language == "en" ? "Settings" : "设置"].tap()
            capture(app, "headers-settings-" + language)
            let health = app.switches[language == "en" ? "Sync to Activity Rings" : "同步到运动圆环"].firstMatch
            for _ in 0..<4 { if health.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(health.exists)
            if health.value as? String == "1" { health.tap() }
            app.buttons[language == "en" ? "Save" : "保存"].tap()
            XCTAssertTrue(start.waitForExistence(timeout: 5))
            start.tap()
            XCTAssertTrue(app.staticTexts["whole.count"].waitForExistence(timeout: 8))
            capture(app, "headers-live-" + language)
            let finish = app.buttons["workout.end"]
            reveal(finish, in: app)
            finish.tap()
            let done = app.buttons["whole.summary.done"]
            XCTAssertTrue(done.waitForExistence(timeout: 10))
            capture(app, "headers-summary-" + language)
            reveal(done, in: app)
            done.tap()
            XCTAssertTrue(start.waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor func testWholeWorkoutPauseSwitchAndDiscard() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        defer { app.terminate() }

        let start = app.buttons["workout.start.squat"]
        XCTAssertTrue(start.waitForExistence(timeout: 12))
        start.tap()
        let count = app.staticTexts["whole.count"]
        XCTAssertTrue(count.waitForExistence(timeout: 8))
        XCTAssertEqual(count.label, "0")
        XCTAssertFalse(app.buttons["whole.next-set"].exists)
        capture(app, "whole-watch-live-zero-reps")

        let pause = app.buttons["whole.pause"]
        reveal(pause, in: app)
        pause.tap()
        waitForLabel(String(localized: "继续", locale: Locale(identifier: "zh_CN")), element: pause)
        capture(app, "whole-watch-paused")
        pause.tap()
        waitForLabel(String(localized: "暂停", locale: Locale(identifier: "zh_CN")), element: pause)

        let exercise = app.buttons["whole.exercise"]
        reveal(exercise, in: app)
        exercise.tap()
        let bench = app.buttons["whole.switch.bench_press"]
        XCTAssertTrue(bench.waitForExistence(timeout: 5))
        reveal(bench, in: app)
        bench.tap()
        XCTAssertTrue(exercise.waitForExistence(timeout: 5))
        XCTAssertEqual(exercise.value as? String, "卧推")
        XCTAssertEqual(count.label, "0")
        capture(app, "whole-watch-switched-zero-reps")

        let actions = app.buttons["whole.actions"]
        reveal(actions, in: app)
        actions.tap()
        let menuVisible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.debugDescription.contains("label: '放弃训练'")
        }, object: nil)
        let menuResult = XCTWaiter.wait(for: [menuVisible], timeout: 5)
        capture(app, "whole-watch-manual-group-menu")
        XCTAssertEqual(menuResult, .completed)
        // watchOS removes disabled confirmation-dialog actions: zero reps
        // cannot create an empty set, so only discard is offered here.
        XCTAssertFalse(app.debugDescription.contains("手动分组"))
        try tapSystemAction("放弃训练", in: app)
        capture(app, "whole-watch-discard-confirmation")
        XCTAssertTrue(app.debugDescription.contains("放弃这次训练？"))
        try tapSystemAction("放弃训练", in: app)
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        XCTAssertFalse(app.otherElements["whole.summary"].exists)
        capture(app, "whole-watch-discard-home")
    }

    @MainActor private func tapSystemAction(_ label: String, in app: XCUIApplication) throws {
        // On the fixed watchOS review device, the full AX snapshot contains the
        // system action cells but both identifier and typed-cell queries omit
        // them. Use the current labeled cell's measured bounds, never a guessed
        // screen position or the underlying page's similarly labeled button.
        let snapshot = app.debugDescription
        let line = try XCTUnwrap(snapshot.components(separatedBy: "\n").first {
            $0.contains("Cell,") && $0.contains("label: '\(label)'")
        })
        let expression = try NSRegularExpression(pattern: #"\{\{([-0-9.]+), ([-0-9.]+)\}, \{([-0-9.]+), ([-0-9.]+)\}\}"#)
        let match = try XCTUnwrap(expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)))
        let values = try (1...4).map { index in
            try XCTUnwrap(Double((line as NSString).substring(with: match.range(at: index))))
        }
        let action = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        let bounds = app.frame
        XCTAssertTrue(bounds.contains(action))
        XCTAssertGreaterThan(action.height, 20)
        app.coordinate(withNormalizedOffset: CGVector(
            dx: (action.midX - bounds.minX) / bounds.width,
            dy: (action.midY - bounds.minY) / bounds.height
        )).tap()
    }

    @MainActor private func waitForLabel(_ label: String, element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        for _ in 0..<10 {
            let frame = element.frame
            if element.isHittable, frame.minY >= app.frame.minY + 28,
               frame.maxY <= app.frame.maxY - 6 { return }
            let down = frame.minY < app.frame.minY + 28
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.40 : 0.72))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.66 : 0.46))
            from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.15)
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.7)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-AX"; tree.lifetime = .keepAlways; add(tree)
    }
}
