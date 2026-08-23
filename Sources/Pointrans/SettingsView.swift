import SwiftUI
import AppKit

// MARK: - Main Settings View
struct SettingsView: View {
    @AppStorage("appLanguage") private var appLanguage = "auto"
    @State private var activeTab: String? = "general"

    var body: some View {
        NavigationSplitView {
            List(selection: $activeTab) {
                Label(Localization.string(for: "tab_general"), systemImage: "gearshape")
                    .tag("general")
                Label(Localization.string(for: "tab_ai"), systemImage: "sparkles")
                    .tag("ai")
                Label(Localization.string(for: "tab_permissions"), systemImage: "lock.shield")
                    .tag("permissions")
            }
            .listStyle(.sidebar)
        } detail: {
            switch activeTab {
            case "general":
                GeneralTab()
            case "ai":
                AITab()
            case "permissions":
                PermissionsTab()
            default:
                GeneralTab()
            }
        }
        .frame(width: 580, height: 400)
        .onAppear {
            updateWindowTitle()
        }
        .onChange(of: appLanguage) { oldValue, newValue in
            updateWindowTitle()
        }
    }

    private func updateWindowTitle() {
        SettingsWindowManager.shared.window?.title = Localization.string(for: "settings_title")
    }
}

// MARK: - General Settings Tab
struct GeneralTab: View {
    @AppStorage("translationEnabled") private var translationEnabled = true
    @AppStorage("modifierKey") private var modifierKey = "command"
    @AppStorage("hoverDelay") private var hoverDelay = 0.3
    @AppStorage("appLanguage") private var appLanguage = "auto"

