import AppKit
import Foundation

@main
@MainActor
enum PointransApplication {
    private static let lifetime = ApplicationLifetime(delegate: PointransAppDelegate())

    static func main() {
        let application = NSApplication.shared
        application.delegate = lifetime.delegate
        application.setActivationPolicy(.accessory)
        application.mainMenu = makeMainMenu(for: application)
        withExtendedLifetime(lifetime) { application.run() }
    }

    private static func makeMainMenu(for application: NSApplication) -> NSMenu {
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Pointrans")
        let quit = NSMenuItem(
            title: String(localized: "Quit Pointrans"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = application
        applicationMenu.addItem(quit)
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)
        return mainMenu
    }
}

@MainActor
final class PointransAppDelegate: NSObject, NSApplicationDelegate {
    private var controller: TranslationController?
    private var shell: ApplicationShellCoordinator?
    private var overlay: TranslationPanelCoordinator?
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            // The menu-bar item is the application's primary surface. Create
            // and retain it before loading dictionaries, models, or windows so
            // every successful process launch is immediately discoverable.
            let statusBar = try StatusBarController(validating: ())
            self.statusBar = statusBar

            let resourceBundle: Bundle
            #if SWIFT_PACKAGE
            resourceBundle = .module
            #else
            resourceBundle = .main
            #endif

            #if DEBUG
            let isUITesting = UITestSupport.isEnabled
            #else
            let isUITesting = false
            #endif

            let permissionProvider: any PermissionProviding
            let environment: ProviderEnvironment
            let preferences: AppPreferences
            let languagePacks: LanguagePackManager

            if isUITesting {
                #if DEBUG
                environment = UITestSupport.environment()
                permissionProvider = UITestSupport.permissions()
                let suiteName = "com.tailcasso.Pointrans.UITests"
                let defaults = UserDefaults(suiteName: suiteName)!
                defaults.removePersistentDomain(forName: suiteName)
                preferences = AppPreferences(defaults: defaults)
                let onboarding = UITestSupport.scenario.hasPrefix("onboarding")
                preferences.didCompleteOnboarding = !onboarding
                if UITestSupport.scenario == "onboarding-guided" {
                    preferences.onboardingStage = .guidedExperience
                }
                preferences.cloudContextConsent = .allowed
                languagePacks = LanguagePackManager(forceInstalledForTesting: true)
                #else
                fatalError("UI testing support is unavailable in Release builds")
                #endif
            } else {
                let dictionary = try DictionaryStore(bundle: resourceBundle)
                let translator = BaseTranslationService(dictionary: dictionary)
                let workerURL = AppConfiguration.workerBaseURL()
                    ?? URL(string: "https://pointrans-api.cuostudio.workers.dev")!
                let cloud = CloudContextClient(baseURL: workerURL)
                permissionProvider = PermissionService()
                environment = ProviderEnvironment(
                    extractor: HybridTextExtractor(),
                    translator: translator,
                    analyzer: ContextAnalyzerRouter(cloud: cloud),
                    permissions: permissionProvider
                )
                preferences = AppPreferences()
                languagePacks = LanguagePackManager()
            }

            let permissionCoordinator = PermissionCoordinator(provider: permissionProvider)
            let controller = TranslationController(preferences: preferences, environment: environment)
            let overlay = TranslationPanelCoordinator(controller: controller, isUITesting: isUITesting)
            let shell = ApplicationShellCoordinator(
                controller: controller,
                permissions: permissionCoordinator,
                languagePacks: languagePacks,
                preferences: preferences,
                statusBar: statusBar
            )

            self.controller = controller
            self.overlay = overlay
            self.shell = shell
            shell.launch()

            #if DEBUG
            if isUITesting {
                if UITestSupport.scenario.hasPrefix("preview") || UITestSupport.scenario.hasPrefix("ai-") {
                    controller.start()
                    controller.loadUITestFixture(pinned: UITestSupport.scenario == "preview-pinned")
                } else if UITestSupport.scenario != "onboarding" {
                    shell.handleReopen()
                }
            }
            #endif
        } catch {
            presentFatalStartupError(error)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let shell {
            shell.stop()
        } else {
            statusBar?.invalidate()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        shell?.applicationDidBecomeActive()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        sender.activate()
        shell?.handleReopen()
        return true
    }

    private func presentFatalStartupError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(localized: "Pointrans could not start")
        if error is ApplicationShellCoordinator.InitializationError {
            alert.informativeText = String(localized: "Pointrans could not create its menu bar item and will quit.")
        } else {
            alert.informativeText = String(localized: "The built-in dictionary is missing or damaged. Reinstall Pointrans.")
        }
        alert.addButton(withTitle: String(localized: "Quit"))
        alert.runModal()
        NSApp.terminate(nil)
    }
}
