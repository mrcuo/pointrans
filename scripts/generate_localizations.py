#!/usr/bin/env python3
"""Generate the String Catalog used by the native app."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "Sources" / "Pointrans" / "Resources" / "Localizable.xcstrings"

ZH = {
    "An explanation isn't available on this Mac right now.": "这台 Mac 目前无法生成解释。",
    "Asked only if it is needed": "仅在确实需要时询问",
    "A real context result is unavailable. Check your network or enable Apple Intelligence, then retry.": "无法获得真实语境结果。请检查网络或启用 Apple 智能后重试。",
    "All built-in translation routes failed. Check the language capability and try again.": "所有内置翻译路径均失败。请检查语言能力后重试。",
    "AI context": "AI 语境",
    "Accessibility": "辅助功能",
    "Accessibility is required": "需要辅助功能权限",
    "Allow Accessibility": "允许辅助功能",
    "Allow Screen Recording": "允许屏幕录制",
    "Apple Translation": "Apple 翻译",
    "Back": "返回",
    "Both required permissions must remain enabled.": "必须保持两项必需权限均已启用。",
    "Built-in translation": "内置翻译能力",
    "Chinese → English": "中文 → 英文",
    "Check online again": "重新检查在线解释",
    "Close": "关闭",
    "Cloud": "云端",
    "Cloud context quota resets at %@.": "云端语境额度将在 %@ 重置。",
    "Cloud context quota is exhausted. Try again after it resets.": "云端语境额度已用完，请在额度重置后重试。",
    "Cloud · %d remaining": "云端 · 剩余 %d 次",
    "Context insight": "语境解释",
    "Context insight is temporarily unavailable.": "语境解释暂时不可用。",
    "Continue": "继续",
    "Copy": "复制",
    "English and Chinese are detected automatically": "自动识别英文与中文",
    "English → Chinese": "英文 → 中文",
    "Explain this word in its sentence": "解释这个词在当前句子中的含义",
    "Great — keep holding for a moment.": "很好，再保持一下。",
    "Hold Left Option and hover": "按住左 Option 并悬停",
    "Hold Left Option and keep the pointer over English or Chinese text. Pointrans detects the language and shows the translation beside your pointer.": "按住左 Option，把光标停在英文或中文文字上。Pointrans 会自动识别语言，并在光标旁显示翻译。",
    "Hover delay": "悬停延迟",
    "Language capability is ready": "语言能力已就绪",
    "Language preparation could not finish. Check your connection and try again.": "语言能力准备失败。请检查网络后重试。",
    "Left Option recognized": "已识别左 Option",
    "Local definition": "本地释义",
    "Looking up this word…": "正在读取这个词…",
    "Never sends text online": "绝不在线发送文字",
    "No supported word was found.": "光标处没有可识别的中英文词语。",
    "Not now": "暂不使用",
    "Offline dictionary": "本地词典",
    "Offline dictionary · OCR": "本地词典 · OCR",
    "On-device": "设备端",
    "On-device AI": "设备端 AI",
    "On this Mac": "这台 Mac",
    "Online": "在线",
    "Online context explanation": "在线语境解释",
    "Online explanation couldn't finish.": "在线解释暂时未能完成。",
    "Online explanation needs a service update.": "在线解释服务需要更新。",
    "Open Control Center": "打开控制中心",
    "Open Settings": "打开设置",
    "Open System Settings": "打开系统设置",
    "Pause Translation": "暂停翻译",
    "Permission granted": "权限已授予",
    "Pinned": "已固定",
    "Point at a word. Understand it.": "指向一个词，即刻理解。",
    "Press Left Option once to continue": "按一下左 Option 继续",
    "Pointrans could not create its menu bar item and will quit.": "Pointrans 无法创建菜单栏图标，将自动退出。",
    "Pointrans could not start": "Pointrans 无法启动",
    "Pointrans is preparing Apple's on-device translation languages. This built-in capability must be ready before the guided experience.": "Pointrans 正在准备 Apple 设备端中英翻译语言。完成后才能进入引导体验。",
    "Pointrans needs attention": "Pointrans 需要处理",
    "Pointrans can use an online explanation with only this word and its sentence. It never sends a screenshot or the app you're using.": "Pointrans 可以只用这个词和所在句子在线生成解释；绝不会发送截图或你正在使用的应用信息。",
    "Pointrans is reading the sentence. No other action is needed.": "Pointrans 正在理解这句话，无需进行其他操作。",
    "Pointrans will explain this exact use.": "Pointrans 会解释这个词在当前句子里的含义。",
    "Preparing English and Chinese": "正在准备中英语言能力",
    "Preparing language capability…": "正在准备语言能力…",
    "Pronounce": "朗读",
    "Quit": "退出",
    "Quit and reopen Pointrans": "退出后重新打开 Pointrans",
    "Quit Pointrans": "退出 Pointrans",
    "Reading…": "正在取词…",
    "Reading the word under your pointer…": "正在读取光标下的单词…",
    "Ready": "就绪",
    "Ready to translate": "可以翻译",
    "Required": "必需",
    "Required for text inside images, PDFs, and apps that do not expose readable text. Only a small area near the pointer is processed on this Mac; screenshots are never saved or uploaded.": "读取图片、PDF 和无法提供文字的应用时必需。只在这台 Mac 上处理光标附近的小范围画面；截图绝不会保存或上传。",
    "Required to listen for Left Option and read the word under your pointer.": "监听左 Option 并读取光标下的文字时必需。",
    "Restoring text detection…": "正在恢复取词监听…",
    "Restart Pointrans to finish this permission. Your setup progress is saved.": "请重新启动 Pointrans 以完成此权限设置。你的设置进度已保存。",
    "Resume Translation": "继续翻译",
    "Retry": "重试",
    "Screen Recording": "屏幕录制",
    "Screen Recording is required": "需要屏幕录制权限",
    "See what it means in this sentence": "看看它在这句话里是什么意思",
    "Setup finishes automatically after the two actions.": "完成上面两个动作后会自动结束设置。",
    "Setup is required": "需要完成首次设置",
    "Starting…": "正在启动…",
    "Step %d of 5": "第 %d 步，共 5 步",
    "Text detection needs attention": "取词监听需要处理",
    "The built-in dictionary is missing or damaged. Reinstall Pointrans.": "内置词典缺失或损坏，请重新安装 Pointrans。",
    "The blue word is the target. Pointrans responds while Left Option is held.": "蓝色单词就是目标；按住左 Option 时，Pointrans 会立即响应。",
    "The guided action did not finish. Keep the pointer on the sample and try again.": "引导操作尚未完成。请把光标停在示例目标词上后重试。",
    "The required Apple Translation language pair is unavailable on this Mac.": "这台 Mac 无法使用必需的 Apple 中英翻译语言。",
    "The selected text cannot be analyzed.": "无法分析所选文字。",
    "The explanation is not available on this Mac right now.": "这台 Mac 目前无法生成解释。",
    "The explanation is temporarily unavailable.": "解释暂时不可用。",
    "The word translation is complete, but the online explanation service is not ready for this version yet.": "上面的单词已经翻译完成，但在线解释服务尚未适配当前版本。",
    "The word translation is complete. Try this Mac again or check the online explanation.": "上面的单词已经翻译完成。可以重试这台 Mac，或重新检查在线解释。",
    "That's it — Pointrans is ready in your menu bar.": "就是这样，Pointrans 已在菜单栏就绪。",
    "This Mac couldn't create the extra explanation.": "这台 Mac 暂时无法生成进一步解释。",
    "This context cannot be analyzed on device.": "此语境无法在设备端分析。",
    "Today's cloud context quota is used up. On-device analysis remains available.": "今日云端语境额度已用完，设备端分析仍可使用。",
    "To continue, Pointrans can send only “breakthrough” and this sample sentence for an online explanation. It never sends a screenshot or the app you're using.": "如需继续，Pointrans 只会发送“breakthrough”和这句示例文字来在线生成解释；绝不会发送截图或你正在使用的应用信息。",
    "Translate the blue word": "翻译蓝色单词",
    "Translation is ready. Now ask what it means in this sentence.": "翻译好了。现在看看它在这句话里是什么意思。",
    "Translation is paused": "翻译已暂停",
    "Translation is temporarily unavailable. Try again.": "翻译暂时不可用，请重试。",
    "Translation unavailable": "翻译不可用",
    "Try again": "重试",
    "Try again on this Mac": "在这台 Mac 上重试",
    "Try it once. You're ready.": "试一次，就会用了。",
    "Turn off": "关闭",
    "Understanding this context…": "正在理解这段语境…",
    "Understanding this sentence…": "正在理解这句话…",
    "Unavailable": "不可用",
    "Use online explanation": "使用在线解释",
    "Used only when this Mac cannot explain": "仅在这台 Mac 无法解释时使用",
    "Waiting for System Settings…": "正在等待系统设置…",
    "Waiting for Left Option": "等待按下左 Option",
    "Move the pointer onto the blue word, then hold Left Option.": "把光标移到蓝色单词上，然后按住左 Option。",
}


def main() -> None:
    strings = {
        key: {
            "localizations": {
                "zh-Hans": {
                    "stringUnit": {"state": "translated", "value": value}
                }
            }
        }
        for key, value in sorted(ZH.items())
    }
    payload = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Generated {OUTPUT} with {len(strings)} localized strings")


if __name__ == "__main__":
    main()
