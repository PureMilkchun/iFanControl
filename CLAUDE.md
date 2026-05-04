# CLAUDE.md

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

- 菜单一次性构建 + 原地更新（`buildMenuOnce` + `updateDynamicMenuItems`），不要每 2 秒重建 NSMenu
- `BackgroundHardwareReader` 在后台线程执行硬件 I/O，NSLock 保护缓存
- `FanManager` 是 `@MainActor`，硬件调用**必须**在后台线程
- **不要给 `Process.waitUntilExit()` 加 DispatchSemaphore 超时**——曾引入线程竞争，导致温度读取卡住（CODE_AUDIT.md#6）
- 更新校验**只用 SHA256**，不要加文件大小校验（CDN 会改字节数，CODE_AUDIT.md#5）
- ZIP 包 app bundle 里**绝不能包含 config.json**（2026-04-27 教训：误带旧 config 导致误判无风扇）
- 开机自启动用 `SMAppService.mainApp.register()`，旧 LaunchAgent plist 首次启动时自动清理

## 构建与替换

```bash
swift build -c release
cp .build/release/MacFanControl iFanControl.app/Contents/MacOS/iFanControl
cp iFanControl.app/Contents/MacOS/iFanControl /Applications/iFanControl.app/Contents/MacOS/iFanControl
codesign --force --sign - /Applications/iFanControl.app
open /Applications/iFanControl.app
```

部署前先确认用户实际运行路径：`/Applications/iFanControl.app/`，不是开发目录（CODE_AUDIT.md#3）

## 发布纪律

发布**必须同步以下四项**，缺一不可：
1. 新 ZIP 包
2. 官网 `docs/iFanControl-macOS.zip`
3. `docs/update-manifest.json`
4. GitHub Release

不要只推 GitHub 代码就认为用户能收到更新。

## 官网部署

```bash
cd '/Users/puremilk/Documents/mac fancontrol/docs'
npx wrangler pages deploy ./ --project-name ifan --no-bundle --skip-caching
```

**禁止**：不要在 `docs/` 放 `_worker.js` 或 `_worker.bundle`（会覆盖 functions/ 自动构建）

详细规范见 `docs/DEPLOY.md`

## 统计后台部署

```bash
cd '/Users/puremilk/Documents/mac fancontrol/ifan-stats'
npx wrangler pages deploy ./ --project-name ifan-stats --no-bundle --skip-caching
```

数据库结构、表设计等细节见 `ifan-stats/` 目录内代码。

## 多语言

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
5. **发布前核对清单** — ZIP / 官网 / manifest / GitHub Release 四项必须同步
6. **部署前确认运行路径** — 用户跑的是 `/Applications/`，不是开发目录
