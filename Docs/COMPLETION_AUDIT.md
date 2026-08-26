# Pointrans 2.0 完成度审计

记录日期：2026-08-27

## 已完成并有自动化证据

- 原生 Xcode macOS App、Unit Test、UI Test targets，Swift 6 严格并发和 Universal 2 Release。
- 类型安全设置迁移、旧 DeepSeek Key/Endpoint 清理、原 Bundle ID 与权限身份保留。
- listen-only `CGEventTap`、悬停意图状态机、不可变请求、真正任务取消、Pinned 隔离与动画会话保护。
- AX 优先、ScreenCaptureKit + Vision OCR 回退、固定触发锚点及多显示器坐标转换。
- 175,157 条确定性 SQLite 词典、Apple Translation 增强、Foundation Models 优先与 Worker 自动回退路由。
- 结构化 `ContextInsight`、AI 关闭立即取消、云请求字段最小化、匿名 Keychain 安装身份。
- CuoStudio 品牌控制中心、Preview/Pinned 两态、浅色/深色令牌、系统语言跟随、无传统设置窗口。
- Worker token、输入限制、每日 30 次配额、UTC 重置、IP 限流、超时退款与日志脱敏；本地候选新增 fail-closed 健康/版本身份接口和干净提交部署门禁。
- Core 52/52、Worker 本地候选 15/15、Release 静态分析、Universal 2、严格签名、DMG 与静默安装验证。

## 尚未满足的最终门槛

- 生产云端 AI：Worker 可达且安装令牌可签发，但 DeepSeek 上游账号返回 HTTP 402；对外接口因此正确返回 `503 upstream_unavailable`。恢复上游计费后必须再次通过生产探针。
- Worker 精确身份上线：包含 `/health`、`/version` 与完整 Git SHA 校验的候选已通过本地检查，但尚未覆盖生产。部署前仍需取得 Cloudflare 账户套餐及共享容量的权威事实，不能用猜测代替生产预算判断。
- 真实桌面验收：遵守用户“不在开发过程中打开应用”的要求，build 205 没有被启动。状态栏点击、真实权限页、Safari/Chrome/Terminal/PDF/图片、双显示器、OCR 和 build 205 性能数据仍需用户允许一次受控交互验收。
- 公网分发：本地 DMG 为 ad-hoc 签名；Developer ID、公证与 stapling 只能在证书可用后执行。

因此，源码、自动化验证、本地 DMG 和静默安装已经交付，但在上述两个外部/交互门槛完成前，不应宣称 Pointrans 2.0 已达到正式公开发布状态。
