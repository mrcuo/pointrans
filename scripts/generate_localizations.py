#!/usr/bin/env python3
"""Generate the String Catalog used by the native app."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "Sources" / "Pointrans" / "Resources" / "Localizable.xcstrings"

ZH = {
    "A private, native point-to-translate companion for macOS.": "一款私密、原生的 macOS 指点翻译工具。",
    "About": "关于",
    "AI context": "AI 语境",
    "AI context is off": "AI 语境已关闭",
    "Accessibility": "辅助功能",
    "Accessibility powers the trigger and accurate text lookup. Screen Recording is used only when OCR fallback is needed.": "辅助功能用于监听触发键并准确读取文字；仅在需要 OCR 回退时使用屏幕录制。",
    "Available to download": "可下载",
    "Back": "返回",
    "Checking…": "正在检查…",
    "Chinese → English": "中文 → 英文",
    "Cloud": "云端",
    "Cloud fallback ready": "云端回退就绪",
    "Cloud fallback on demand": "云端回退按需使用",
    "Close": "关闭",
    "Context": "语境",
    "Context insight": "语境解释",
    "Context insight is temporarily unavailable.": "语境解释暂时不可用。",
    "Copy": "复制",
    "Direction": "翻译方向",
    "Disabled": "已关闭",
    "Done": "完成",
    "Enable": "启用",
    "English → Chinese": "英文 → 中文",
    "EN → ZH": "英 → 中",
    "English ↔ Chinese language pack": "中英翻译语言包",
    "Granted": "已授权",
    "Hold %@ and hover": "按住 %@ 并悬停取词",
    "Hover delay": "悬停延迟",
    "Hover translation": "光标翻译",
    "Language pair unavailable": "该语言组合不可用",
    "Last used: Cloud": "上次使用：云端",
    "Last used: On-device": "上次使用：设备端",
    "Left Command (⌘)": "左 Command (⌘)",
    "Left Command": "左 Command",
    "Left Control (⌃)": "左 Control (⌃)",
    "Left Control": "左 Control",
    "Left Option (⌥)": "左 Option (⌥)",
    "Left Option": "左 Option",
    "Left Shift (⇧)": "左 Shift (⇧)",
    "Left Shift": "左 Shift",
    "Local definition": "本地释义",
    "Looking up this word…": "正在查询这个词…",
    "No dictionary result. Prepare the language pack for device translation.": "本地词典暂无结果。准备语言包后可使用设备端翻译。",
    "OCR": "OCR",
    "OCR fallback only": "仅用于 OCR 回退",
    "On-device": "设备端",
    "On-device context ready": "智能语境已就绪",
    "On-device translation": "设备端翻译",
    "On-device available": "设备端可用",
    "On-device first · automatic fallback": "设备端优先 · 自动回退",
    "Paused": "已暂停",
    "Permissions & language pack": "权限与语言包",
    "Permissions": "权限",
    "Pinned": "已固定",
    "Point. Understand.": "一点，即懂。",
    "Pointrans could not start": "Pointrans 无法启动",
    "Preparation failed · Try again": "准备失败 · 请重试",
    "Prepare": "准备",
    "Preparing…": "正在准备…",
    "Pronounce": "朗读",
    "Quit": "退出",
    "Quit Pointrans": "退出 Pointrans",
    "Reading": "取词中",
    "Reading…": "正在取词…",
    "Ready": "就绪",
    "Ready on this Mac": "已在这台 Mac 上就绪",
    "Ready Pointrans": "准备 Pointrans",
    "Right Command (⌘)": "右 Command (⌘)",
    "Right Command": "右 Command",
    "Right Control (⌃)": "右 Control (⌃)",
    "Right Control": "右 Control",
    "Right Option (⌥)": "右 Option (⌥)",
    "Right Option": "右 Option",
    "Right Shift (⇧)": "右 Shift (⇧)",
    "Right Shift": "右 Shift",
    "Required": "需要授权",
    "Screen Recording": "屏幕录制",
    "Smart context is ready": "智能语境已就绪",
    "Text": "文字",
    "The built-in dictionary is missing or damaged. Reinstall Pointrans.": "内置词典缺失或损坏，请重新安装 Pointrans。",
    "The selected text cannot be analyzed.": "无法分析所选文字。",
    "This context cannot be analyzed on device.": "此语境无法在设备端分析。",
    "Today's cloud context quota is used up. On-device analysis remains available.": "今日云端语境额度已用完，设备端分析仍可使用。",
    "Trigger and text lookup": "触发与文字读取",
    "Trigger key": "触发键",
    "Translation is on": "翻译已开启",
    "Translation is paused": "翻译已暂停",
    "Two focused permissions": "只需两项必要权限",
    "Understanding this context…": "正在理解这段语境…",
    "Explain this word in its sentence": "解释它在当前句子中的含义",
    "Offline dictionary": "离线词典",
    "Offline dictionary · OCR": "离线词典 · OCR",
    "ZH → EN": "中 → 英",
}


def main() -> None:
    strings = {}
    for key, value in sorted(ZH.items()):
        strings[key] = {
            "localizations": {
                "zh-Hans": {
                    "stringUnit": {"state": "translated", "value": value}
                }
            }
        }
    payload = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Generated {OUTPUT} with {len(strings)} localized strings")


if __name__ == "__main__":
    main()
