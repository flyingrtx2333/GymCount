import XCTest
final class WeightEntryNativeTests: XCTestCase {
 @MainActor private func field(_ app: XCUIApplication) -> XCUIElement {
  app.textFields.matching(identifier: "weight-input-value").element(boundBy: 0)
 }
 // watchOS 27 can omit value in firstMatch's attribute cache. Match the
 // live accessibility snapshot rather than weakening the expected value.
 @MainActor private func assertValue(_ value: String,_ app: XCUIApplication) {
  let match=app.textFields.matching(NSPredicate(format:"identifier == %@ AND value == %@","weight-input-value",value)).element(boundBy:0)
  XCTAssertTrue(match.waitForExistence(timeout:5))
 }
 @MainActor private func shot(_ app: XCUIApplication,_ name: String) {
  let a=XCTAttachment(screenshot: app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)
  let tree=XCTAttachment(string: app.debugDescription);tree.name=name+"-AX";tree.lifetime = .keepAlways;add(tree)
  let system=XCUIApplication(bundleIdentifier: "com.apple.Carousel");let t=XCTAttachment(string: system.debugDescription);t.name=name+"-system-AX";t.lifetime = .keepAlways;add(t)
 }
 @MainActor private func enter(_ text: String,_ app: XCUIApplication,english: Bool) {
  field(app).tap();shot(app,"native-keyboard-open")
  app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,count: 12)+text)
  shot(app,"native-keyboard-entered")
  let done=app.buttons.matching(NSPredicate(format: "label IN %@", ["Done", "完成"])).firstMatch
  XCTAssertTrue(done.waitForExistence(timeout: 5));done.tap()
  XCTAssertTrue(app.buttons.matching(identifier: "weight-input-save").element(boundBy: 0).waitForExistence(timeout: 6))
 }
 @MainActor func testSettingsBoundsAndCancel() {
  continueAfterFailure=false
  let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(en)","-AppleLocale","en_US"];app.launch()
  XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 12));app.buttons["Settings"].tap()
  let body=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","My Weight")).firstMatch
  XCTAssertTrue(body.waitForExistence(timeout: 6));body.tap();enter("201",app,english:true)
  XCTAssertFalse(app.buttons.matching(identifier: "weight-input-save").element(boundBy: 0).isEnabled)
  shot(app,"weight-body-range-error");app.buttons.matching(identifier: "weight-input-back").element(boundBy: 0).tap()
  XCTAssertTrue(body.label.contains("70"));body.tap();enter("72.25",app,english:true)
  app.buttons.matching(identifier: "weight-input-save").element(boundBy: 0).tap();XCTAssertTrue(body.label.contains("72.25"))
  shot(app,"weight-settings-decimal")
  app.buttons.matching(identifier: "watch.back").element(boundBy: 0).tap();app.buttons["Settings"].tap()
  XCTAssertTrue(body.label.contains("70"));XCTAssertFalse(body.label.contains("72.25"))
 }
 @MainActor func testEnglishDirectEntry() { run(english: true) }
 @MainActor func testChineseDirectEntry() { run(english: false) }
 @MainActor private func run(english: Bool) {
  continueAfterFailure=false
  let app=XCUIApplication();app.launchArguments=["-AppleLanguages",english ? "(en)" : "(zh-Hans)","-AppleLocale",english ? "en_US" : "zh_CN"]
  addUIInterruptionMonitor(withDescription: "Preview notification prompt") { alert in
   for n in ["不允许","Don’t Allow","Don't Allow"] {if alert.buttons[n].exists {alert.buttons[n].tap();return true}};return false
  }
  app.launch()
  let system=XCUIApplication(bundleIdentifier: "com.apple.Carousel")
  for n in ["不允许","Don’t Allow","Don't Allow"] {if system.alerts.buttons[n].waitForExistence(timeout: 1) {system.alerts.buttons[n].tap()}}
  XCTAssertTrue(app.buttons["workout.start.bench_press"].waitForExistence(timeout: 12));app.buttons["workout.start.bench_press"].tap()
  let currentWeight = (app.buttons[english ? "Edit Equipment Weight" : "修改器械重量"].value as? String)?.components(separatedBy: " ").first
  XCTAssertNotNil(currentWeight)
  app.buttons[english ? "Edit Equipment Weight" : "修改器械重量"].tap()
  XCTAssertTrue(field(app).waitForExistence(timeout: 6));shot(app,english ? "weight-entry-en-initial" : "weight-entry-zh-initial")
  assertValue(currentWeight!,app)
  enter("72.25",app,english: english)
  assertValue("72.25",app);shot(app,english ? "weight-entry-en-decimal" : "weight-entry-zh-decimal")
  app.buttons["weight-step-plus"].tap()
  assertValue("74.75",app)
  app.buttons.matching(identifier: "weight-input-save").element(boundBy: 0).tap()
  XCTAssertTrue(app.buttons[english ? "Edit Equipment Weight" : "修改器械重量"].waitForExistence(timeout: 5))
  app.buttons[english ? "Edit Equipment Weight" : "修改器械重量"].tap()
  assertValue("74.75",app)
  enter("-1",app,english: english)
  XCTAssertTrue(app.descendants(matching:.any)["weight-input-error"].firstMatch.exists)
  XCTAssertFalse(app.buttons.matching(identifier: "weight-input-save").element(boundBy: 0).isEnabled)
  enter("72.25x",app,english: english)
  XCTAssertFalse(app.buttons.matching(identifier: "weight-input-save").element(boundBy: 0).isEnabled);shot(app,english ? "weight-entry-en-invalid" : "weight-entry-zh-invalid")
  app.buttons.matching(identifier: "weight-input-back").element(boundBy: 0).tap()
  app.buttons[english ? "Edit Equipment Weight" : "修改器械重量"].tap()
  assertValue("74.75",app)
  app.buttons.matching(identifier: "weight-input-back").element(boundBy: 0).tap()
  app.buttons["workout.end"].tap()
  if app.buttons["workout.saved.close"].waitForExistence(timeout: 3) {app.buttons["workout.saved.close"].tap()}
 }
}
