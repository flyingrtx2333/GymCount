import XCTest

final class TrainingStreakNativeTests: XCTestCase {
    @MainActor func testHomeStreak() {
        continueAfterFailure = false
        for language in ["zh-Hans", "en"] {
            let app = XCUIApplication()
            app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
            app.launch()
            let streak = app.descendants(matching: .any).matching(identifier: "workout.streak").firstMatch
            XCTAssertTrue(streak.waitForExistence(timeout: 12))
            XCTAssertNotNil(streak.label.range(of: "[0-9]+", options: .regularExpression))
            XCTAssertTrue(app.buttons["workout.start.bench_press"].isHittable)
            XCTAssertTrue(app.buttons["workout.start.deadlift"].isHittable)
            let image = XCTAttachment(screenshot: app.screenshot()); image.name = "watch-streak-\(language)"; image.lifetime = .keepAlways; add(image)
            let tree = XCTAttachment(string: app.debugDescription); tree.name = "watch-streak-\(language)-AX"; tree.lifetime = .keepAlways; add(tree)
            app.terminate()
        }
    }
}
