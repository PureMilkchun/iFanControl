# CLAUDE.md

## 当前正式发布（2026-10-15）

维护者已审核并授权发布3.0.0/build71（对外3.0）。沿用已发布Beta70程序，仅更新版本/build/正式身份和签名，风扇控制策略、工具与有效程序区段保持。正式与Beta feed均指向stable71，Beta使用不可变71包，官网下载与/download均71；旧ZIP/manifest仍永久52。Production `56371256-511d-4101-9f6d-0a8d25713eab`，源码标签v3.0.0，记录见docs/releases/3.0.0-build71*.json。下一build大于71。下文Beta62～70发布段落是历史，不代表当前正式线路仍52。

## 项目概述

iFanControl 是一个面向 Apple Silicon Mac 的原生菜单栏风扇控制工具，支持自动/手动模式、5 点风扇曲线 + 3 预设切换、温度源选择、应用内更新、中英文切换、匿名活跃统计。

## 目录地图

| 目录 | 用途 | Claude 可改动 |
|------|------|--------------|
| `macfan-control-v2/` | App 主工程（当前目录） | 是 |
| `docs/` | 官网（Cloudflare Pages） | 单独操作 |
| `ifan-stats/` | 统计后台（Cloudflare Pages + D1） | 单独操作 |
| `distribution-a/` | 安装体验实验线 | 仅实验 |
| `~/Downloads/iFanControl-2.8` | 旧目录 | **不要动** |

## App 架构红线

- **UI意图保护**：主菜单“告诉开发者”下的邀请文本框是维护者明确保留的设计，用于鼓励反馈；点击进入独立窗口而不直接编辑是预期行为，不得当重复/假输入移除。
- **启动呈现边界**：等待面板必须先于硬件探测显示，按真实步骤更新，到菜单/控制循环初始化后收起；无假百分比/最低等待。更新回执仍按运行build校验，显示在面板收起之后。首次引导与无风扇提示仍保留；不要为缩短等待误改原硬件/遥测/安全逻辑。
- **状态时间语义**：recordedAt是最近一次状态记录写入时间，普通相同签名不会重写，force路径可强制记录；不能与“正常”并列呈现为过去才正常，不能为了UI时间刷新改控温/记录频率。68显示当前状态/配置模式，记录时间在明确标注的tooltip中。

- 菜单一次性构建 + 原地更新（`buildMenuOnce` + `updateDynamicMenuItems`），不要每 2 秒重建 NSMenu
- `BackgroundHardwareReader` 在后台线程执行硬件 I/O，NSLock 保护缓存
- `FanManager` 是 `@MainActor`，硬件调用**必须**在后台线程
- **不要给 `Process.waitUntilExit()` 加 DispatchSemaphore 超时**——曾引入线程竞争，导致温度读取卡住（CODE_AUDIT.md#6）
- 更新校验**只用 SHA256**，不要加文件大小校验（CDN 会改字节数，CODE_AUDIT.md#5）
- ZIP 包 app bundle 里**绝不能包含 config.json**（2026-04-27 教训：误带旧 config 导致误判无风扇）
- 开机自启动用 `SMAppService.mainApp.register()`，旧 LaunchAgent plist 首次启动时自动清理

## 构建与Git约定

遵循 `CONTRIBUTING.md`。main维持正式代码，codex/3.0-beta保存Beta开发基线；日常直接小步提交/推送开发分支，较大修改按需用任务分支和PR；禁止强推/删除长期分支，不要求构建/PR作为保存代码门槛。Beta标签与发布记录对应真实源码输入。构建workflow已停用、只保留手动触发，不得为了保存Git历史运行构建/测试/打包；用户明确要求本阶段只建立历史、追踪和回退。不能用Git推送触发部署。

App元数据来源为 `packaging/app/Info.plist`，不要修改本机生成的App来代替源码版本提交。

```bash
python3 scripts/build_app.py
python3 packaging/pkg/build.py --app build/iFanControl.app --tool kentsmc
```

产物位于build/与packaging/pkg/output/，不追踪二进制App/签名/Cloudflare缓存。本机历史文件保留；实验与反馈邮件不要混入公开提交。禁止自动替换用户实际安装的 `/Applications/iFanControl.app`；安装体验通过现有PKG路线验收。

## 发布纪律

发布必须同步最新 PKG、新通道 `docs/update-manifest-pkg.json`、GitHub Release 和官网下载入口。

旧通道 `docs/update-manifest.json` 永久停在 2.9.9/build52，旧 ZIP `docs/iFanControl-legacy-2.9.9.zip` 与兼容别名 `docs/iFanControl-macOS.zip` 必须永久保留；后续版本禁止覆盖它们。旧客户端先通过 ZIP 升至 2.9.9，再进入新 PKG 通道。发布前运行 `python3 packaging/pkg/verify_channels.py`，固定元数据为 `packaging/pkg/legacy-channel.json`。

不要只推 GitHub 代码就认为用户能收到更新。

### Beta 独立发布（2026-10-12 用户确认）

