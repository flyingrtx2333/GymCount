import XCTest

final class PhoneNavigationTests: XCTestCase {
    @MainActor
    func testWatchSetupGuide() {
        for (language, locale, guide) in [("zh-Hans", "zh_CN", "查看安装指南"), ("en", "en_US", "Installation Guide")] {
            let app = XCUIApplication()
            app.launchArguments = ["--isolated-ui-test", "--ui-test-storage-id=" + UUID().uuidString,
                                   "-AppleLanguages", "(" + language + ")", "-AppleLocale", locale,
                                   "-records.appearance", language == "en" ? "dark" : "light"]
            app.launch()
            XCTAssertTrue(app.buttons["watch-setup-open"].waitForExistence(timeout: 15))
            snapshot(app, "watch-setup-empty-" + language)
            app.buttons["watch-setup-open"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["watch-setup-heading"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.links[guide].exists || app.buttons[guide].exists)
            snapshot(app, "watch-setup-guide-" + language)
            app.buttons["sync-close"].tap()
            XCTAssertTrue(app.buttons["add-record"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    func testProfessionalRecordsFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["--isolated-ui-test", "--ui-test-storage-id=" + UUID().uuidString,
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-records.appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["add-record"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["开始训练"].exists)
        app.buttons["add-record"].tap()
        app.buttons["save-record"].tap()
        XCTAssertTrue(app.staticTexts["重量 0–500 公斤，次数 1–999"].exists)
        fill(app, app.textFields["重量（公斤）"], "42.5")
        fill(app, app.textFields["次数"], "8")
        app.buttons["完成"].tap()
        app.buttons["添加一组"].tap()
        fill(app, app.textFields.matching(identifier: "次数").element(boundBy: 1), "6")
        app.buttons["完成"].tap()
        snapshot(app, "pro-multiple-set-entry")
        app.buttons["save-record"].tap()
        XCTAssertTrue(app.buttons["record-select"].waitForExistence(timeout: 5))
        let row = app.cells.containing(.staticText, identifier: "卧推").firstMatch
        row.tap()
        XCTAssertEqual(app.descendants(matching: .any)["record-total-reps"].value as? String, "14 次")
        XCTAssertTrue(app.staticTexts["42.5 公斤 × 8 次"].exists)
        XCTAssertTrue(app.staticTexts["42.5 公斤 × 6 次"].exists)
        app.buttons["edit-record"].tap()
        fill(app, app.textFields.matching(identifier: "重量（公斤）").firstMatch, "45")
        fill(app, app.textFields.matching(identifier: "次数").firstMatch, "10")
        app.buttons["完成"].tap()
        app.buttons["取消"].tap()
        app.buttons["保留草稿"].tap()
        XCTAssertEqual(app.descendants(matching: .any)["record-total-reps"].value as? String, "14 次")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["resume-record-draft"].waitForExistence(timeout: 10))
        app.buttons["resume-record-draft"].tap()
        XCTAssertEqual(app.textFields.matching(identifier: "次数").firstMatch.value as? String, "10")
        app.buttons["save-record"].tap()
        app.cells.containing(.staticText, identifier: "卧推").firstMatch.tap()
        XCTAssertEqual(app.descendants(matching: .any)["record-total-reps"].value as? String, "16 次")
        snapshot(app, "pro-record-detail")
        app.recordTab(3).tap()
        XCTAssertTrue(app.buttons["trend-metric"].waitForExistence(timeout: 5))
        app.buttons["trend-metric"].tap(); app.buttons["trend-metric-weight"].tap()
        XCTAssertEqual(app.descendants(matching: .any)["trend-summary-value"].value as? String, "45 公斤")
        app.buttons["trend-metric"].tap(); app.buttons["trend-metric-reps"].tap()
        XCTAssertEqual(app.descendants(matching: .any)["trend-summary-value"].value as? String, "16 次")
        snapshot(app, "pro-trend-detail")
        app.recordTab(1).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["record-select"].waitForExistence(timeout: 5))
        app.buttons["record-select"].tap(); app.buttons["全选"].tap()
        app.buttons["删除所选记录"].tap()
        app.alerts.buttons["取消"].tap()
        XCTAssertTrue(app.cells.containing(.staticText, identifier: "卧推").firstMatch.exists)
        app.buttons["删除所选记录"].tap(); app.alerts.buttons["删除"].tap()
        XCTAssertFalse(app.cells.containing(.staticText, identifier: "卧推").firstMatch.exists)
    }

    @MainActor
    func testRealRecordsPresentation() throws {
        let app = XCUIApplication()
        let base = ["--isolated-ui-test", "--ui-test-storage-id=pro-records-review", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchArguments = base + ["-records.appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["add-record"].waitForExistence(timeout: 15))
        try requireRealHistory(app)
        XCTAssertTrue(app.cells.containing(.staticText, identifier: "卧推").firstMatch.exists)
        snapshot(app, "pro-real-history-light")
        app.recordTab(3).tap()
        snapshot(app, "pro-real-trends-light")
        app.recordTab(2).tap()
        snapshot(app, "pro-settings-light")
        app.terminate()
        app.launchArguments = base + ["-records.appearance", "dark"]
        app.launch()
        XCTAssertTrue(app.buttons["add-record"].waitForExistence(timeout: 15))
        snapshot(app, "pro-real-history-dark")
        app.terminate()
        app.launchArguments = ["--isolated-ui-test", "--ui-test-storage-id=pro-records-review", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-records.appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-UIAccessibilityReduceMotionEnabled", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["add-record"].waitForExistence(timeout: 15))
        snapshot(app, "pro-real-history-accessibility")
        app.swipeUp()
        snapshot(app, "pro-real-rows-accessibility")
        app.buttons["add-record"].tap()
        snapshot(app, "pro-editor-accessibility")
        app.buttons["Cancel"].tap()
        app.recordTab(3).tap()
        snapshot(app, "pro-trends-accessibility")
    }

    @MainActor
    func testSystemFileDialogs() {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launchArguments = ["--isolated-ui-test", "--ui-test-storage-id=pro-records-review", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-records.appearance", "light"]
        app.launch()
        func capture(_ name: String) {
            print("ALL_PAGES_SCREEN:" + name)
            Thread.sleep(forTimeInterval: 1.5)
            snapshot(app, name)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = name + "-AX"; tree.lifetime = .keepAlways; add(tree)
        }
        func stable(_ element: XCUIElement) {
            var previous: CGRect?
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard element.exists, element.isEnabled, element.isHittable else { return false }
                let frame = element.frame
                defer { previous = frame }
                return frame == previous
            }, object: element)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        }
        defer { capture("backup-roundtrip-final-state") }
        XCTAssertTrue(app.buttons["add-record"].waitForExistence(timeout: 15))
        app.recordTab(2).tap()
        app.buttons["records-backup"].tap()
        let save = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "DOCPicker.actionButton", "保存")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        capture("backup-picker-initial-state")
        let backupName = "PowerReps-Records-Roundtrip-" + String(UUID().uuidString.prefix(8))
        let filename = app.textFields["DOCPicker.filenameTextField"]
        print("BACKUP_DEFAULT_FILENAME:" + String(describing: filename.exists ? filename.value : nil))
        XCTAssertTrue(filename.waitForExistence(timeout: 5))
        XCTAssertTrue((filename.value as? String)?.hasPrefix("PowerReps-Records-") == true)
        filename.tap()
        filename.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 100) + backupName + "\n")
        print("ALL_PAGES_BACKUP_FILENAME:" + backupName)
        stable(save)
        capture("backup-before-save")
        save.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 15), .completed)
        XCTAssertTrue(app.descendants(matching: .any)["records-backup-last-success"].firstMatch.waitForExistence(timeout: 10))
        capture("backup-save-confirmed")
        stable(app.buttons["records-restore"])
        app.buttons["records-restore"].tap()
        capture("backup-restore-picker")
        let backup = app.cells.matching(NSPredicate(format: "label CONTAINS %@", backupName)).firstMatch
        XCTAssertTrue(backup.waitForExistence(timeout: 10))
        backup.tap()
        XCTAssertTrue(app.buttons["confirm-restore"].waitForExistence(timeout: 10))
        capture("backup-restore-preview")
        app.buttons["confirm-restore"].tap()
        XCTAssertTrue(app.staticTexts["恢复完成"].waitForExistence(timeout: 10))
        app.alerts.buttons["确定"].tap()
    }

