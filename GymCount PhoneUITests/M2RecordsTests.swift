import XCTest

final class M2RecordsTests: XCTestCase {
    @MainActor private func launch(_ id: String, dark: Bool = false, englishLarge: Bool = false, english: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--isolated-ui-test", "--ui-test-storage-id=" + id, "--reset-record-view-preferences",
            "-AppleLanguages", englishLarge || english ? "(en)" : "(zh-Hans)", "-AppleLocale", englishLarge || english ? "en_US" : "zh_CN",
            "-records.appearance", dark ? "dark" : "light"]
        if englishLarge { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-UIAccessibilityReduceMotionEnabled", "YES"] }
        app.launch()
        app.launchArguments.removeAll { $0 == "--reset-record-view-preferences" }
        XCTAssertTrue(app.buttons["add-record"].waitForExistence(timeout: 15))
        return app
    }
    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    @MainActor private func fill(_ field: XCUIElement, _ value: String) {
        field.tap()
        let old = field.value as? String ?? ""
        if old != "—" && !old.isEmpty {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
        }
        field.typeText(value)
    }
    @MainActor func testM2RealRecordsAndTrends() {
        let app = launch("m2-real-review")
        XCTAssertTrue(app.staticTexts["82 条记录"].exists, "Requires the original 82-record snapshot in isolated storage")
        let recordFilter = app.buttons["record-exercise-filter"]
        XCTAssertLessThan(recordFilter.frame.maxY, app.buttons["history-record"].firstMatch.frame.minY)
        XCTAssertLessThan(app.buttons["add-record"].frame.maxY, recordFilter.frame.minY)
        shot(app, "m2-integrated-records-light")
        app.buttons["record-exercise-filter"].tap(); app.buttons["深蹲"].tap()
        XCTAssertTrue(app.cells.containing(.staticText, identifier: "深蹲").firstMatch.exists)
        XCTAssertFalse(app.cells.containing(.staticText, identifier: "卧推").firstMatch.exists)
        app.buttons["history-record"].firstMatch.swipeLeft()
        app.buttons["编辑"].firstMatch.tap()
        XCTAssertTrue(app.textFields["总次数"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        app.buttons["record-select"].tap(); app.buttons["全选"].tap()
        app.buttons["删除所选记录"].tap(); app.alerts.buttons["取消"].tap()
        app.buttons["record-select"].tap()
        app.buttons["tab-3"].tap()
        let chart = app.descendants(matching: .any)["trend-chart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        XCTAssertLessThan(app.buttons["trend-exercise-filter"].frame.maxY, chart.frame.minY)
        XCTAssertLessThan(app.buttons["trend-metric"].frame.maxY, chart.frame.minY)
        shot(app, "m2-integrated-trends-light")
        app.buttons["trend-metric"].tap(); app.buttons["次数"].firstMatch.tap()
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["trend-open-day"].label.contains("0 次"))
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        XCTAssertTrue(app.buttons["trend-open-day"].label.contains("15 次"))
        app.buttons["trend-open-day"].tap()
        XCTAssertTrue(app.staticTexts["4 条记录"].waitForExistence(timeout: 5))
        app.buttons["选择日期"].tap()
        XCTAssertTrue(app.navigationBars["选择日期"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        // Repeated explicit taps retarget page transitions without queuing navigation.
        for _ in 0..<3 { app.buttons["tab-3"].tap(); app.buttons["tab-1"].tap() }
        XCTAssertTrue(app.buttons["add-record"].exists)
        app.buttons["tab-2"].tap()
        XCTAssertTrue(app.buttons["records-backup"].waitForExistence(timeout: 5))
    }
    @MainActor func testM2EntryPersistenceAndKeyboard() {
        let id = "m2-entry-" + UUID().uuidString
        let app = launch(id)
        app.buttons["add-record"].tap()
        app.buttons["save-record"].tap()
        XCTAssertTrue(app.staticTexts["重量 0–500 公斤，次数 1–999"].exists)
        fill(app.textFields["重量（公斤）"].firstMatch, "42.5")
        app.buttons["下一项"].tap(); app.typeText("8")
        app.buttons["完成"].tap()
        app.buttons["add-record-set"].tap()
        app.typeText("6")
        app.buttons["完成"].tap()
        XCTAssertEqual(app.textFields.matching(identifier: "重量（公斤）").element(boundBy: 1).value as? String, "42.5")
        shot(app, "m2-integrated-entry-light")
        app.buttons["取消"].tap(); app.buttons["保留草稿"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["resume-record-draft"].waitForExistence(timeout: 10))
        app.buttons["resume-record-draft"].tap()
        XCTAssertEqual(app.textFields.matching(identifier: "次数").element(boundBy: 1).value as? String, "6")
        app.buttons["save-record"].tap()
        XCTAssertTrue(app.staticTexts["1 条记录"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["record-time-empty"].firstMatch.exists)
        app.buttons["history-record"].firstMatch.tap()
        XCTAssertEqual(app.descendants(matching: .any)["record-total-reps"].value as? String, "14 次")
        let firstSet = app.descendants(matching: .any)["record-set-1"].firstMatch
        XCTAssertEqual(firstSet.label, "第 1 组")
        XCTAssertEqual(firstSet.value as? String, "42.5 公斤 · 8 次")
        app.buttons["tab-2"].tap()
        app.buttons["records-export"].tap()
        XCTAssertTrue(app.buttons["records-export-sets"].isEnabled)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.1)).tap()
        app.buttons["tab-3"].tap()
        XCTAssertEqual(app.descendants(matching: .any)["trend-total-reps"].value as? String, "14 次")
        XCTAssertEqual(app.descendants(matching: .any)["trend-best-weight"].value as? String, "42.5 公斤")
        app.buttons["tab-1"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["record-select"].tap(); app.buttons["全选"].tap()
        app.buttons["删除所选记录"].tap(); app.alerts.buttons["删除"].tap()
        XCTAssertTrue(app.staticTexts["暂无记录"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["暂无记录"].waitForExistence(timeout: 10))
    }
    @MainActor func testM2PresentationVariants() {
        var app = launch("m2-real-review", dark: true)
        XCTAssertTrue(app.staticTexts["82 条记录"].exists)
        shot(app, "m2-integrated-records-dark")
        app.buttons["tab-3"].tap(); shot(app, "m2-integrated-trends-dark")
        app.terminate()
        app = launch("m2-real-review", englishLarge: true)
        let title = app.staticTexts["Records"].firstMatch
        XCTAssertGreaterThanOrEqual(title.frame.minY, app.frame.minY)
        XCTAssertTrue(app.buttons["add-record"].isHittable)
        shot(app, "m2-integrated-records-large-english")
        app.buttons["history-sync-workouts"].tap()
        XCTAssertTrue(app.buttons["sync-now"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let filter = app.buttons["record-exercise-filter"]
        let filterTop = filter.frame.minY
        app.swipeUp()
        XCTAssertTrue(!filter.exists || !filter.isHittable || filter.frame.minY < filterTop - 40, "Large-text filters must scroll with records")
        XCTAssertTrue(app.buttons["add-record"].isHittable)
        shot(app, "records-large-english-scrolled")
        app.buttons["add-record"].tap()
        XCTAssertTrue(app.buttons["save-record"].waitForExistence(timeout: 5))
        shot(app, "m2-integrated-entry-large-english")
        app.buttons["Cancel"].tap()
        app.buttons["tab-3"].tap()
        shot(app, "m2-integrated-trends-large-english")
        let trendFilter = app.buttons["trend-exercise-filter"]
        let trendFilterTop = trendFilter.frame.minY
        app.swipeUp()
        XCTAssertTrue(!trendFilter.isHittable || trendFilter.frame.minY < trendFilterTop - 40, "Large-text trend filters must scroll")
        shot(app, "trends-large-english-scrolled")
    }
    @MainActor func testOptionalRecordFields() {
        let app = launch("compact-fields-" + UUID().uuidString)
        app.buttons["add-record"].tap()
        fill(app.textFields["重量（公斤）"].firstMatch, "42.5")
        app.buttons["下一项"].tap(); app.typeText("8")
        app.buttons["完成"].tap()
        let duration = app.textFields["record-duration-field"]
        let note = app.descendants(matching: .any)["record-note-field"].firstMatch
        XCTAssertTrue(duration.exists)
        XCTAssertLessThan(note.frame.height, 70, "An empty note should occupy one compact row")
        fill(duration, "7.5")
        app.buttons["下一项"].tap()
        app.typeText("训练记录\n保留动作和重量")
        app.buttons["完成"].tap()
        XCTAssertGreaterThan(note.frame.height, 44)
        shot(app, "entry-optional-fields-filled")
        app.buttons["取消"].tap(); app.buttons["保留草稿"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["resume-record-draft"].waitForExistence(timeout: 10))
        app.buttons["resume-record-draft"].tap()
        XCTAssertEqual(duration.value as? String, "7.5")
        XCTAssertTrue((note.value as? String ?? "").contains("保留动作和重量"))
        app.buttons["save-record"].tap()
        XCTAssertTrue(app.buttons["history-record"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["history-record"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "7:30", "7:30")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "保留动作和重量")).firstMatch.waitForExistence(timeout: 5))
    }
    @MainActor func testCompactEnglishPresentation() {
        let app = launch("m2-real-review", english: true)
        XCTAssertTrue(app.buttons["record-time-metric"].isHittable)
        shot(app, "records-english")
        app.buttons["tab-3"].tap()
        shot(app, "trends-english")
        app.buttons["tab-1"].tap(); app.buttons["add-record"].tap()
        XCTAssertTrue(app.buttons["save-record"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["save-record"].isHittable)
        shot(app, "entry-english")
        app.buttons["Cancel"].tap()
    }
    @MainActor func testRecordTimeChart() {
        let app = launch("m2-real-review")
        XCTAssertTrue(app.staticTexts["82 条记录"].exists)
        let chart = app.descendants(matching: .any)["record-time-chart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        shot(app, "record-time-all-light")
        app.buttons["record-time-metric"].tap(); app.buttons["record-time-granularity-day"].tap()
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["record-time-open-day"].waitForExistence(timeout: 5))
        app.buttons["record-time-open-day"].tap()
        XCTAssertLessThan(app.buttons["history-record"].firstMatch.frame.minY, 300)
        app.buttons["record-exercise-filter"].tap(); app.buttons["卧推"].tap()
        app.buttons["record-period-filter"].tap(); app.buttons["近7天"].tap()
        XCTAssertTrue(app.staticTexts["4 条记录"].waitForExistence(timeout: 5))
        XCTAssertTrue(chart.exists)
        shot(app, "record-time-bench-week")
        app.buttons["record-time-metric"].tap(); app.buttons["动作时长（估计）"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["record-time-empty"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(chart.exists, "Missing action durations must not be rendered as zero")
        shot(app, "record-time-unmeasured")
        app.buttons["record-time-metric"].tap(); app.buttons["训练总用时"].tap()
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
    }
    @MainActor func testExportSummaryScope() {
        let app = launch("m2-real-review")
        app.buttons["record-exercise-filter"].tap(); app.buttons["卧推"].tap()
        app.buttons["record-period-filter"].tap(); app.buttons["近7天"].tap()
        XCTAssertTrue(app.staticTexts["4 条记录"].waitForExistence(timeout: 5))
        app.buttons["tab-2"].tap()
        let export = app.buttons["records-export"]
        XCTAssertTrue(export.label.contains("卧推"))
        XCTAssertTrue(export.label.contains("近7天"))
        XCTAssertTrue(export.label.contains("4 条记录"))
        shot(app, "workflow-export-scope")
        export.tap()
        let details = app.descendants(matching: .any)["records-export-sets"].firstMatch
        let tree = XCTAttachment(string: app.debugDescription); tree.name = "disabled-export-menu-tree"; tree.lifetime = .keepAlways; add(tree)
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertFalse(details.isEnabled)
        XCTAssertTrue(app.buttons["训练汇总 CSV"].isEnabled)
        shot(app, "workflow-no-empty-set-export")
    }
    @MainActor func testChartPeriodNavigation() {
        let app = launch("m2-real-review")
        XCTAssertTrue(app.staticTexts["82 条记录"].exists)
        let timeChart = app.descendants(matching: .any)["record-time-chart"].firstMatch
        XCTAssertEqual(app.buttons["record-time-metric"].value as? String, "按月")
        shot(app, "workflow-records-monthly")
        timeChart.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        app.buttons["record-time-open-day"].tap()
        XCTAssertTrue(app.staticTexts["6 条记录"].waitForExistence(timeout: 5), "A month opens every record in the month")
        app.buttons["选择日期"].tap()
        XCTAssertTrue(app.navigationBars["选择日期"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        app.buttons["tab-3"].tap()
        app.buttons["trend-metric"].tap(); app.buttons["trend-granularity-week"].tap()
        XCTAssertTrue(app.buttons["trend-open-day"].label.contains("70 公斤"))
        shot(app, "workflow-trends-weekly")
        app.buttons["trend-open-day"].tap()
        XCTAssertTrue(app.staticTexts["4 条记录"].waitForExistence(timeout: 5), "A week opens every matching workout in that week")
        app.buttons["tab-3"].tap()
        app.buttons["trend-metric"].tap(); app.buttons["trend-granularity-month"].tap()
        app.buttons["trend-open-day"].tap()
        XCTAssertTrue(app.staticTexts["5 条记录"].waitForExistence(timeout: 5), "Month navigation preserves the exercise filter")
    }
    @MainActor func testRecordViewPreferences() {
        let app = launch("m2-real-review")
        app.buttons["record-exercise-filter"].tap(); app.buttons["卧推"].tap()
        app.buttons["record-period-filter"].tap(); app.buttons["近30天"].tap()
        app.buttons["record-time-metric"].tap(); app.buttons["动作时长（估计）"].tap()
        app.buttons["record-time-metric"].tap(); app.buttons["record-time-granularity-week"].tap()
        app.buttons["record-time-metric"].tap(); app.buttons["record-time-toggle-chart"].tap()
        app.buttons["tab-3"].tap()
        app.buttons["trend-exercise-filter"].tap(); app.buttons["深蹲"].tap()
        app.buttons["trend-period-filter"].tap(); app.buttons["全部时间"].tap()
        app.buttons["trend-metric"].tap(); app.buttons["次数"].firstMatch.tap()
        app.buttons["trend-metric"].tap(); app.buttons["trend-granularity-month"].tap()
        app.buttons["trend-metric"].tap(); app.buttons["trend-toggle-chart"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["5 条记录"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["record-exercise-filter"].label.contains("卧推"))
        XCTAssertTrue(app.buttons["record-period-filter"].label.contains("近30天"))
        XCTAssertTrue(app.buttons["record-time-metric"].label.contains("动作时长"))
        XCTAssertEqual(app.buttons["record-time-metric"].value as? String, "按周")
        XCTAssertFalse(app.descendants(matching: .any)["record-time-chart"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["record-time-empty"].firstMatch.exists)
        shot(app, "workflow-records-collapsed")
        app.buttons["record-time-metric"].tap(); app.buttons["record-time-toggle-chart"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["record-time-empty"].firstMatch.exists)
        app.buttons["record-time-metric"].tap(); app.buttons["训练总用时"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["record-time-chart"].firstMatch.exists)
        app.buttons["tab-3"].tap()
        XCTAssertTrue(app.buttons["trend-exercise-filter"].label.contains("深蹲"))
        XCTAssertTrue(app.buttons["trend-period-filter"].label.contains("全部时间"))
        XCTAssertTrue(app.buttons["trend-metric"].label.contains("次数"))
        XCTAssertEqual(app.buttons["trend-metric"].value as? String, "按月")
        XCTAssertFalse(app.descendants(matching: .any)["trend-chart"].firstMatch.exists)
        app.buttons["trend-metric"].tap(); app.buttons["trend-toggle-chart"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["trend-chart"].firstMatch.exists)
        shot(app, "workflow-preferences-restored")
    }
    @MainActor func testChartClearAndReturnRange() {
        let app = launch("m2-real-review")
        let chart = app.descendants(matching: .any)["record-time-chart"].firstMatch
        let total = app.staticTexts["record-time-value"].label
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["record-time-clear-selection"].waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.staticTexts["record-time-value"].label, total)
        shot(app, "interactions-clear-selection")
        app.buttons["record-time-clear-selection"].tap()
        XCTAssertEqual(app.staticTexts["record-time-value"].label, total)
        XCTAssertTrue(app.staticTexts["82 条记录"].exists)
        XCTAssertFalse(app.buttons["record-time-open-day"].exists)
        XCTAssertEqual(app.buttons["record-time-metric"].value as? String, "按月")
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        app.buttons["record-time-open-day"].tap()
        XCTAssertTrue(app.staticTexts["6 条记录"].waitForExistence(timeout: 5))
        shot(app, "interactions-return-range")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["record-return-range"].waitForExistence(timeout: 10))
        app.buttons["record-return-range"].tap()
        XCTAssertTrue(app.staticTexts["82 条记录"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["record-return-range"].exists)
        app.buttons["record-exercise-filter"].tap(); app.buttons["卧推"].tap()
        app.buttons["record-period-filter"].tap(); app.buttons["近30天"].tap()
        XCTAssertTrue(app.staticTexts["5 条记录"].waitForExistence(timeout: 5))
        app.buttons["tab-3"].tap()
        app.buttons["trend-metric"].tap(); app.buttons["trend-granularity-week"].tap()
        app.buttons["trend-open-day"].tap()
        XCTAssertTrue(app.staticTexts["4 条记录"].waitForExistence(timeout: 5))
        app.buttons["record-return-range"].tap()
        XCTAssertTrue(app.staticTexts["5 条记录"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["record-exercise-filter"].label.contains("卧推"))
        XCTAssertTrue(app.buttons["record-period-filter"].label.contains("近30天"))
        app.buttons["tab-3"].tap(); app.buttons["trend-open-day"].tap()
        app.buttons["record-period-filter"].tap(); app.buttons["全部时间"].tap()
        XCTAssertTrue(app.staticTexts["78 条记录"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["record-return-range"].exists, "Manual filtering ends the drill-down context")
    }
    @MainActor func testEditorFirstErrorFocus() {
        let app = launch("first-error-" + UUID().uuidString)
        app.buttons["add-record"].tap()
        let first = app.textFields["record-set-1-weight-field"]
        fill(first, "600"); app.buttons["下一项"].tap(); app.typeText("8"); app.buttons["完成"].tap()
        app.buttons["add-record-set"].tap()
        fill(app.textFields["record-set-2-weight-field"], "42.5")
        XCTAssertEqual(app.textFields["record-set-2-weight-field"].value as? String, "42.5")
        app.buttons["下一项"].tap(); app.typeText("0"); app.buttons["完成"].tap()
        for _ in 3...10 {
            app.buttons["add-record-set"].tap(); app.typeText("6"); app.buttons["完成"].tap()
        }
        app.scrollViews["record-editor-scroll"].swipeUp()
        XCTAssertFalse(first.isHittable, "The first error starts outside the viewport")
        app.buttons["save-record"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(first.isHittable)
        XCTAssertEqual(first.value as? String, "600")
        shot(app, "interactions-first-error")
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "42.5")
        XCTAssertEqual(first.value as? String, "42.5", "Typing after invalid save targets the first bad field")
        app.buttons["save-record"].tap()
        let second = app.textFields["record-set-2-reps-field"]
        XCTAssertTrue(second.isHittable)
        app.typeText(XCUIKeyboardKey.delete.rawValue + "6")
        XCTAssertEqual(second.value as? String, "6")
        app.buttons["完成"].tap(); app.buttons["save-record"].tap()
        XCTAssertTrue(app.staticTexts["1 条记录"].waitForExistence(timeout: 5))
        app.buttons["history-record"].firstMatch.tap()
        XCTAssertEqual(app.descendants(matching: .any)["record-total-reps"].value as? String, "62 次")
    }
    @MainActor func testBackupSavedConfirmation() {
        let app = launch("m2-real-review")
        app.buttons["tab-2"].tap()
        app.buttons["records-backup"].tap()
        XCTAssertTrue(app.buttons["保存"].waitForExistence(timeout: 10))
        let name = app.textFields.firstMatch
        if name.exists { fill(name, "PowerReps-Proof-" + String(UUID().uuidString.prefix(8))) }
        app.buttons["保存"].tap()
        let last = app.staticTexts["records-backup-last-success"]
        XCTAssertTrue(last.waitForExistence(timeout: 10))
        let savedLabel = last.label
        shot(app, "interactions-backup-confirmed")
        app.terminate(); app.launch(); app.buttons["tab-2"].tap()
        XCTAssertTrue(last.waitForExistence(timeout: 10))
        XCTAssertEqual(last.label, savedLabel)
    }
    @MainActor func testBackupCancelAndCSV() {
        let app = launch("m2-real-review")
        app.buttons["tab-2"].tap()
        let last = app.staticTexts["records-backup-last-success"]
        XCTAssertTrue(last.waitForExistence(timeout: 5), "Run after an actual successful backup")
        let savedLabel = last.label
        app.buttons["records-backup"].tap()
        XCTAssertTrue(app.buttons["保存"].waitForExistence(timeout: 10))
        if !app.buttons["取消"].exists && app.buttons["浏览"].exists { app.buttons["浏览"].tap() }
        shot(app, "interactions-backup-cancel-picker")
        XCTAssertTrue(app.buttons["取消"].waitForExistence(timeout: 10))
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["records-backup"].waitForExistence(timeout: 5))
        XCTAssertEqual(last.label, savedLabel)
        app.buttons["records-export"].tap(); app.buttons["训练汇总 CSV"].tap()
        XCTAssertTrue(app.buttons["保存"].waitForExistence(timeout: 10))
        let name = app.textFields.firstMatch
        if name.exists { fill(name, "PowerReps-CSV-Proof-" + String(UUID().uuidString.prefix(8))) }
        app.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["records-backup"].waitForExistence(timeout: 10))
        XCTAssertEqual(last.label, savedLabel)
        shot(app, "interactions-backup-unchanged-after-csv")
    }
    @MainActor func testReturnRangeLargeEnglish() {
        let app = launch("m2-real-review", dark: true, englishLarge: true)
        app.buttons["tab-3"].tap()
        let open = app.buttons["trend-open-day"]
        for _ in 0..<3 { if !open.isHittable { app.swipeUp() } }
        open.tap()
        let back = app.buttons["record-return-range"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(back.isHittable)
        shot(app, "interactions-return-range-large-english")
        back.tap()
        XCTAssertTrue(app.staticTexts["82 records"].waitForExistence(timeout: 5))
    }
    @MainActor func testM2NativeWalkthrough() {
        let app = launch("m2-tour-review")
        XCTAssertTrue(app.staticTexts["82 条记录"].exists)
        shot(app, "m2-tour-records")
        app.buttons["tab-3"].tap()
        shot(app, "m2-tour-trends")
        app.buttons["trend-metric"].tap(); app.buttons["次数"].firstMatch.tap()
        let chart = app.descendants(matching: .any)["trend-chart"].firstMatch
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        app.buttons["tab-1"].tap(); app.buttons["add-record"].tap()
        let weight = app.textFields["重量（公斤）"].firstMatch
        weight.tap(); app.buttons["下一项"].tap(); app.typeText("8")
        app.buttons["完成"].tap()
        app.buttons["add-record-set"].tap(); app.typeText("6")
        app.buttons["完成"].tap()
        shot(app, "m2-tour-entry")
        XCTAssertTrue(app.buttons["save-record"].isHittable)
        app.buttons["取消"].tap(); app.buttons["放弃修改"].tap()
    }

}
