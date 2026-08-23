# Pointrans (光标翻译)

[English](#english) | [中文](#中文)

---

## English

**Pointrans** is a lightweight, high-performance, and native macOS screen-hover translation tool built using Swift and SwiftUI. It enables you to instantly translate text on your screen (English $\leftrightarrow$ Chinese) by simply holding a modifier key and hovering your cursor over any word.

It combines the speed of local OCR and instant translation APIs with the semantic depth of modern LLMs (Gemini / OpenAI / DeepSeek) to give you context-aware definitions.

> [!NOTE]
> Pointrans does not require system-wide accessibility permissions, making it extremely secure and lightweight to use.

---

### 🌟 Core Features

- **Zero-Accessibility-Permission Hover Listener**: Monitors modifier keys and mouse coordinates globally using high-frequency, low-overhead event loops. Safe and private.
- **Native Vision OCR**: Captures a small screen crop around the cursor in memory and runs Apple's highly optimized Vision framework OCR locally. Works on any app, including Safari, Chrome, Terminal, PDF readers, and images.
- **Hyphenated Word Extraction**: Smartly extracts hyphenated compounds (e.g., `wi-fi`, `e-mail`, `state-of-the-art`) without truncating them.
- **Dual-Language & Localization**: Dynamically adapts interface labels and OCR targets based on system language.
  - **Chinese System**: Translates English to Chinese (Default).
  - **English System**: Translates Chinese to English (Default).
- **Dual-Engine Translation**:
  - **Google Translate**: Instant word definitions in ~100ms.
  - **Context-Aware AI Translation**: Feeds the hovered word and its surrounding sentence context to Gemini or OpenAI-compatible models to return precise contextual meanings, phonetics, parts of speech, and explanations.
- **Elegant macOS UI**: A non-activating floating frosted-glass window (`NSPanel`) that displays translation results without taking window focus. Supports hover lock (move your cursor into the panel to keep it open and select/copy text).
- **Sleek Settings Panel**: Overhauled using native macOS `NavigationSplitView` and grouped `Form` layouts for a lightweight, modern, and native operating system appearance.

---

### 📦 Installation & Setup

1. **Download & Mount**: Open `Pointrans.dmg` and drag `Pointrans.app` to your `Applications` folder.
2. **Launch**: Open `Pointrans` from Launchpad or Applications. A `translate` icon will appear in your macOS status menu bar.
3. **Screen Recording Permission**: 
   - When you first hover-translate, a system dialog will prompt you to authorize Screen Recording.
   - Alternatively, click the menu bar icon -> **Settings...** -> **System Permissions** tab.
   - Click **Request Permission**. In the macOS System Settings dialog, toggle the switch next to **Pointrans** to enabled.
   - Restart the application to ensure permissions take effect immediately.

> [!IMPORTANT]
> The app is code-signed using ad-hoc signing (`codesign --sign -`) in the build pipeline. This ensures macOS correctly displays the application inside the Privacy & Security preferences list.


---


### 🛠️ Building from Source

To compile the application locally:
```bash
# Clone the repository
git clone https://github.com/mrcuo/pointrans.git
cd pointrans

# Make build executable
chmod +x build.sh package.sh

# Compile and package as DMG
./package.sh
```
This generates `Pointrans.dmg` in the repository root.

---

---

## 中文

**Pointrans (光标翻译)** 是一款基于 Swift 和 SwiftUI 构建的 macOS 原生、高性能、轻量化光标悬停翻译工具。只需按住自定义修饰键（如 Command）并在单词上悬停鼠标，即可瞬间将屏幕上任意位置的中英文单词进行互译。

本软件结合了本地 OCR 的高响应度、快速网页翻译，以及大语言模型（Gemini / OpenAI / DeepSeek）的上下文理解能力，提供融合前后语境的“深度翻译”解析。

> [!NOTE]
> Pointrans 无需开启系统敏感的“辅助功能(Accessibility)”权限，保障您的系统安全与隐私。

---

### 🌟 核心特性

- **零“辅助功能”权限监听**：无需开启系统辅助功能权限。通过低能耗的后台定时器轮询修饰键状态与光标位置，即可实现流畅的悬停唤醒。
- **本地 Vision 文本识别**：在内存中截取光标周围 `400 x 80` 像素的图像，使用苹果原生 Vision OCR 引擎在本地进行文字提取。支持任何应用（Safari, Chrome, 终端, PDF, 微信, 甚至图片）。
- **连字符单词合并**：精准识别并提取带有连字符的复合词（如 `wi-fi`、`e-mail`、`state-of-the-art`），不再发生仅翻译前半段的情况。
- **双向语言自适应**：
  - **中文系统**：默认执行 **英译中**，OCR 专注英文单词提取。
  - **英文系统**：默认执行 **中译英**，OCR 支持中英文提取，并自动利用 Apple 分词器切分中文词组。
- **双引擎融合翻译**：
  - **快速翻译**：100毫秒内完成谷歌翻译响应，快速呈现在悬浮窗中。
  - **AI 深度语境翻译**：将光标处的单词连同其所在的句子上下文一同发送给大模型，返回融合语境的精准词义、音标、词性、语境解析与例句。
- **毛玻璃浮窗交互**：使用不夺取焦点的 `NSPanel` 浮窗，实时进行毛玻璃模糊过滤，伴有流畅的缩放及淡入淡出动画。支持悬停锁定（鼠标移入悬浮窗可保持显示并支持文本选择/复制）。
- **原生极简设置**：重构并使用 macOS 原生 `NavigationSplitView` 和分组 `Form` 布局，UI 轻量扁平，拥有纯正的苹果系统原生设计质感。

---

### 📦 安装与配置

1. **双击安装**：双击打开生成的 `Pointrans.dmg`，将 `Pointrans` 图标拖拽至右侧的 `Applications` 应用程序文件夹。
2. **启动软件**：在启动台或应用程序中打开，状态栏（屏幕右上角）将出现翻译图标。
3. **授予权限**：
   - 首次触发翻译时，系统会弹出原生“录屏”授权申请。
   - 或者点击菜单栏图标 -> **设置...** -> 选择 **系统权限** 标签页。
   - 点击 **点击申请屏幕录制权限**，在系统弹窗中选择打开系统设置，并勾选启用 **Pointrans**。
   - 建议重启软件以确保权限完全生效。

> [!IMPORTANT]
> 应用在构建打包时已通过 ad-hoc 签名（`codesign --sign -`），确保其能成功在 macOS 隐私与安全性设置的“屏幕录制”列表中注册并显示。


---


### 🛠️ 源码编译

若需自行编译：
```bash
# 克隆仓库
git clone https://github.com/mrcuo/pointrans.git
cd pointrans

# 开启脚本执行权限
chmod +x build.sh package.sh

# 编译并打包为 DMG
./package.sh
```
编译成功后，将在根目录下生成可分发的 `Pointrans.dmg` 安装包。