    var body: some View {
        Form {
            Section(Localization.string(for: "general_trigger")) {
                Toggle(Localization.string(for: "general_enable"), isOn: $translationEnabled)

                if translationEnabled {
                    Picker(Localization.string(for: "general_key"), selection: $modifierKey) {
                        Text("Command (⌘)").tag("command")
                        Text("Option (⌥)").tag("option")
                        Text("Control (⌃)").tag("control")
                        Text("Shift (⇧)").tag("shift")
                    }

                    HStack {
                        Text(Localization.string(for: "general_delay"))
                        Spacer()
                        Slider(value: $hoverDelay, in: 0.1...1.5, step: 0.1)
                            .frame(width: 200)
                        Text(String(format: "%.1f s", hoverDelay))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 45, alignment: .trailing)
                    }
                }
            }

            Section(Localization.string(for: "general_language")) {
                Picker(Localization.string(for: "general_language"), selection: $appLanguage) {
                    Text(Localization.string(for: "lang_auto")).tag("auto")
                    Text(Localization.string(for: "lang_zh")).tag("zh")
                    Text(Localization.string(for: "lang_en")).tag("en")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - AI Settings Tab

private enum ConnectionTestResult {
    case success
    case failure(String)
}

struct AITab: View {
    @AppStorage("aiEnabled") private var aiEnabled = false
    @AppStorage("aiProvider") private var aiProvider = "gemini"

    @AppStorage("geminiApiKey") private var geminiApiKey = ""
    @AppStorage("geminiModel") private var geminiModel = "gemini-2.5-flash"

    @AppStorage("openaiApiKey") private var openaiApiKey = ""
    @AppStorage("openaiEndpoint") private var openaiEndpoint = "https://api.openai.com/v1/chat/completions"
    @AppStorage("openaiModel") private var openaiModel = "gpt-4o-mini"

    @State private var isTesting = false
    @State private var testResult: ConnectionTestResult?

    var body: some View {
        Form {
            Section(Localization.string(for: "ai_section")) {
                Toggle(Localization.string(for: "ai_enable"), isOn: $aiEnabled)

                if aiEnabled {
                    Picker(Localization.string(for: "ai_provider"), selection: $aiProvider) {
                        Text("Google Gemini").tag("gemini")
                        Text("OpenAI").tag("openai")
                    }
                    .pickerStyle(.segmented)
                }
            }

            if aiEnabled {
                if aiProvider == "gemini" {
                    Section("Gemini") {
                        SecureField(Localization.string(for: "ai_api_key"), text: $geminiApiKey)

                        Picker(Localization.string(for: "ai_model"), selection: $geminiModel) {
                            Text("gemini-2.5-flash").tag("gemini-2.5-flash")
                            Text("gemini-2.5-pro").tag("gemini-2.5-pro")
                        }
                    }
                } else {
                    Section("OpenAI") {
                        SecureField(Localization.string(for: "ai_api_key"), text: $openaiApiKey)

                        TextField(Localization.string(for: "ai_endpoint"), text: $openaiEndpoint)

                        TextField(Localization.string(for: "ai_model"), text: $openaiModel)
                    }
                }

                Section {
                    Button(action: runConnectionTest) {
                        HStack {
                            Spacer()
                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.8)
                                    .padding(.trailing, 4)
                                Text(Localization.string(for: "testing_connection"))
                            } else {
                                Text(Localization.string(for: "test_connection"))
                            }
                            Spacer()
                        }
                    }
                    .disabled(isTesting || (aiProvider == "gemini" ? geminiApiKey.isEmpty : openaiApiKey.isEmpty))

                    if let result = testResult {
                        HStack {
                            Spacer()
                            switch result {
                            case .success:
                                Label(Localization.string(for: "test_success"), systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            case .failure:
                                Label(Localization.string(for: "test_failed"), systemImage: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                            }
                            Spacer()
                        }
                        .padding(.top, 4)

                        if case .failure(let message) = result {
                            Text(message)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: aiProvider) { _, _ in testResult = nil }
        .onChange(of: geminiApiKey) { _, _ in testResult = nil }
        .onChange(of: openaiApiKey) { _, _ in testResult = nil }
        .onChange(of: openaiEndpoint) { _, _ in testResult = nil }
        .onChange(of: openaiModel) { _, _ in testResult = nil }
    }

    private func runConnectionTest() {
        isTesting = true
        testResult = nil

        Task {
            let (success, message) = await TranslationService.shared.testConnection()
            await MainActor.run {
                isTesting = false
                testResult = success ? .success : .failure(message)
            }
        }
    }
}

// MARK: - Permissions Settings Tab
struct PermissionsTab: View {
    @State private var hasPermission = false

    var body: some View {
        Form {
            Section(Localization.string(for: "permission_title")) {
                Text(Localization.string(for: "permission_desc"))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3.5)

                HStack(spacing: 8) {
                    Circle()
                        .fill(hasPermission ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(hasPermission
                         ? Localization.string(for: "permission_granted")
                         : Localization.string(for: "permission_not_granted"))
                        .font(.system(size: 13, weight: .semibold))
                }

                if !hasPermission {
                    Button(action: checkAndRequestPermission) {
                        Text(Localization.string(for: "permission_btn_request"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Text(Localization.string(for: "permission_tip"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Button(action: checkPermissionStatus) {
                        Text(Localization.string(for: "permission_btn_check"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            checkPermissionStatus()
        }
    }

    private func checkPermissionStatus() {
        hasPermission = CGPreflightScreenCaptureAccess()
    }

    private func checkAndRequestPermission() {
        let granted = CGRequestScreenCaptureAccess()
        hasPermission = granted
        if !granted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.checkPermissionStatus()
            }
        }
    }
}

// MARK: - Settings Window with Edit Shortcuts Support
class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command {
            switch event.charactersIgnoringModifiers {
            case "v":
                if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) { return true }
            case "c":
                if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) { return true }
            case "x":
                if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) { return true }
            case "a":
                if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) { return true }
            case "z":
                if NSApp.sendAction(Selector(("undo:")), to: nil, from: self) { return true }
            default:
                break
            }
        } else if flags == [.command, .shift] {
            if event.charactersIgnoringModifiers == "z" {
                if NSApp.sendAction(Selector(("redo:")), to: nil, from: self) { return true }
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Window Manager
class SettingsWindowManager {
    static let shared = SettingsWindowManager()

    var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    func show() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let newWindow = SettingsWindow(
            contentViewController: hostingController
        )
        newWindow.setContentSize(NSSize(width: 580, height: 400))
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        newWindow.title = Localization.string(for: "settings_title")
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden
        newWindow.isReleasedWhenClosed = false

        newWindow.center()

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate()

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newWindow,
            queue: .main
        ) { [weak self] _ in
            self?.window = nil
            if let observer = self?.closeObserver {
                NotificationCenter.default.removeObserver(observer)
                self?.closeObserver = nil
            }
        }
    }
}
