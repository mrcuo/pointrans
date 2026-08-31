import XCTest

@MainActor
final class PointransUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testControlCenterContainsOnlyLockedProductControls() throws {
        let app = launch(scenario: "control-center")
        XCTAssertTrue(element("control-center-main", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Hold Left Option and hover"].exists)
        XCTAssertTrue(app.staticTexts["English and Chinese are detected automatically"].exists)
        XCTAssertTrue(element("translation-toggle", in: app).exists)
        XCTAssertTrue(element("hover-delay-slider", in: app).exists)

        XCTAssertFalse(app.staticTexts["Trigger key"].exists)
        XCTAssertFalse(app.staticTexts["Direction"].exists)
        XCTAssertFalse(app.staticTexts["Provider"].exists)
        XCTAssertFalse(app.staticTexts["API Key"].exists)
    }

    func testMissingEitherRequiredPermissionIsVisibleInControlCenter() throws {
        let app = launch(scenario: "permissions")
        XCTAssertTrue(element("control-center-main", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Accessibility"].exists)
        XCTAssertTrue(app.staticTexts["Screen Recording"].exists)
        XCTAssertGreaterThanOrEqual(app.buttons.matching(identifier: "Open Settings").count, 2)
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
        XCTAssertTrue(app.staticTexts["The explanation is temporarily unavailable."].waitForExistence(timeout: 3))
        app.buttons["close-pinned-button"].click()
        XCTAssertFalse(element("translation-pinned", in: app).waitForExistence(timeout: 1))
    }

    func testOnboardingStartsWithAVisibleStatusItemAndExit() throws {
        let app = launch(scenario: "onboarding")
        XCTAssertTrue(element("pointrans-onboarding-window", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Quit Pointrans"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["_XCUI:CloseWindow"].waitForExistence(timeout: 2))
        let statusItem = element("pointrans-menu-bar-button", in: app)
        XCTAssertTrue(statusItem.waitForExistence(timeout: 2))
        XCTAssertGreaterThan(statusItem.frame.width, 70)
        XCTAssertGreaterThan(statusItem.frame.height, 20)

        let optionBadge = element("welcome-left-option-badge", in: app)
        XCTAssertTrue(optionBadge.waitForExistence(timeout: 2))

        app.buttons["Quit Pointrans"].click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 3))
    }

    func testGuidedStageIsTheRealPracticeSurfaceWithoutAFakeResultPage() throws {
        let app = launch(scenario: "onboarding-guided")
        XCTAssertTrue(element("pointrans-onboarding-window", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Quit Pointrans"].waitForExistence(timeout: 2))
        XCTAssertTrue(element("pointrans-menu-bar-button", in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["breakthrough"].waitForExistence(timeout: 2))
        XCTAssertTrue(element("guided-practice-status", in: app).exists)
        XCTAssertTrue(app.staticTexts["Pointrans is ready. Try it here."].exists)
        XCTAssertTrue(app.staticTexts["Point to the blue word and hold Left Option"].exists)
        XCTAssertFalse(element("guided-live-result", in: app).exists)
        XCTAssertFalse(app.staticTexts["Choose how context can recover"].exists)
        XCTAssertFalse(app.buttons["Allow cloud fallback"].exists)
        XCTAssertFalse(app.buttons["onboarding-finish-button"].exists)
    }

    func testClosingTheOnboardingWindowTerminatesTheMenuBarProcess() throws {
        let app = launch(scenario: "onboarding")
        let close = app.buttons["_XCUI:CloseWindow"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))

        app.activate()
        close.click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 3))
    }

    func testControlCenterFollowsChineseAndDarkAppearance() throws {
        let app = launch(scenario: "control-center", language: "zh-Hans", dark: true)
        XCTAssertTrue(element("control-center-main", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["按住左 Option 并悬停"].exists)
        XCTAssertTrue(app.staticTexts["自动识别英文与中文"].exists)
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
