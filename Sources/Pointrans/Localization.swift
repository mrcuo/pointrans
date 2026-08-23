import Foundation

struct Localization {
    
    /// Returns the localized string for a key based on the user's selected language preference.
    static func string(for key: String) -> String {
        let selected = UserDefaults.standard.string(forKey: "appLanguage") ?? "auto"
        let lang: String

        if selected == "auto" {
            let preferredLang = Locale.preferredLanguages.first?.lowercased() ?? "en"
            lang = preferredLang.hasPrefix("zh") ? "zh" : "en"
        } else {
            lang = selected
        }

        return localizations[key]?[lang] ?? key
    }

    /// Built once; `string(for:)` previously rebuilt this dictionary on every call.
    private static let localizations: [String: [String: String]] = [
            "app_name": ["zh": "光标翻译", "en": "Pointrans"],
            "quick_trans": ["zh": "快速翻译", "en": "Quick Translation"],
            "ai_trans": ["zh": "AI 语境深度解析", "en": "AI Context Analysis"],
            "ai_loading": ["zh": "正在分析语境中...", "en": "Analyzing context..."],
            "loading_translating": ["zh": "正在翻译...", "en": "Translating..."],
            "loading_ai": ["zh": "正在翻译及分析语境...", "en": "Translating & analyzing context..."],
            "no_permission": ["zh": "未启用屏幕录制权限", "en": "Screen Recording Permission Disabled"],
            "no_permission_desc": ["zh": "Pointrans 需要屏幕录制权限来识别屏幕上的单词。\n请点击菜单栏图标 -> 设置 -> 系统权限 选项卡，按提示授予权限。", "en": "Pointrans requires screen recording permission to parse words on the screen.\nPlease click the menu bar icon -> Settings -> System Permissions, and grant permission."],
            "ai_translation_button": ["zh": "AI 语境翻译", "en": "AI Translation"],
            
            // Menu Items
            "menu_enable": ["zh": "启用翻译功能", "en": "Enable Translation"],
            "menu_mode_direction": ["zh": "翻译方向", "en": "Translation Direction"],
            "menu_mode_en_zh_short": ["zh": "英语 → 中文", "en": "English → Chinese"],
            "menu_mode_zh_en_short": ["zh": "中文 → 英语", "en": "Chinese → English"],
            "menu_settings": ["zh": "设置...", "en": "Settings..."],
            "menu_about": ["zh": "关于 Pointrans", "en": "About Pointrans"],
            "menu_quit": ["zh": "退出", "en": "Quit"],
            
            // Settings Window
            "settings_title": ["zh": "设置 - Pointrans", "en": "Settings - Pointrans"],
            "tab_general": ["zh": "常规", "en": "General"],
            "tab_ai": ["zh": "AI 翻译", "en": "AI Translation"],
            "tab_permissions": ["zh": "系统权限", "en": "Permissions"],
            
            "general_enable": ["zh": "开启翻译功能", "en": "Enable Translation"],
            "general_trigger": ["zh": "触发设置", "en": "Trigger Settings"],
            "general_key": ["zh": "触发修饰键", "en": "Trigger Modifier Key"],
            "general_delay": ["zh": "鼠标悬停延迟", "en": "Hover Delay"],
            "general_language": ["zh": "界面语言", "en": "App Language"],
            
            "lang_auto": ["zh": "自动 (跟随系统)", "en": "Auto (System Default)"],
            "lang_zh": ["zh": "简体中文", "en": "简体中文"],
            "lang_en": ["zh": "English", "en": "English"],
            
            "ai_section": ["zh": "AI 语境配置", "en": "AI Context Configurations"],
            "ai_enable": ["zh": "启用 AI 语境翻译 (深度解析)", "en": "Enable AI Context Translation"],
            "ai_provider": ["zh": "AI 服务商", "en": "AI Provider"],
            "ai_model": ["zh": "模型名称", "en": "Model Name"],
            "ai_endpoint": ["zh": "API 节点 (Endpoint)", "en": "API Endpoint"],
            "ai_key_warning": ["zh": "⚠️ 请在设置中配置 API Key", "en": "⚠️ Please configure API Key in settings"],
            
            // Offline dictionary
            "offline_local_badge": ["zh": "[本地离线]", "en": "[Offline]"],
            
            // Permissions
            "permission_title": ["zh": "权限设置", "en": "Permission Settings"],
            "permission_desc": ["zh": "本软件采用屏幕截图加本地 Vision 文本识别 (OCR) 技术实现。为此，软件需要系统屏幕录制权限。截图仅在本地内存中处理，绝对不会保存或上传。", "en": "This software captures a small screen region and runs offline OCR (Vision framework) in memory to detect text. Thus, it requires Screen Recording permission. Images are never saved or uploaded."],
            "permission_granted": ["zh": "已获得屏幕录制权限", "en": "Screen Recording permission granted"],
            "permission_not_granted": ["zh": "未获得权限", "en": "Permission not granted"],
            "permission_btn_request": ["zh": "点击申请屏幕录制权限", "en": "Click to request permission"],
            "permission_btn_check": ["zh": "重新检查权限状态", "en": "Re-check permission status"],
            "permission_tip": ["zh": "💡 提示：在弹出系统对话框时，请选择\u{201C}打开系统设置\u{201D}，并勾选\u{201C}Pointrans\u{201D}。开启后如不能立即生效，建议重启本应用。", "en": "💡 Tip: When the system dialog prompts, click 'Open System Settings' and check 'Pointrans'. If it does not take effect immediately, please restart the app."],
            
            // Network warnings
            "net_error_google": ["zh": "⚠️ 网络连接失败。请在设置中查看离线词包状态。", "en": "⚠️ Network error. Please check offline dictionary in Settings."],
            
            // TTS Pronunciation Tooltip
            "pronounce_tooltip": ["zh": "朗读单词", "en": "Pronounce word"],

            // Test connection
            "test_connection": ["zh": "测试连接", "en": "Test Connection"],
            "testing_connection": ["zh": "正在测试连接...", "en": "Testing connection..."],
            "test_success": ["zh": "连接成功", "en": "Connection Successful"],
            "test_failed": ["zh": "连接失败", "en": "Connection Failed"],
            "ai_api_key": ["zh": "API Key", "en": "API Key"],
            "ok": ["zh": "好", "en": "OK"]
        ]
    
