# Pointrans 2.0 验收记录

记录日期：2026-08-27

## 已自动验收

- Core Unit Tests：52/52 通过；使用无 App 宿主的 `PointransCoreTests` scheme，执行过程不会启动 Pointrans。
- 离屏 UI 渲染：控制中心 360pt 浅色、Preview 360pt 浅色、Pinned 420pt 深色均由无窗口 `NSHostingView` 渲染并完成人工目视检查；修复了英文悬停延迟标签裁切和系统 `Menu` 收缩导致的触发键错位。
- macOS UI Tests：测试代码已编译；根据当前无干扰开发约束，本轮未执行会启动 App 的 UI 测试。
- Cloudflare Worker：当前生产路由与 Durable Object 已部署。新的本地候选通过 TypeScript check、Vitest 15/15 和 Wrangler dry-run；增加了 fail-closed 的 `/health`、`/version` 以及“仅从干净提交部署并核对精确 SHA/版本”的门禁。该候选尚未覆盖当前生产 Worker。
- SQLite 词典：英中 54,045 条，中英 121,112 条，共 175,157 条；两次独立构建逐字节一致，`integrity_check = ok`，运行时只读主键索引查询。
- Release：`Pointrans 2.0.0 (205)`，Bundle ID `com.tailcasso.Pointrans`，`LSUIElement = true`，固定生产地址为 `https://pointrans-api.cuostudio.workers.dev`。
- 架构：`x86_64 arm64`（Universal 2）。
- 静态分析：Release 配置同时覆盖 `arm64 x86_64`，`xcodebuild analyze` 通过。
- 签名：原始 App、安装 App 与从 DMG 复制出的 App 均通过 `codesign --verify --deep --strict`；Release 不包含 `get-task-allow` 等调试 entitlement。
- DMG：只读挂载、Applications 软链接与临时安装复制验证通过。
- DMG SHA-256：`b6275bce71e725430666a03966e0ba3233a4548af17a1da06068c0891fc333ec`。
- 本机安装：仅保留 `/Applications/Pointrans.app`，安装后未启动；最终核验时不存在 Pointrans 进程。废纸篓内容未移动、未删除。
- Idle CPU 基线：build 203 的最终签名 App 连续 5 分钟、每 5 秒采样，共 60 次；平均 0.093%，最高单次 1.4%。build 205 按用户要求未启动，因此未伪造或沿用为 build 205 的运行时结果。

## 需要真实权限/设备环境的手工验收

以下项目不能由隔离的自动化测试代替，正式公开发布前需在授予系统权限的目标 Mac 上执行：

- Safari、Chrome、Terminal、Preview PDF、图片和全屏空间的真实 AX/OCR 取词。
- 水平、垂直及 Retina 双显示器布局的真实坐标与面板锚定。
- Accessibility 缺失、Screen Recording 缺失、断网、语言包缺失的系统交互。
- Apple Intelligence 开启/关闭及真实 Foundation Models 安全拒绝。
- AX + SQLite、OCR、Apple Translation、设备端 AI、云端 AI 的真实 p95 延迟采样。

## 外部部署状态

- 生产地址：`https://pointrans-api.cuostudio.workers.dev`
- 当前生产 Worker 版本：`75dbc052-2e01-440d-b931-b12f835abad2`
- 本地候选：15/15 tests 通过；生产部署前必须确认 Cloudflare 账户套餐与共享容量，再以已提交的完整 Git SHA 部署并通过 `/health`、`/version` 精确身份核验。
- Durable Object migration、匿名安装 HMAC 令牌、UTC 日额度和 IP 限流均已部署。
- `INSTALLATION_SECRET` 与 `DEEPSEEK_API_KEY` 均以 Cloudflare encrypted secret 保存；仓库和 DMG 中不包含 Secret。
- 生产端到端验收：2026-08-27 使用固定测试词和固定句子复测，`POST /v1/installations` 返回 201，`POST /v1/context` 返回 200，`ContextInsight` 结构有效，云端 AI 已恢复。探针未发送截图、应用信息或用户内容。
