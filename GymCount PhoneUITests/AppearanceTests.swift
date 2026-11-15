import XCTest

final class AppearanceTests: XCTestCase {
    @MainActor private func launch(english: Bool = false, large: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--isolated-ui-test", "--ui-test-storage-id=appearance-real127-20261114",
            "--reset-record-view-preferences", "-AppleLanguages", english ? "(en)" : "(zh-Hans)",
            "-AppleLocale", english ? "en_US" : "zh_CN"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.recordTab(2).waitForExistence(timeout: 12))
        app.recordTab(2).tap()
        app.buttons["records-appearance"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["appearance-mode"].firstMatch.waitForExistence(timeout: 5))
        return app
    }
    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-AX"; tree.lifetime = .keepAlways; add(tree)
    }
    @MainActor func testPalettesModesAndPersistence() {
        let app = launch()
        for (mode, name) in [("深色", "dark"), ("浅色", "light")] {
            app.segmentedControls["appearance-mode"].buttons[mode].tap()
            shot(app, "appearance-open-" + name)
            for palette in ["platinum", "onyx", "mist", "pine", "dusk", "rose"] {
                let choice = app.buttons["appearance-palette-" + palette]
                XCTAssertTrue(choice.isHittable)
                choice.tap(); XCTAssertTrue(choice.isSelected)
                shot(app, "appearance-" + name + "-" + palette)
            }
        }
        app.segmentedControls["appearance-mode"].buttons["深色"].tap()
        app.buttons["appearance-palette-mist"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        for (tab, name) in [(1, "records"), (3, "trends"), (2, "settings")] {
            app.recordTab(tab).tap()
            shot(app, "appearance-mist-dark-" + name)
        }
        app.terminate()
        let restored = launch()
        XCTAssertTrue(restored.buttons["appearance-palette-mist"].isSelected)
        XCTAssertTrue(restored.segmentedControls["appearance-mode"].buttons["深色"].isSelected)
        shot(restored, "appearance-restored-mist-dark")
        restored.segmentedControls["appearance-mode"].buttons["跟随系统"].tap()
        shot(restored, "appearance-system-light")
    }

    @MainActor func testEnglishAccessibility() {
        let app = launch(english: true, large: true)
        let last = app.buttons["appearance-palette-rose"]
        for _ in 0..<12 where !last.isHittable { app.swipeUp() }
        XCTAssertTrue(last.isHittable)
        last.tap(); XCTAssertTrue(last.isSelected)
        XCTAssertEqual(last.label, "Rose")
        shot(app, "appearance-english-large-last-palette")
        let mode = app.descendants(matching: .any)["appearance-mode"].firstMatch
        for _ in 0..<12 where !mode.isHittable { app.swipeDown() }
        XCTAssertTrue(mode.isHittable)
        shot(app, "appearance-english-large-mode")
    }

    @MainActor func testCompactPaletteGrid() {
        let app = launch()
        let mode = app.segmentedControls["appearance-mode"]
        mode.buttons["深色"].tap()
        let last = app.buttons["appearance-palette-rose"]
        for _ in 0..<6 where !last.isHittable { app.swipeUp() }
        XCTAssertTrue(last.isHittable)
        last.tap(); XCTAssertTrue(last.isSelected)
        shot(app, "appearance-compact-last-palette")
        for _ in 0..<6 where !mode.isHittable { app.swipeDown() }
        XCTAssertTrue(mode.isHittable)
        mode.buttons["浅色"].tap()
        app.buttons["appearance-palette-platinum"].tap()
        shot(app, "appearance-compact-platinum-light")
    }
}