    /// Formulates the localization-aware prompt for AI context translation.
    static func translationPrompt(word: String, context: String, direction: String) -> String {
        if direction == "zh-to-en" {
            return """
            You are an expert Chinese-to-English translation assistant. Translate the Chinese word/phrase in its specific context into natural English.
            
            Target Chinese word/phrase: \(word)
            Sentence context: \(context)
            
            Output strictly in the following format (Markdown support enabled):
            **Translation**: [Provide the most accurate English translation for the word/phrase in this context]
            **Pinyin**: [Pinyin with tone marks] | **Part of Speech**: [e.g., noun (n.), verb (v.), etc.]
            **Contextual Analysis**: [A brief 1-2 sentence explanation of why this translation fits this context, and any specific connotations or idioms used]
            **Example**:
            - \(word): [The original sentence containing the word, or a simplified version] -> [Natural English translation of the sentence]
            """
        } else {
            return """
            你是一个智能翻译助手。请翻译英文单词，并结合上下文语境提供精准、自然的简体中文解释。
            
            原文单词: \(word)
            上下文语境: \(context)
            
            请严格按以下格式输出（支持 Markdown）：
            **词义**: [该单词在当前语境下的最贴切中文翻译]
            **音标**: [音标] | **词性**: [词性]
            **语境解析**: [简短的一两句话，解释该词在此上下文中的具体含义、感情色彩或习惯用法]
            **例句**:
            - \(word): [当前语境里的原句或简化原句] (中文翻译)
            """
        }
    }
}
