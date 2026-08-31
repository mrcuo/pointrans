# Pointrans 2.0 完成度审计

记录日期：2026-08-31

## 已完成的重构

### 应用外壳

- AppKit delegate 由进程级生命周期对象强持有，启动时同步创建唯一 `NSStatusItem`。
- 首次引导、控制中心和翻译浮层是三个职责独立的窗口；完成引导后的冷启动不主动显示普通窗口。
- 菜单栏左键切换控制中心，右键提供打开、暂停/继续和退出。
- 状态项暂时不可见不会终止进程；显式重开始终显示控制中心，启动后缺少可用锚点也会自动提供控制中心恢复入口。
- 退出路径统一停止 event tap、悬停、AX/OCR、基础翻译、设备 AI、Worker 请求和窗口任务。

### 强制首次引导

- 使用版本化 onboarding v3，旧 `didCompleteOnboarding`、v1 或 v2 不能跳过新流程；v2 独立隐私页状态会迁移到一体化体验。
- 五阶段流程已实现：认识产品、辅助功能、屏幕录制、自动语言能力、一体化强制真实体验。独立云端路由页已经删除。
- 双权限与双向 Apple Translation 能力均为硬门槛；系统权限需重启时保存当前阶段并阻止继续。
- 强制体验把 `breakthrough` 渲染为始终可见的独立目标控件，并直接向取词控制器提供其精确语义范围，不再让 AX/OCR 读取自家界面；页面内实时展示按键、读取、真实翻译、语境和完成状态。
- 真实翻译完成后会话固定留在引导页，用户点击自然语言语境入口；真实语境成功后自动完成，不存在额外完成按钮。
- 离开体验阶段会立即关闭面板并停止全局监听，防止未完成引导时处理其他应用。
- 写入完成状态前再次校验双权限、语言能力和两类真实结果。

### 固定手势与统一状态

- 触发键固定为 Carbon 左 Option 键码，删除了触发键持久化和 UI；首次引导欢迎页以本地 AppKit 事件确认真实左 Option 按下，立即点亮胶囊并自动推进，不依赖尚未授予的辅助功能权限。
- `AppReadinessResolver` 统一菜单栏和控制中心的状态优先级：onboarding、paused、双权限、语言准备、监听恢复/失败和 ready。
- event tap 只转发必要事件，空闲鼠标移动不进入 MainActor；监听失败采用 0.5、1、2、4、8 秒有限恢复。
- 任一权限撤销都会停止监听和当前任务；暂停同样取消会话但保留状态栏入口。

### 取词与翻译

- AX 优先，失败后才走 ScreenCaptureKit + Vision；截图只在本机瞬时处理。
- OCR 只接受光标实际命中的带少量容差词元，不再把空白或标点吸附到附近单词。
- tokenizer 按光标词元自动检测英文/简体中文并决定方向，限制上下文为 600 UTF-16 单位且不切断组合字符。
- 基础路由并行预取但严格决策为：设备端 AI 最多 1 秒、Apple Translation、本地词典。
- 一次性 deadline gate 确保忽略取消的迟到 AI 既不会拖住降级，也不能覆盖已经显示的结果。
- 三路失败会短暂显示明确错误，不留下空白窗口。

### Preview、Pinned 与语境解释

- Preview 有 200ms 读取反馈、安全走廊、外部点击/Escape/超时关闭和新会话隔离。
- Pinned 支持文本选择、滚动、朗读、完整/选择复制、拖动、关闭，并在存在期间拒绝新取词。
- 语境解释只由点击触发；设备端优先，仅 unavailable/transient 且用户已同意时回退 Worker。
- 在线解释授权只在设备端发生可恢复错误的原位置询问，不再提前要求用户理解“云端回退”；日常 Pinned 与首次引导共用同一按需授权策略。
- 无效输入、安全拒绝、取消不触发云端；撤销同意、关闭、暂停和新会话都会取消语境任务。
- 云端结果保留来源、剩余额度和重置时间；断网与额度耗尽不删除基础翻译，也不循环请求。
- 设备端不可用、在线网络失败、在线服务协议不兼容和额度耗尽使用不同领域状态；设备端重试可显式禁止在线回退，避免已有同意状态把用户循环送回故障 Worker。

### 隐私、持久化和 Worker

- 仅持久化暂停、悬停延迟、云端语境同意、版本化 onboarding，以及既有 Keychain 身份/令牌。
- 删除触发键、翻译方向、AI 开关、Provider、模型、Endpoint、API Key 和语言包人工选择等旧键。
- Worker 注册只接受空对象并在服务端生成随机匿名额度身份；客户端既有 Keychain installation UUID 保持本地，不再上传。
- `/v1/context` 只包含随机请求 ID、词、有限上下文、精确 UTF-16 范围和方向；无截图、应用名称、Bundle、硬件或设备身份字段。
- Worker 输入校验、原子日额度、IP 边界、上游超时退款和脱敏日志已通过 19 项测试。

### 构建与重复项治理

- 保持 Bundle ID `com.tailcasso.Pointrans`、UserDefaults 域、Keychain 和 TCC 身份。
- AppIcon 使用原生 `AppIcon.icon`，由 Icon Composer 的纯黑背景和单一透明白色 Symbol 图层组成；旧预合成 `AppIcon.appiconset` 已删除，系统只应用一次外形裁切。菜单栏 Symbol 和页头横版 Logo 继续来自 `Pointrans_Logo_Design_Files` v1.1 定稿。
- Release 为 Universal 2，启动时验证只读 SQLite 词典完整性。
- `build.sh` 只输出 `build/Artifacts.noindex/Pointrans.app`；`package.sh` 只在 `dist` 留版本化 DMG。
- DMG 只提供一个 Pointrans 和 Applications 链接；构建与打包不触碰 `/Applications`。
- 构建结束现在扫描并注销整个仓库 `build` 树里的所有 Pointrans App，覆盖 Core Test、UI Test、Analyze 和 Release 各类 DerivedData，解决 Launchpad/Spotlight 多个 Pointrans 的根源。

## 自动化证据

- Core：77/77。
- Worker：TypeScript check + 19/19。
- App/Core/UI Tests：完整 `build-for-testing` 成功，UI Tests 仅编译未运行。
- Release：arm64/x86_64 静态分析成功。
- DMG：2.0.0（215）；严格签名、架构、现代图标、词典、挂载复制和无调试 entitlement 由 `package.sh` 全部验证。
- Launch Services：最终打包后没有任何仓库 Pointrans App 注册记录。

## 尚未完成的外部门槛

- 未执行安装、启动、权限点击、卸载或真实应用取词；这些步骤按约定由用户完成。
- 未把 Worker 新契约部署到生产；实测生产端仍返回旧协议的 405/400，因此设备端语境不可用时的真实在线解释仍需部署后验收。
- 未取得 Developer ID Application 公网发行签名，也未执行 Apple 公证与 stapling。
- Safari、Chrome、Terminal、PDF、图片、全屏、双显示器、真实 Apple Intelligence、真实语言包下载、菜单栏遮挡恢复、Launchpad/Spotlight 单项和退出后立即删除仍属于安装候选的最终桌面门槛。

结论：计划中的源码重构、自动化覆盖和本地安装候选已完成；公开发布状态必须等待 Worker 生产部署、用户真实安装矩阵和 Developer ID/公证三类外部门槛全部通过。
