import XCTest

// Uses the original 82-record local snapshot, copied into isolated storage
// before launch. No generated workouts or manufactured set data are used.
final class TrainingInsightsTests: XCTestCase {
    @MainActor private func launch(english: Bool = false, dark: Bool = false, large: Bool = false, reset: Bool = true) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--isolated-ui-test", "--ui-test-storage-id=insights-real82",
                               "-AppleLanguages", english ? "(en)" : "(zh-Hans)", "-AppleLocale", english ? "en_US" : "zh_CN",
                               "-records.appearance", dark ? "dark" : "light"]
        if reset { app.launchArguments.append("--reset-record-view-preferences") }
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-UIAccessibilityReduceMotionEnabled", "YES"] }
        app.launch()
        XCTAssertTrue(app.recordTab(3).waitForExistence(timeout: 15))
        app.recordTab(3).tap()
        XCTAssertTrue(element("insights-records", app).waitForExistence(timeout: 8))
        return app
    }

    @MainActor private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @MainActor private func reveal(_ item: XCUIElement, _ app: XCUIApplication, fromBelow: Bool = false) {
        for _ in 0..<18 {
            let lower = app.recordTab(1).frame.minY - 8
            let upper: CGFloat = 120
            let exists = item.exists
            let frame = exists ? item.frame : .zero
            if exists, item.isHittable, frame.minY >= upper, frame.maxY <= lower { return }
            let down = fromBelow || (exists && frame.minY < upper)
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.52, dy: down ? 0.32 : 0.77))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.52, dy: down ? 0.77 : 0.32))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertTrue(item.isHittable, "The control must be reachable")
        XCTAssertLessThanOrEqual(item.frame.maxY, app.recordTab(1).frame.minY - 4, "The bottom bar must not cover the control")
    }

    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        // Native page transitions last 0.32 seconds; capture the settled layout.
        Thread.sleep(forTimeInterval: 0.5)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-AX"; tree.lifetime = .keepAlways; add(tree)
    }

    @MainActor private func assertValue(_ id: String, _ expected: String, _ app: XCUIApplication) {
        let item = element(id, app)
        XCTAssertTrue(item.exists)
        XCTAssertEqual(item.value as? String, expected)
    }

    @MainActor private func assertHeader(_ app: XCUIApplication, inline: Bool) {
        let title = element("trend-heading", app)
        let exercise = app.buttons["trend-exercise-filter"]
        let period = app.buttons["trend-period-filter"]
        XCTAssertTrue(title.isHittable && exercise.isHittable && period.isHittable)
        XCTAssertEqual(title.frame.minX, 16, accuracy: 2)
        XCTAssertEqual(period.frame.maxX, app.frame.maxX - 16, accuracy: 2)
        XCTAssertGreaterThanOrEqual(exercise.frame.height, 44)
        XCTAssertGreaterThanOrEqual(period.frame.height, 44)
        XCTAssertGreaterThanOrEqual(exercise.frame.minX, 14)
        XCTAssertLessThanOrEqual(exercise.frame.maxX, app.frame.maxX - 14)
        if inline {
            XCTAssertEqual(title.frame.midY, exercise.frame.midY, accuracy: 2)
            XCTAssertEqual(title.frame.midY, period.frame.midY, accuracy: 2)
            XCTAssertLessThan(title.frame.maxX, exercise.frame.minX)
            XCTAssertLessThan(exercise.frame.maxX, period.frame.minX)
        }
    }

    @MainActor func testCompactHeaderAndExerciseSelection() {
        let app = launch(dark: true)
        assertHeader(app, inline: true)
        shot(app, "trend-header-inline-dark")
        let titleX = element("trend-heading", app).frame.minX
        let right = app.buttons["trend-period-filter"].frame.maxX
        for exercise in ["卧推", "深蹲", "全部动作"] {
            app.buttons["trend-exercise-filter"].tap()
            app.buttons[exercise].firstMatch.tap()
            assertHeader(app, inline: true)
            XCTAssertEqual(element("trend-heading", app).frame.minX, titleX, accuracy: 1)
            XCTAssertEqual(app.buttons["trend-period-filter"].frame.maxX, right, accuracy: 1)
            shot(app, "trend-header-selected-" + exercise)
        }
        app.buttons["trend-period-filter"].tap(); app.buttons["近30天"].tap()
        assertHeader(app, inline: true)
        XCTAssertTrue(app.buttons["trend-period-filter"].label.contains("30"))
        shot(app, "trend-header-30days")
    }

    @MainActor func testHeaderEnglishAndLargeType() {
        var app = launch(english: true)
        assertHeader(app, inline: true)
        app.buttons["trend-exercise-filter"].tap(); app.buttons["Bench Press"].firstMatch.tap()
        assertHeader(app, inline: true)
        shot(app, "trend-header-compact-english")
        app.buttons["trend-period-filter"].tap(); app.buttons["Custom dates"].tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(element("trend-custom-range", app).waitForExistence(timeout: 5))
        assertHeader(app, inline: true)
        shot(app, "trend-header-custom-range-english")
        app.terminate()
        app = launch(english: true, large: true)
        assertHeader(app, inline: false)
        app.buttons["trend-exercise-filter"].tap(); app.buttons["Bench Press"].firstMatch.tap()
        assertHeader(app, inline: false)
        shot(app, "trend-header-accessibility-english")
    }

    @MainActor private func assertRootTitles(_ app: XCUIApplication, prefix: String, large: Bool = false) {
        var reference: CGRect?
        for (tab, title) in [(1, "records-heading"), (3, "trend-heading"), (2, "settings-heading")] {
            app.buttons["tab-\(tab)"].tap()
            let heading = app.staticTexts[title]
            XCTAssertTrue(heading.waitForExistence(timeout: 5))
            XCTAssertTrue(heading.isHittable)
            XCTAssertEqual(heading.frame.minX, 16, accuracy: 1)
            XCTAssertLessThanOrEqual(heading.frame.maxX, app.frame.maxX - 16)
            if let reference {
                XCTAssertEqual(heading.frame.minY, reference.minY, accuracy: 1)
                if !large { XCTAssertEqual(heading.frame.height, reference.height, accuracy: 1) }
            } else { reference = heading.frame }
            shot(app, prefix + "-" + title)
        }
    }

    @MainActor func testUnifiedPageHeadersAndNavigation() {
        let app = launch(dark: true)
        assertRootTitles(app, prefix: "unified-dark")
        let help = app.buttons["使用帮助"]
        reveal(help, app); help.tap()
        XCTAssertTrue(app.navigationBars["使用帮助"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["settings-heading"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["设置"].exists)
        let sync = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "手表同步", "history-sync-workouts")).firstMatch
        reveal(sync, app, fromBelow: true); sync.tap()
        XCTAssertTrue(app.buttons["sync-now"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["settings-heading"].waitForExistence(timeout: 5))
        app.recordTab(1).tap()
        app.buttons["record-select"].tap(); app.buttons["record-select"].tap()
        XCTAssertTrue(app.buttons["add-record"].isHittable)
        app.buttons["add-record"].tap()
        XCTAssertTrue(app.navigationBars["补记训练"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        XCTAssertTrue(app.staticTexts["records-heading"].waitForExistence(timeout: 5))
    }

    @MainActor func testUnifiedPageHeadersEnglishAndAccessibility() {
        var app = launch(english: true)
        assertRootTitles(app, prefix: "unified-compact-english")
        app.terminate()
        app = launch(english: true, large: true)
        assertRootTitles(app, prefix: "unified-accessibility-english", large: true)
        let help = app.buttons["Help"]
        reveal(help, app); help.tap()
        XCTAssertTrue(app.navigationBars["Help"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["settings-heading"].waitForExistence(timeout: 5))
    }

    @MainActor func testVisualSystemContentAndEditor() {
        let app = launch()
        let missing = element("trend-empty", app)
        reveal(missing, app)
        XCTAssertLessThanOrEqual(missing.frame.height, 88, "A missing local measurement must remain compact")
        shot(app, "system-trends-compact-state-light")
        app.recordTab(1).tap()
        shot(app, "system-records-light")
        app.buttons["history-record"].firstMatch.tap()
        XCTAssertTrue(element("record-total-reps", app).waitForExistence(timeout: 5))
        shot(app, "system-detail-metric-units-light")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["add-record"].tap()
        let save = app.buttons["save-record"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(save.frame.height, 44)
        shot(app, "system-editor-light")
        app.textFields.firstMatch.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isHittable)
        shot(app, "system-editor-keyboard-light")
        app.buttons["取消"].tap()
        XCTAssertTrue(app.staticTexts["records-heading"].waitForExistence(timeout: 5))
        app.recordTab(2).tap()
        shot(app, "system-settings-light")
        app.buttons["records-backup"].tap()
        XCTAssertTrue(app.buttons["保存"].waitForExistence(timeout: 10))
        shot(app, "system-native-file-export")
        if !app.buttons["取消"].exists && app.buttons["浏览"].exists { app.buttons["浏览"].tap() }
        XCTAssertTrue(app.buttons["取消"].waitForExistence(timeout: 10))
        app.buttons["取消"].firstMatch.tap()
        XCTAssertTrue(app.buttons["records-backup"].waitForExistence(timeout: 10))
    }

    @MainActor func testAllActivityCalendarAndFilter() {
        let app = launch()
        XCTAssertTrue(app.buttons["trend-exercise-filter"].label.contains("全部动作"))
        XCTAssertTrue(app.buttons["trend-period-filter"].label.contains("全部时间"))
        assertValue("insights-records", "82 条", app)
        assertValue("insights-reps", "323 次", app)
        assertValue("insights-days", "12 天", app)
        XCTAssertEqual(element("insights-duration", app).value as? String, "—", "Elapsed session time must not stand in for missing action timing")
        shot(app, "insights-overview-real82-light")

        let heatmap = element("trend-training-heatmap", app)
        reveal(app.buttons["trend-heatmap-date"], app)
        // Select a different original workout day from the default latest day
        // (Friday, 9 October 2026), using the production grid scale.
        var calendar = Calendar.current
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: Date())
        let first = calendar.date(byAdding: .day, value: -363, to: today)!
        let monday = calendar.date(byAdding: .day, value: -(calendar.component(.weekday, from: first) + 5) % 7, to: first)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9))!
        let offset = calendar.dateComponents([.day], from: monday, to: day).day!
        let target = CGPoint(x: heatmap.frame.minX + CGFloat(offset / 7) * 18 + 7,
                             y: heatmap.frame.minY + 22 + CGFloat(offset % 7) * 18 + 7)
        XCTAssertTrue(app.frame.contains(target))
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: target.x, dy: target.y)).tap()
        XCTAssertTrue((app.buttons["trend-heatmap-date"].value as? String ?? "").contains("10月9日"))
        XCTAssertTrue(app.buttons["trend-heatmap-open-day"].isEnabled)
        shot(app, "insights-calendar-real-selected")
        app.buttons["trend-heatmap-open-day"].tap()
        XCTAssertTrue(app.buttons["history-record"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["record-period-filter"].label.contains("自定义"))
        shot(app, "insights-calendar-day-records")
        app.recordTab(3).tap()

        let squat = element("insights-exercise-squat", app)
        reveal(squat, app); squat.tap()
        let overview = element("insights-records", app)
        reveal(overview, app, fromBelow: true)
        assertValue("insights-records", "4 条", app)
        assertValue("insights-reps", "0 次", app)
        XCTAssertTrue(app.buttons["trend-exercise-filter"].label.contains("深蹲"))
        shot(app, "insights-squat-filter-linked")
        // These original squat summaries contain zero reps. An empty donut
        // must stay valid when changing both the filter and distribution metric.
        let distributionMetric = app.buttons["insights-exercise-metric"]
        reveal(distributionMetric, app); distributionMetric.tap()
        app.buttons["按动作次数"].tap()
        XCTAssertTrue(element("insights-exercise-squat", app).exists)
        shot(app, "insights-zero-rep-squat-distribution")
        app.terminate()
        let relaunched = launch(reset: false)
        assertValue("insights-records", "82 条", relaunched)
        XCTAssertTrue(relaunched.buttons["trend-exercise-filter"].label.contains("全部动作"))
    }

    @MainActor func testDarkAndEnglishAccessibility() {
        var app = launch(dark: true)
        assertValue("insights-records", "82 条", app)
        shot(app, "insights-overview-dark")
        reveal(app.buttons["trend-heatmap-date"], app)
        shot(app, "insights-calendar-dark")
        app.terminate()
        app = launch(english: true, large: true)
        XCTAssertTrue((element("insights-records", app).value as? String ?? "").contains("82"))
        shot(app, "insights-overview-english-accessibility")
        reveal(app.buttons["trend-heatmap-date"], app)
        shot(app, "insights-calendar-english-accessibility")
        app.buttons["trend-heatmap-date"].tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        shot(app, "insights-calendar-picker-english-accessibility")
        app.buttons["Done"].tap()
        reveal(element("insights-exercise-bench_press", app), app)
        shot(app, "insights-exercises-english-accessibility")
        reveal(app.buttons["insights-weight-70"], app)
        app.buttons["insights-weight-70"].tap()
        XCTAssertTrue(app.buttons["insights-weight-70"].isSelected)
        shot(app, "insights-weight-english-accessibility")
    }

    @MainActor func testCompactWeightAndPeriod() {
        let app = launch(english: true)
        shot(app, "insights-overview-small-english")
        let weight = app.buttons["insights-weight-70"]
        reveal(weight, app)
        XCTAssertFalse(app.buttons["insights-weight-0"].exists)
        XCTAssertTrue((weight.value as? String ?? "").contains("73"))
        weight.tap()
        XCTAssertTrue(weight.isSelected)
        shot(app, "insights-weights-small-selected")
        reveal(element("insights-exercise-bench_press", app), app)
        element("insights-exercise-bench_press", app).tap()
        reveal(element("insights-records", app), app, fromBelow: true)
        XCTAssertTrue((element("insights-records", app).value as? String ?? "").contains("78"))
        app.buttons["trend-period-filter"].tap(); app.buttons["Last 30 days"].tap()
        XCTAssertTrue((element("insights-records", app).value as? String ?? "").contains("5"))
        XCTAssertTrue((element("insights-reps", app).value as? String ?? "").contains("15"))
        shot(app, "insights-small-filtered-period")
    }

    @MainActor func testFinalCalendarPresentation() {
        let app = launch()
        shot(app, "insights-final-overview-calendar-light")
        let date = app.buttons["trend-heatmap-date"]
        reveal(date, app)
        let value = date.value as? String
        let calendar = element("trend-training-heatmap", app)
        let middleY = calendar.frame.minY + 94
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: 100, dy: middleY)).press(forDuration: 0.05,
            thenDragTo: origin.withOffset(CGVector(dx: 350, dy: middleY)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertEqual(date.value as? String, value, "Horizontal panning must keep the inspected day")
        shot(app, "insights-final-calendar-panned")
        let range = app.buttons["trend-heatmap-range"]
        range.tap(); app.buttons["2025"].tap()
        XCTAssertTrue(range.label.contains("2025"))
        XCTAssertTrue((date.value as? String ?? "").contains("2025"))
        shot(app, "insights-final-calendar-2025")
        range.tap(); app.buttons["近一年"].tap()
        assertValue("insights-records", "82 条", app)
        shot(app, "insights-final-calendar-latest")
        let weight = app.buttons["insights-weight-70"]
        reveal(weight, app); weight.tap()
        reveal(weight, app)
        XCTAssertTrue(weight.isSelected)
        shot(app, "insights-final-exercise-weight-distributions")
    }

    @MainActor func testTrendFilterSwitching() {
        let app = launch(dark: true)
        let metric = app.buttons["trend-metric"]
        reveal(metric, app)
        metric.tap(); app.buttons["trend-metric-reps"].tap()
        for (exercise, count) in [("卧推", "78 条"), ("深蹲", "4 条"), ("全部动作", "82 条")] {
            app.buttons["trend-exercise-filter"].tap(); app.buttons[exercise].firstMatch.tap()
            assertValue("insights-records", count, app)
        }
        for value in ["weight", "elapsed", "active", "reps"] {
            reveal(metric, app); metric.tap(); app.buttons["trend-metric-" + value].tap()
            if value == "weight" {
                XCTAssertTrue((element("trend-summary-value", app).value as? String ?? "").contains("70"))
            } else if value == "active" {
                assertValue("trend-summary-value", "—", app)
                XCTAssertTrue(element("trend-empty", app).exists)
            } else {
                XCTAssertTrue(element("trend-chart", app).exists)
            }
            XCTAssertTrue(app.recordTab(2).isHittable)
        }
        for period in ["近30天", "近90天", "全部时间"] {
            app.buttons["trend-period-filter"].tap()
            app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", period, "trend-period-filter")).firstMatch.tap()
            XCTAssertTrue(app.buttons["trend-period-filter"].label.contains(period))
        }
        for grouping in ["day", "week", "month"] {
            reveal(metric, app); metric.tap(); app.buttons["trend-granularity-" + grouping].tap()
        }
        let distribution = app.buttons["insights-exercise-metric"]
        for type in ["按动作次数", "按记录数"] {
            reveal(distribution, app); distribution.tap(); app.buttons[type].tap()
        }
        app.buttons["trend-exercise-filter"].tap(); app.buttons["硬拉"].firstMatch.tap()
        XCTAssertTrue(element("trend-empty", app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("trend-chart", app).exists)
        app.buttons["trend-exercise-filter"].tap(); app.buttons["全部动作"].firstMatch.tap()
        assertValue("insights-records", "82 条", app)
        assertValue("insights-reps", "323 次", app)
        XCTAssertTrue(element("trend-chart", app).exists)
        shot(app, "performance-final-trend-filters")
        app.recordTab(2).tap()
        XCTAssertTrue(app.staticTexts["settings-heading"].isHittable)
    }

    @MainActor func testDailyChartPanAndScrollToBottom() {
        let app = launch(dark: true)
        let menu = app.buttons["trend-metric"]
        reveal(menu, app)
        menu.tap(); app.buttons["trend-metric-reps"].tap()
        menu.tap(); app.buttons["trend-granularity-day"].tap()
        let chart = element("trend-chart", app)
        reveal(chart, app)
        shot(app, "repair-daily-reps-latest-dark")
        let range = chart.value as? String
        let start = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        let end = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertNotEqual(chart.value as? String, range, "A daily chart spanning a year must pan instead of squeezing every day into one pixel")
        shot(app, "repair-daily-reps-panned-dark")
        let beforeY = chart.frame.minY
        let center = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let up = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: chart.frame.midX, dy: chart.frame.midY - 130))
        center.press(forDuration: 0.05, thenDragTo: up, withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertLessThan(chart.frame.minY, beforeY - 40, "A vertical swipe starting on the chart must scroll the page")
        let footer = element("trend-breakdown-disclosure", app)
        reveal(footer, app); footer.tap()
        for _ in 0..<8 { app.swipeUp() }
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "trend-breakdown-")).allElementsBoundByIndex
        let lastID = rows.filter { $0.identifier != "trend-breakdown-disclosure" }.last!.identifier
        shot(app, "repair-trends-last-row-reachable")
        let last = app.buttons.matching(identifier: lastID).firstMatch
        XCTAssertTrue(last.isHittable)
        XCTAssertGreaterThanOrEqual(last.frame.minY, 120)
        XCTAssertLessThanOrEqual(last.frame.maxY, app.recordTab(1).frame.minY - 4)
        last.tap()
        XCTAssertTrue(app.buttons["history-record"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.recordTab(1).isSelected, "The oldest summary must open its actual records")
        shot(app, "repair-trends-oldest-day-opened")
    }

    @MainActor func testStableChartHeightWithRealSyncedHistory() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--isolated-ui-test", "--ui-test-storage-id=sync-repair-real127",
            "--reset-record-view-preferences", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-records.appearance", "dark"]
        app.launch()
        XCTAssertTrue(app.recordTab(3).waitForExistence(timeout: 15))
        app.recordTab(3).tap()
        let menu = app.buttons["trend-metric"]
        reveal(menu, app)
        menu.tap(); app.buttons["trend-metric-active"].tap()
        let chart = element("trend-chart", app)
        XCTAssertTrue(chart.waitForExistence(timeout: 5), "Install actual history with known training durations")
        reveal(chart, app)
        let expected = chart.frame.height
        XCTAssertEqual(expected, 156, accuracy: 1)
        for grouping in ["month", "week", "day"] {
            reveal(menu, app); menu.tap(); app.buttons["trend-granularity-" + grouping].tap()
            reveal(chart, app)
            XCTAssertEqual(chart.frame.height, expected, accuracy: 1, "Data aggregation changed chart height")
            shot(app, "stable-duration-chart-" + grouping)
        }
        for exercise in ["卧推", "深蹲", "全部动作"] {
            app.buttons["trend-exercise-filter"].tap(); app.buttons[exercise].firstMatch.tap()
            reveal(chart, app)
            XCTAssertEqual(chart.frame.height, expected, accuracy: 1, "Exercise data changed chart height")
        }
        let range = chart.value as? String
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).press(forDuration: 0.05,
            thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)),
            withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertNotEqual(chart.value as? String, range)
        XCTAssertEqual(chart.frame.height, expected, accuracy: 1)
        shot(app, "stable-duration-chart-panned")
    }
}