开发者手动本地安装 2.9.10/build62 作为种子版本，先只部署 Beta 线路。Beta 迭代只改 `update-manifest-beta.json`、独立含 build 的 PKG 与该 feed 的 no-store 规则；不要同步推进正式 manifest、`iFanControl-macOS.pkg`、`/download`、官网版本/时间线或正式 GitHub Release。正式/旧线路保持 2.9.9/build52，直到用户决定正式发布。

`output/release-candidate/channel-preview/` 包含待正式发布的 build62 文件，**不能整体部署为 Beta 测试线路**。首次 Beta 部署使用 `output/beta-bootstrap-62/site/`，以线上 Production 资产清单逐一校验后构建；后端 functions 保持原源码，保留与线上不同的本地文件，避免将无关工作顺带发布。后续 Beta build 必须大于 62；正式发布时 build 必须大于此前所有 Beta build。

## 官网部署

```bash
cd '/Users/puremilk/Documents/mac fancontrol/docs'
npx wrangler pages deploy ./ --project-name ifan --branch main --no-bundle --skip-caching
```

**禁止**：不要在 `docs/` 放 `_worker.js` 或 `_worker.bundle`（会覆盖 functions/ 自动构建）

详细规范见 `docs/DEPLOY.md`

## 统计后台部署

```bash
cd '/Users/puremilk/Documents/mac fancontrol/ifan-stats'
npx wrangler pages deploy ./ --project-name ifan-stats --no-bundle --skip-caching
```

数据库结构、表设计等细节见 `ifan-stats/` 目录内代码。

## 3.0 UI 设计约束（2026-10-13）

用户要求先全面梳理再改善。简洁、优雅、高效涵盖进入、等待、反馈、失败恢复和真实完成；现状与方案见 `docs/development/3.0-ui-audit.md`。保留PKG的系统完成勾与打开说明，不用自定义conclusion覆盖它，不在root安装脚本中自动启动GUI。检查/下载/校验/打开Installer不能提前宣称安装成功。

菜单一次构建原地刷新、即时展示偏好、转速显式应用、曲线关闭保存/预设切换通知都有现有理由。UI重构应明确这些语义，不能把有意的差异当bug一并改掉。安全窗口95℃与代码/历史110℃的差异应按真实规则统一说明，不能改控温来迁就文案。第一轮64/65行为验收通过但视觉被用户否定；第二轮已应用原生设计skill并发布Beta66，原从65→66验收。66记录见 `docs/development/3.0-ui-polish.md`。Beta67曾进一步精简主菜单并修复提示白边/放大勾，信息栏设置维持66原样；新记录见 `docs/development/3.0-ui-menu-notice.md`。Beta68恢复反馈邀请框并说明状态记录时间，记录见 `docs/development/3.0-ui-feedback-intent.md`；原58个非Beta-feed资产及后端保持，正式build52线路继续保留；Beta69放大帮助侧栏导航并收紧选择区域、添加官网按钮，记录见 `docs/development/3.0-ui-help-sidebar.md`；保留59个非Beta-feed资产和后端，正式/旧/download仍52，当前Beta70增加真实启动阶段面板，菜单/控制循环初始化后收起，再显示更新回执/首次引导；保留60个旧非Beta-feed资产，正式/旧/download仍52，记录见 `docs/development/3.0-ui-startup.md`，下一build须大于70。

## 多语言约定

中 / 英存储在 `UserDefaults("ifancontrol.ui.language")`，切换后需重启。三个模块各自定义 `currentLanguage`（main.swift / SensorCatalog.swift / FanCurveWindow.swift）。

## 收工流程

当用户明确表示「收工」时，自动执行以下更新，无需用户逐一指示：

1. **`PROJECT_TIMELINE.md`** — 在对应日期下追加本次会话的所有实质性改动（功能、修复、部署等），格式与现有条目一致
2. **`PROJECT_MEMORY.md`** — 更新版本号、架构基线、已知问题等章节，确保与当前代码状态一致
3. **`CLAUDE.md`** — 若本次会话引入了新的红线、教训或部署变更，同步更新本文件
4. **`CODE_AUDIT.md`** — 若本次会话产生了新的审查教训或误判记录，追加到对应章节
5. **其他文档** — 若改动涉及官网 `docs/` 或统计后台 `ifan-stats/` 的结构/部署规范，同步更新对应目录的 README 或 DEPLOY 文档

原则：只记录实质性变更，不记录过程性探索。

## Claude 执行规则

1. **先理解，后判断** — 读完整调用链和数据流，再下结论；不要只看局部代码就标记为 bug
2. **区分确信度** — 确认的 bug 直接说，疑似问题用试探语气（"这里的设计意图是什么？"）
3. **移动状态变量前画调用图** — `hasXxx` / `isXxx` guard flag 位置敏感，移错会引发无限递归（CODE_AUDIT.md#2）
4. **不要预防性加固** — 如果原始代码工作正常，不要为了"理论上更安全"而改动（CODE_AUDIT.md#6）
5. **发布前核对清单** — 新通道 / PKG / 官网 / GitHub Release 必须同步，旧通道版本与哈希不得改动
6. **部署前确认运行路径** — 用户跑的是 `/Applications/`，不是开发目录
