import AppKit
import Foundation

@main
@MainActor
enum PointransApplication {
    static func main() {
        let application = NSApplication.shared
        let delegate = PointransAppDelegate()
        application.delegate = delegate
        #if DEBUG
        application.setActivationPolicy(UITestSupport.isEnabled ? .regular : .accessory)
        #else
        application.setActivationPolicy(.accessory)
        #endif
        application.run()
    }
}

@MainActor
final class PointransAppDelegate: NSObject, NSApplicationDelegate {
    private var controller: TranslationController?
    private var statusCoordinator: StatusItemCoordinator?
    private var panelCoordinator: TranslationPanelCoordinator?
    private var languagePacks: LanguagePackManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let resourceBundle: Bundle
            #if SWIFT_PACKAGE
            resourceBundle = .module
            #else
            resourceBundle = .main
            #endif

            let isUITesting: Bool
            #if DEBUG
            isUITesting = UITestSupport.isEnabled
            #else
            isUITesting = false
            #endif

            let environment: ProviderEnvironment
            if isUITesting {
                #if DEBUG
                environment = UITestSupport.environment()
                #else
                fatalError("UI testing support is unavailable in Release builds")
                #endif
            } else {
                let dictionary = try DictionaryStore(bundle: resourceBundle)
                let translator = BaseTranslationService(dictionary: dictionary)
                let workerURL = AppConfiguration.workerBaseURL() ?? URL(string: "https://pointrans-api.cuostudio.workers.dev")!
                let cloud = CloudContextClient(baseURL: workerURL)
                let analyzer = ContextAnalyzerRouter(cloud: cloud)
                environment = ProviderEnvironment(
                    extractor: HybridTextExtractor(),
                    translator: translator,
                    analyzer: analyzer,
                    permissions: PermissionService()
                )
            }

            let preferences: AppPreferences
            #if DEBUG
            if isUITesting {
                let suiteName = "com.tailcasso.Pointrans.UITests"
                let testDefaults = UserDefaults(suiteName: suiteName)!
                testDefaults.removePersistentDomain(forName: suiteName)
                preferences = AppPreferences(defaults: testDefaults)
                preferences.didCompleteOnboarding = UITestSupport.scenario != "permissions"
            } else {
                preferences = AppPreferences()
            }
            #else
            preferences = AppPreferences()
            #endif
            let controller = TranslationController(preferences: preferences, environment: environment)
            let packs = LanguagePackManager()

            self.controller = controller
            languagePacks = packs
            statusCoordinator = StatusItemCoordinator(controller: controller, languagePacks: packs)
            panelCoordinator = TranslationPanelCoordinator(controller: controller, isUITesting: isUITesting)
            if !isUITesting { controller.start() }

            #if DEBUG
            if isUITesting, UITestSupport.scenario.hasPrefix("preview") || UITestSupport.scenario.hasPrefix("ai-") {
                NSApp.activate()
                controller.loadUITestFixture(pinned: UITestSupport.scenario == "preview-pinned")
            } else if isUITesting {
                NSApp.activate()
                statusCoordinator?.showForUITesting()
            }
            #endif

        } catch {
            presentFatalStartupError(error)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Pointrans is a menu-bar utility. Launching or reopening it must remain
        // passive; the control center is presented only by the status-item click.
        return false
    }

    private func presentFatalStartupError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(localized: "Pointrans could not start")
        alert.informativeText = String(localized: "The built-in dictionary is missing or damaged. Reinstall Pointrans.")
        alert.addButton(withTitle: String(localized: "Quit"))
        alert.runModal()
        NSApp.terminate(nil)
    }
}
