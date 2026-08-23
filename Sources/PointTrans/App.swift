import Cocoa
import SwiftUI

@main
class PointTransApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    
    var statusItem: NSStatusItem?
    var enableMenuItem: NSMenuItem?
    var modeSubmenu: NSMenu?
    var modeEnZhItem: NSMenuItem?
    var modeZhEnItem: NSMenuItem?
    var modeSubmenuItem: NSMenuItem?
    var settingsMenuItem: NSMenuItem?
    var aboutMenuItem: NSMenuItem?
    var quitMenuItem: NSMenuItem?
    private var isShowingAlert = false
    private var translationGeneration = 0
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize default settings if not already set
        setupDefaultSettings()
        
        // Build status bar menu
        setupMenuBar()
        
        // Set up mouse and keyboard hotkey monitors
        setupEventMonitors()
        
        print("[App] PointTrans started successfully.")
    }
    
    private func setupDefaultSettings() {
        let preferredLang = Locale.preferredLanguages.first?.lowercased() ?? "en"
        let defaultMode = preferredLang.hasPrefix("zh") ? "en-to-zh" : "zh-to-en"
        
        let defaults: [String: Any] = [
            "translationEnabled": true,
            "modifierKey": "command",
            "hoverDelay": 0.3,
            "translationMode": defaultMode,
            "aiEnabled": false,
            "aiProvider": "gemini",
            "geminiModel": "gemini-2.5-flash",
            "openaiEndpoint": "https://api.openai.com/v1/chat/completions",
            "openaiModel": "gpt-4o-mini"
        ]
        UserDefaults.standard.register(defaults: defaults)
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemButton()
        
        let menu = NSMenu()
        menu.delegate = self
        
        // 1. Enable translation toggle
        let enableItem = NSMenuItem(title: Localization.string(for: "menu_enable"), action: #selector(toggleTranslation), keyEquivalent: "")
        enableItem.target = self
        menu.addItem(enableItem)
        self.enableMenuItem = enableItem
        
        menu.addItem(NSMenuItem.separator())
        
        // 2. Translation direction submenu
        let submenuItem = NSMenuItem(title: Localization.string(for: "menu_mode_direction"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        
        let modeEnZh = NSMenuItem(title: Localization.string(for: "menu_mode_en_zh_short"), action: #selector(setModeEnZh), keyEquivalent: "")
        modeEnZh.target = self
        submenu.addItem(modeEnZh)
        self.modeEnZhItem = modeEnZh
        
        let modeZhEn = NSMenuItem(title: Localization.string(for: "menu_mode_zh_en_short"), action: #selector(setModeZhEn), keyEquivalent: "")
        modeZhEn.target = self
        submenu.addItem(modeZhEn)
        self.modeZhEnItem = modeZhEn
        
        submenuItem.submenu = submenu
        menu.addItem(submenuItem)
        self.modeSubmenuItem = submenuItem
        self.modeSubmenu = submenu
        
        menu.addItem(NSMenuItem.separator())
        
        // 3. Settings Window
        let settingsItem = NSMenuItem(title: Localization.string(for: "menu_settings"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        self.settingsMenuItem = settingsItem
        
        menu.addItem(NSMenuItem.separator())
        
        // 4. About
        let aboutItem = NSMenuItem(title: Localization.string(for: "menu_about"), action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        self.aboutMenuItem = aboutItem
        
        // 5. Quit App
        let quitItem = NSMenuItem(title: Localization.string(for: "menu_quit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        self.quitMenuItem = quitItem
        
        statusItem?.menu = menu
    }
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        let isEnabled = UserDefaults.standard.bool(forKey: "translationEnabled")
        enableMenuItem?.state = isEnabled ? .on : .off
        enableMenuItem?.title = Localization.string(for: "menu_enable")
        
        let mode = UserDefaults.standard.string(forKey: "translationMode") ?? "en-to-zh"
        modeEnZhItem?.state = mode == "en-to-zh" ? .on : .off
        modeEnZhItem?.title = Localization.string(for: "menu_mode_en_zh_short")
        
        modeZhEnItem?.state = mode == "zh-to-en" ? .on : .off
        modeZhEnItem?.title = Localization.string(for: "menu_mode_zh_en_short")
        
        modeSubmenuItem?.title = Localization.string(for: "menu_mode_direction")
        settingsMenuItem?.title = Localization.string(for: "menu_settings")
        aboutMenuItem?.title = Localization.string(for: "menu_about")
        quitMenuItem?.title = Localization.string(for: "menu_quit")
        
        updateStatusItemButton()
    }
    
    private func updateStatusItemButton() {
        if let button = statusItem?.button {
            button.image = nil
            let appLang = UserDefaults.standard.string(forKey: "appLanguage") ?? "auto"
            let isZh: Bool
            if appLang == "auto" {
                isZh = (Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") ?? false)
            } else {
                isZh = (appLang == "zh")
            }
            button.title = isZh ? "译" : "PT"
            button.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        }
    }
    
    @objc private func toggleTranslation() {
        let isEnabled = UserDefaults.standard.bool(forKey: "translationEnabled")
        UserDefaults.standard.set(!isEnabled, forKey: "translationEnabled")
        HotKeyHandler.shared.resetLastTranslationLocation()
        TranslationPanel.shared.dismiss()
    }
    
    @objc private func setModeEnZh() {
        UserDefaults.standard.set("en-to-zh", forKey: "translationMode")
        HotKeyHandler.shared.resetLastTranslationLocation()
        TranslationPanel.shared.dismiss()
    }
    
    @objc private func setModeZhEn() {
        UserDefaults.standard.set("zh-to-en", forKey: "translationMode")
        HotKeyHandler.shared.resetLastTranslationLocation()
        TranslationPanel.shared.dismiss()
    }
    
    @objc private func openSettings() {
        SettingsWindowManager.shared.show()
    }
    
    @objc private func showAbout() {
        let versionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let year = Calendar.current.component(.year, from: Date())

        let alert = NSAlert()
        alert.messageText = "PointTrans"
        alert.informativeText = "\(Localization.string(for: "app_name"))\nVersion \(versionString)\n\n© \(year) Tailcasso"
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: Localization.string(for: "ok"))
        alert.runModal()
    }
    
    @objc private func quitApp() {
        TranslationPanel.shared.dismiss()
        HotKeyHandler.shared.stopMonitoring()
        NSApp.terminate(nil)
    }
    
    private func setupEventMonitors() {
        HotKeyHandler.shared.startMonitoring()

        // Bind hover activation callback
        HotKeyHandler.shared.onHoverTriggered = { [weak self] mousePoint in
            self?.handleHoverTrigger(at: mousePoint)
        }

        // Dismiss panel if mouse moves
        HotKeyHandler.shared.onMouseMoved = {
            TranslationPanel.shared.requestDismiss()
        }

        // Dismiss panel if modifier key is released
        HotKeyHandler.shared.onModifierReleased = {
            TranslationPanel.shared.requestDismiss()
        }
    }
    
    private func handleHoverTrigger(at mousePoint: NSPoint) {
        let isEnabled = UserDefaults.standard.bool(forKey: "translationEnabled")
        guard isEnabled else { return }

        // 1. Check Screen Recording permissions
        if !CGPreflightScreenCaptureAccess() {
            showPermissionAlert()
            return
        }

        let activeMode = UserDefaults.standard.string(forKey: "translationMode") ?? "en-to-zh"
        let isAiEnabled = UserDefaults.standard.bool(forKey: "aiEnabled")

        // Every hover trigger advances the generation; async callbacks that no longer
        // match it are stale results for a previous word and are dropped.
        translationGeneration += 1
        let generation = translationGeneration

        Task {
            // 2. Local OCR text extraction (runs off the main thread, see TextExtractor)
            guard let extracted = await TextExtractor.extractWordAtCursor(mode: activeMode) else {
                return
            }
            guard generation == translationGeneration else { return }

            let word = extracted.word
            let context = extracted.context

            // 3. Show floating window in loading state
            TranslationPanel.shared.show(
                at: mousePoint,
                word: word,
                context: context,
                googleResult: nil,
                phonetic: nil,
                aiResult: nil,
                aiEnabled: isAiEnabled,
                isAILoading: false,
                direction: activeMode,
                onFetchAI: nil
            )

            // 4. Fetch translations asynchronously
            let googleTrans = await TranslationService.shared.translateWithGoogle(word: word, direction: activeMode)
            guard generation == translationGeneration else { return }

            let fetchAI: () -> Void = { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    guard generation == self.translationGeneration else { return }

                    if TranslationPanel.shared.isVisible {
                        TranslationPanel.shared.update(
                            word: word,
                            context: context,
                            googleResult: googleTrans?.translation,
                            phonetic: googleTrans?.phonetic,
                            aiResult: nil,
                            aiEnabled: isAiEnabled,
                            isAILoading: true,
                            direction: activeMode,
                            onFetchAI: nil
                        )
                    }

                    let aiTrans = await TranslationService.shared.translateWithAI(word: word, context: context, direction: activeMode)
                    guard generation == self.translationGeneration else { return }

                    if TranslationPanel.shared.isVisible {
                        TranslationPanel.shared.update(
                            word: word,
                            context: context,
                            googleResult: googleTrans?.translation,
                            phonetic: googleTrans?.phonetic,
                            aiResult: aiTrans,
                            aiEnabled: isAiEnabled,
                            isAILoading: false,
                            direction: activeMode,
                            onFetchAI: nil
                        )
                    }
                }
            }

            if TranslationPanel.shared.isVisible {
                TranslationPanel.shared.update(
                    word: word,
                    context: context,
                    googleResult: googleTrans?.translation,
                    phonetic: googleTrans?.phonetic,
                    aiResult: nil,
                    aiEnabled: isAiEnabled,
                    isAILoading: false,
                    direction: activeMode,
                    onFetchAI: fetchAI
                )
            }
        }
    }
    
    private func showPermissionAlert() {
        guard !isShowingAlert else { return }
        isShowingAlert = true
        
        // Use CGRequestScreenCaptureAccess() to trigger the native macOS permission dialog.
        // This properly registers the app in System Settings > Privacy > Screen Recording.
        let granted = CGRequestScreenCaptureAccess()
        
        if !granted {
            // If not granted, show a follow-up alert with instructions
            let alert = NSAlert()
            alert.messageText = Localization.string(for: "no_permission")
            alert.informativeText = Localization.string(for: "no_permission_desc")
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: Localization.string(for: "menu_quit"))
            
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                NSApp.terminate(nil)
            }
        }
        
        isShowingAlert = false
    }
}
