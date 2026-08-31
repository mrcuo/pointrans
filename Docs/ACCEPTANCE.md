# Pointrans 2.0 验收记录

记录日期：2026-08-31
候选版本：Pointrans 2.0.0（215）

## 自动化验收结果

- `PointransCoreTests`：77/77 通过。使用无 App 宿主的 scheme，不创建状态栏项、窗口或 Pointrans 进程。
- Cloudflare Worker：TypeScript check 通过，Vitest 19/19 通过。
- 完整目标编译：Pointrans App、Core Tests 和 UI Tests 的 `build-for-testing` 通过；本轮没有执行会启动 App 的 UI Tests。
- Release 静态分析：`arm64 x86_64` 双架构 `xcodebuild analyze` 通过。
- 离屏 UI 烟雾测试：控制中心、Preview 和 Pinned 均通过 `NSHostingView` 渲染与有效像素检查。
- SQLite 词典：启动时执行 `quick_check(1)`、格式版本和双向非空表校验；交付验证再次执行 `PRAGMA quick_check`。
- Swift 和 Worker 的生成文件已重建，`git diff --check`、Info.plist、String Catalog JSON 和旧产品契约静态扫描均通过。
- AppIcon 已迁移为 macOS 26 原生 `AppIcon.icon`：纯黑 Icon Composer 背景只叠加一个透明白色 Symbol 图层，由系统应用唯一一次外形裁切；旧 `AppIcon.appiconset` 已删除。生成期校验 Icon Composer 结构、纯黑背景、透明度和安全区，避免再次交付带内嵌圆角容器的兼容图标。菜单栏 Symbol 和页头横版 Logo 仍由 `Pointrans_Logo_Design_Files` 内的矢量定稿无损复制。

自动化覆盖的关键产品契约：

- 欢迎步骤必须真实按下一次左 Option，胶囊即时点亮后自动推进；没有手动跳过按钮，右 Option 和其他修饰键不触发。
- 日常取词同样只有左 Option 触发；右 Option 和其他修饰键不触发。
- 英文、简体中文、混合文本中的光标词元自动决定方向；标点、空白和不支持文字不产生方向。
- 辅助功能或屏幕录制任一缺失都不能进入 `ready`。
- 屏幕录制已被系统接受但当前进程尚不可用时进入 `restartRequired`，引导阶段保持持久化。
- Apple 语言能力未完成时不能推进首次引导；引导完成时会再次校验双权限、语言能力、精确目标词、真实基础结果和真实语境结果。
- 首次引导不存在独立云端选择页；v2 的旧隐私阶段自动迁移到一体化体验。示例词由可见独立控件提供确定语义范围，不依赖 AX/OCR 读取自家界面，真实翻译留在引导页内，真实语境成功后自动完成。
- 在线解释授权只在设备端语境发生可恢复错误时原位询问；安全拒绝、无效输入、用户取消及已有决定不会重复弹出授权。
- 设备端不可用、在线网络失败、在线服务协议不兼容和额度耗尽保持为独立错误；“在这台 Mac 上重试”会显式禁止在线回退，不会因既有授权再次走回同一失败路径。
- 设备端 AI 在期限内成功、失败、1 秒超时以及忽略取消的迟到结果；Apple Translation 和词典的固定降级顺序。
- 云端同意、拒绝、撤销、断网、额度耗尽、安全拒绝和取消；撤销或关闭会话会取消正在运行的语境任务。
- Preview/Pinned 会话所有权、旧任务隔离、安全走廊、复制、Escape、拖动边界和 Pinned 期间拒绝新取词。
- event tap 创建失败后的有限指数恢复，以及暂停、权限撤销和退出时的监听/任务停止。
- 控制中心不包含触发键、方向、AI、语言包、模型、Provider 或 API Key 配置。
- Worker 安装注册只接受 `{}`；客户端不再上传 Keychain installation UUID 或应用版本。上下文请求只包含随机请求 ID、目标词、最多 600 UTF-16 上下文、精确目标范围和方向。

## 最终交付物

- DMG：[Pointrans-2.0.0.dmg](../dist/Pointrans-2.0.0.dmg)
- SHA-256 与大小：每次由最终 `package.sh` 产物重新计算，并在交付消息中报告，文档不保存会随源提交变化而失效的旧值。
- Bundle ID：`com.tailcasso.Pointrans`
- Build：215
- `LSUIElement = true`
- App 分类：`public.app-category.utilities`
- 架构：`x86_64 arm64`（Universal 2）
- 源身份：最终 DMG 内 `PointransSourceRevision` 必须是干净的 40 位提交哈希，并由交付门禁验证。
- 签名：本机 Apple Development 签名，Team ID `R8GNQHTB2Z`，Hardened Runtime；原始 App 和从 DMG 复制出的 App 均通过 `codesign --verify --deep --strict`，且无 `get-task-allow`。
- DMG 内容门禁：只读镜像包含一个 `Pointrans.app`、Applications 软链接和隐藏的 `.metadata_never_index` 标记；`dist` 不保留裸 App。

本地签名候选用于当前 Mac 的安装测试，不等同于 Developer ID 公网分发、公证和 stapling。

## 重复应用专项验证

- 所有裸 App 只允许存在于 `build/*.noindex` 下，交付验证会拒绝其他仓库 App 副本。
- 构建、测试和静态分析可能让 Xcode 临时向 Launch Services 注册产物；最终构建和交付验证现在会扫描整个仓库 `build` 树并注销每一个 `Pointrans.app`，而不是只清理主 DerivedData。
- 最终打包后执行 `lsregister -dump`，没有发现任何指向仓库路径的 Pointrans 记录。
- DMG 挂载副本和临时安装复制会在验证结束时注销并卸载。
- 构建和打包没有安装、启动、终止或替换 `/Applications/Pointrans.app`。

## 需要用户执行的真实安装验收

以下项目依赖真实桌面、TCC 和 Finder 行为，自动化不能代替，且按约定由用户操作：

1. 退出并删除旧安装，确认没有 Pointrans 进程与挂载中的旧 DMG。
2. 从最终 DMG 拖入 `/Applications`，推出 DMG，再启动安装副本。
3. 冷启动确认只出现一个菜单栏图标；首次引导依次完成左 Option 确认、辅助功能、屏幕录制、语言能力和一体化真实体验，不出现独立云端选择页。
4. 完成引导后重启，确认只常驻菜单栏；再次双击 App 必须显示独立控制中心。
5. 模拟菜单栏图标被系统遮挡，再次打开 App，确认仍可进入控制中心并退出。
6. 在 Safari、Chrome、Terminal、Preview/PDF、图片、全屏空间和双显示器上验证 AX/OCR 真实取词。
7. 撤销任一权限，确认立即停止取词并显示注意状态；恢复后无需重装。
8. 从右键菜单和控制中心分别退出，确认进程与监听完全消失，Finder 可立即删除 App。
9. 检查 Launchpad 与 Spotlight，确认只出现 `/Applications/Pointrans.app` 一个结果。

## Worker 与公开发行边界

- 本次完成的是 Worker 新隐私契约的本地实现和测试，没有执行生产部署。2026-08-31 实测生产 `/health`、`/version` 返回 405，空对象安装注册返回 400，确认生产端仍是旧契约。
- Build 213 会把该响应明确显示为“在线解释服务需要更新”，不再误报为用户网络故障；但设备端语境不可用的 Mac 仍需先部署新版 Worker，才能完成真实在线解释门槛。
- 正式公开发行还需要 Developer ID Application 签名、公证、stapling，以及从干净提交构建并核对 Worker `/health`、`/version` 的精确版本身份。
