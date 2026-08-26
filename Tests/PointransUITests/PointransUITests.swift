import XCTest

@MainActor
final class PointransUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testControlCenterAndPermissionsNavigation() throws {
        let app = launch(scenario: "control-center")
        XCTAssertTrue(app.staticTexts["Pointrans"].waitForExistence(timeout: 3))
        XCTAssertTrue(element("translation-toggle", in: app).exists)

        app.buttons["permissions-page-button"].click()
        XCTAssertTrue(app.staticTexts["Accessibility"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Screen Recording"].exists)
        XCTAssertTrue(app.buttons["permissions-done-button"].exists)
    }

    func testPreviewPinsAndShowsStructuredInsight() throws {
        let app = launch(scenario: "ai-success")
        XCTAssertTrue(element("translation-preview", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["pulling"].exists)

        app.buttons["context-insight-button"].click()
        XCTAssertTrue(element("translation-pinned", in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Understanding this context…"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["持续拉扯"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["On-device"].exists)
    }

    func testContextFailureIsRecoverableAndPinnedCanClose() throws {
        let app = launch(scenario: "ai-failure")
        XCTAssertTrue(element("translation-preview", in: app).waitForExistence(timeout: 3))
        app.buttons["context-insight-button"].click()
        XCTAssertTrue(app.staticTexts["Context insight is temporarily unavailable."].waitForExistence(timeout: 3))
        app.buttons["close-pinned-button"].click()
        XCTAssertFalse(element("translation-pinned", in: app).waitForExistence(timeout: 1))
    }

    func testControlCenterFollowsChineseAndDarkAppearance() throws {
        let app = launch(scenario: "control-center", language: "zh-Hans", dark: true)
        XCTAssertTrue(app.staticTexts["光标翻译"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["permissions-page-button"].exists)
        XCTAssertTrue(element("translation-toggle", in: app).exists)
    }

    private func launch(scenario: String, language: String = "en", dark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-AppleLanguages", "(\(language))"]
        if dark { app.launchArguments += ["-AppleInterfaceStyle", "Dark"] }
        app.launchEnvironment["POINTRANS_UI_TEST_SCENARIO"] = scenario
        app.launch()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