    @MainActor
    func testRealRecordFiltersAndChartNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--isolated-ui-test", "--ui-test-storage-id=pro-records-review", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-records.appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["record-exercise-filter"].waitForExistence(timeout: 15))
        try requireRealHistory(app)
        app.buttons["record-exercise-filter"].tap()
        app.buttons["深蹲"].tap()
        XCTAssertTrue(app.cells.containing(.staticText, identifier: "深蹲").firstMatch.exists)
        XCTAssertFalse(app.cells.containing(.staticText, identifier: "卧推").firstMatch.exists)
        app.descendants(matching: .any)["history-record"].firstMatch.tap()
        XCTAssertTrue(app.buttons["edit-record"].waitForExistence(timeout: 5))
        let before = app.descendants(matching: .any)["record-total-reps"].value as? String
        app.buttons["edit-record"].tap()
        fill(app, app.textFields["总次数"], "10")
        app.buttons["完成"].tap()
        app.buttons["取消"].tap(); app.buttons["放弃修改"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["save-record"])
        wait(for: [dismissed], timeout: 5)
        XCTAssertEqual(app.descendants(matching: .any)["record-total-reps"].value as? String, before)
        app.navigationBars["训练详情"].buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["record-select"].waitForExistence(timeout: 5))
        app.buttons["record-select"].tap(); app.buttons["全选"].tap()
        app.buttons["删除所选记录"].tap()
        snapshot(app, "pro-filtered-deletion-confirmation")
        app.alerts.buttons["取消"].tap(); app.buttons["record-select"].tap()
        app.buttons["选择日期"].tap()
        XCTAssertTrue(app.navigationBars["选择日期"].waitForExistence(timeout: 5))
        snapshot(app, "pro-calendar")
        app.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["暂无记录"].waitForExistence(timeout: 5))
        app.buttons["清除筛选"].tap()
        app.recordTab(3).tap()
        XCTAssertTrue(app.buttons["trend-metric"].waitForExistence(timeout: 5))
        app.buttons["trend-metric"].tap(); app.buttons["trend-metric-reps"].tap()
        app.buttons["trend-metric"].tap(); app.buttons["trend-granularity-day"].tap()
        let chart = app.descendants(matching: .any)["trend-chart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        let neededScroll = chart.frame.maxY > app.frame.height - 110
        if neededScroll { app.swipeUp() }
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["trend-open-day"].label.contains("10月9日"))
        snapshot(app, "pro-chart-selection")
        if neededScroll { app.swipeDown() }
        app.buttons["trend-open-day"].tap()
        XCTAssertTrue(app.buttons["record-period-filter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["record-period-filter"].label.contains("自定义日期"))
        XCTAssertTrue(app.cells.containing(.staticText, identifier: "卧推").firstMatch.exists)
        snapshot(app, "pro-chart-day-records")
        app.recordTab(3).tap()
        app.buttons["trend-period-filter"].tap()
        app.buttons["全部时间"].tap()
        snapshot(app, "pro-trend-all-years")
    }

    @MainActor
    func testRecordAccessibility() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--isolated-ui-test", "--ui-test-storage-id=pro-records-review", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-records.appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["add-record"].waitForExistence(timeout: 15))
        try requireRealHistory(app)
        snapshot(app, "pro-real-history-english")
        try auditVisibleContent(app)
        app.swipeUp()
        try auditVisibleContent(app)
        app.recordTab(2).tap()
        try auditVisibleContent(app)
        snapshot(app, "pro-settings-english")
    }

    @MainActor
    private func requireRealHistory(_ app: XCUIApplication) throws {
        guard app.descendants(matching: .any)["history-record"].firstMatch.exists else {
            throw XCTSkip("Requires the private real-history seed in isolated storage; see docs/ios-records.md.")
        }
    }

    @MainActor
    private func auditVisibleContent(_ app: XCUIApplication) throws {
        let top = app.navigationBars.firstMatch.frame.maxY + 8
        let bottom = app.recordTab(1).frame.minY - 48
        try app.performAccessibilityAudit(for: [.contrast, .elementDetection, .sufficientElementDescription]) { issue in
            // iOS 26 audits rows underneath the native scroll-edge fade/tab bar.
            // Scroll and audit again above so these same rows are checked unobscured.
            if issue.auditType == .contrast, let element = issue.element,
               element.frame.maxY > bottom || element.frame.minY < top {
                let report = XCTAttachment(string: "Native scroll-edge overlay: " + element.debugDescription)
                report.name = "native-scroll-edge-contrast"; report.lifetime = .keepAlways; self.add(report)
                return true
            }
            return false
        }
    }

    @MainActor
    private func fill(_ app: XCUIApplication, _ field: XCUIElement, _ value: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let old = field.value as? String ?? ""
        if !old.isEmpty && old != "—" {
            field.press(forDuration: 1.2)
            let selectAll = app.menuItems["全选"]
            if selectAll.waitForExistence(timeout: 2) { selectAll.tap() }
            else {
                let button = app.buttons["全选"]
                XCTAssertTrue(button.waitForExistence(timeout: 2)); button.tap()
            }
        }
        field.typeText(value)
        XCTAssertEqual(field.value as? String, value)
    }

    @MainActor
    func testWatchHealthGuideNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["--isolated-ui-test", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.recordTab(2).waitForExistence(timeout: 10))
        app.recordTab(2).tap()
        app.buttons["手表健康权限"].tap()
        XCTAssertTrue(app.navigationBars["手表健康权限"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["设置 → 健康 → 数据来源、App 和服务 → 健身计数器"].exists)
        XCTAssertTrue(app.staticTexts["开启「允许写入」中的「体能训练」。"].exists)
        snapshot(app, "watch-health-permission-guide")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["settings-heading"].exists)
    }

    @MainActor
    func testCaptureStartTimeoutCancellationAndLateReply() {
        let app = XCUIApplication()
        app.launchArguments = ["--isolated-ui-test", "--capture-start-timeout-test", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.recordTab(2).waitForExistence(timeout: 10))
        app.recordTab(2).tap()
        app.buttons["开发者工具"].tap()
        app.buttons["同步录像与采样"].tap()
        let start = app.buttons["开始采集"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(app.staticTexts["正在连接手表…"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["连接超时，请打开手表采集页后重试"].waitForExistence(timeout: 10))
        XCTAssertTrue(start.isEnabled)
        snapshot(app, "capture-start-timeout")

        start.tap()
        let cancel = app.buttons["取消启动"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 2))
        cancel.tap()
        XCTAssertTrue(app.staticTexts["已取消，可重新开始"].waitForExistence(timeout: 3))
        XCTAssertTrue(start.isEnabled)
        // Late replies from both attempts must not change state or start the camera.
        let staleReply = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["已取消，可重新开始"])
        staleReply.isInverted = true
        wait(for: [staleReply], timeout: 9)
        XCTAssertFalse(app.buttons["结束采集"].exists)
        XCTAssertFalse(app.buttons["取消启动"].exists)
        snapshot(app, "capture-start-cancelled")
    }

    @MainActor
    func testWatchHistoryViewerAndDeveloperNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["--isolated-ui-test", "--ui-test-storage-id=" + UUID().uuidString,
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["record-select"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["history-sync-workouts"].exists)
        XCTAssertFalse(app.buttons["tab-0"].exists)
        XCTAssertFalse(app.buttons["开始训练"].exists)
        snapshot(app, "watch-history-empty-viewer")
        app.buttons["history-sync-workouts"].tap()
        XCTAssertTrue(app.buttons["sync-now"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        app.recordTab(2).tap()
        XCTAssertTrue(app.staticTexts["settings-heading"].waitForExistence(timeout: 5))
        app.buttons["开发者工具"].tap()
        app.buttons["采集记录与标注"].tap()
        XCTAssertTrue(app.navigationBars["采集记录"].waitForExistence(timeout: 5))
        app.recordTab(1).tap()
        XCTAssertTrue(app.buttons["record-select"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
