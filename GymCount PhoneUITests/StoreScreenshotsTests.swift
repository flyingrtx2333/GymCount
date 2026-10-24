import XCTest

// Capture the shipping UI with explicitly labelled, non-personal marketing
// examples in isolated storage. These captures are not accuracy validation.
final class StoreScreenshotsTests: XCTestCase {
    @MainActor func testStoreScreenshots() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--isolated-ui-test", "--ui-test-storage-id=appstore-demo-20261024",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-records.appearance", "light"]
        app.launch()
        XCTAssertTrue(app.staticTexts["12 条记录"].waitForExistence(timeout: 15), "Load only the labelled marketing examples")
        capture(app, "store-records")
        app.buttons["tab-3"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["trend-chart"].firstMatch.waitForExistence(timeout: 5))
        capture(app, "store-trends")
        app.buttons["tab-1"].tap()
        app.buttons["add-record"].tap()
        let weight = app.textFields["重量（公斤）"].firstMatch
        weight.tap()
        let value = weight.value as? String ?? ""
        if value != "—" { weight.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)) }
        weight.typeText("70")
        app.buttons["下一项"].tap(); app.typeText("8"); app.buttons["完成"].tap()
        for reps in ["8", "6"] {
            app.buttons["add-record-set"].tap(); app.typeText(reps); app.buttons["完成"].tap()
        }
        capture(app, "store-entry")
        app.buttons["取消"].tap(); app.buttons["放弃修改"].tap()
        let tabsReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons["tab-2"])
        XCTAssertEqual(XCTWaiter.wait(for: [tabsReady], timeout: 5), .completed)
        app.buttons["tab-2"].tap()
        XCTAssertTrue(app.buttons["records-backup"].waitForExistence(timeout: 5))
        capture(app, "store-settings")
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
