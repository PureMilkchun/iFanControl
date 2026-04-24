# iFanControl 固定记忆

关联时间戳记忆：`/Users/puremilk/Documents/mac fancontrol/macfan-control-v2/PROJECT_TIMELINE.md`  
读取建议：先读本文件，再读时间戳记忆，避免遗漏最新变更。

更新时间：2026-04-24

## 1. 项目当前基线

iFanControl 是一个面向 Apple Silicon 带风扇机型的风扇控制工具，当前长期方向是：

- 仅面向带风扇的 M 系列 Mac
- 支持自动 / 手动模式
- 支持 5 点风扇曲线编辑
- 支持温度源选择
- 支持安全兜底转速
- 支持应用内自动更新
- 首次安装与应用内更新统一走 ZIP 链路

## 2. 真实工作目录

### App 主工程
- `/Users/puremilk/Documents/mac fancontrol/macfan-control-v2`

这是当前可信的正式 App 开发基线。  
应用代码、正式打包、正式版本迭代，默认都应以这里为准。

### 官网目录
- `/Users/puremilk/Documents/mac fancontrol/docs`

这是 Cloudflare Pages 当前实际发布目录。

### DMG 实验线
- `/Users/puremilk/Documents/mac fancontrol/distribution-a`

这是安装体验实验目录，只用于验证，不再作为当前正式分发主线：
- DMG 外壳
- `Install.command` 入口行为
- App 首次启动引导页
- App 内完整卸载

### 不要作为主工作目录的地方
- `/Users/puremilk/Downloads/iFanControl-2.8`

这个目录只是下载包/测试包所在位置，不应再作为真正开发基线。

## 3. 当前版本与分发策略

### 当前正式稳定版本
- 正式版本：`2.8.24`

### 当前实验产物
- 实验 DMG：`/Users/puremilk/Documents/mac fancontrol/distribution-a/dist/iFanControl-experimental.dmg`

### 当前官网下载产物（固定文件名）
- `/Users/puremilk/Documents/mac fancontrol/docs/iFanControl-macOS.zip`

### 当前推荐分发策略
- 首次安装：使用 `ZIP`
- 自动更新：使用 `ZIP`

一句话：
- **首装走 ZIP**
- **更新走 ZIP**

## 4. 自动更新当前事实

当前自动更新仍使用 ZIP，而不是 DMG。

相关事实：
- Manifest：`https://ifan-59w.pages.dev/update-manifest.json`
- ZIP：`https://ifan-59w.pages.dev/iFanControl-macOS.zip`

代码位置：
- `/Users/puremilk/Documents/mac fancontrol/macfan-control-v2/Sources/MacFanControl/main.swift`

当前判断：
- 官网下载与应用内更新统一走 ZIP，减少 Gatekeeper 对 `.command` 的阻断影响
- 安装指导统一推荐“将 `install.sh` 拖入终端执行”

## 5. 官网当前事实

### 当前稳定上线地址
- `https://ifan-59w.pages.dev`

### 当前发布命令
```bash
cd '/Users/puremilk/Documents/mac fancontrol'
npx wrangler pages deploy docs --project-name ifan
```

### 官网关键规则
- `docs` 是唯一真实发布源
- 官网大改版式时，CSS 文件名必须升级，不要复用旧文件名
- 官网下载入口当前固定指向：`./iFanControl-macOS.zip`
- 应用内更新链路从 `update-manifest.json` 读取 ZIP
- 当前正式策略是“首装与更新均走 ZIP”（全链路 ZIP）

## 6. 图标与资源规则

### 当前正确 App 图标
- `/Users/puremilk/Documents/mac fancontrol/macfan-control-v2/icon.png`

### 旧图标
- `/Users/puremilk/Documents/mac fancontrol/icon.png`

继续工作时不要再误用旧图标。

## 7. 当前安装 / 卸载设计规则

### 正式主线
- 现有稳定链路为 ZIP（首装） + ZIP（自动更新）
- 安装指导统一为：终端拖拽 `install.sh`，不依赖双击 `.command`

### 实验线
- DMG 顶层保留：
  - `iFanControl.app`
  - `Applications`
  - `Install.command`
  - `Uninstall.command`
  - `README｜安装指南.txt`
- 目前仅用于实验验证，不作为官网主分发来源

### 卸载的长期正确方向
- 长期应以 **App 内完整卸载** 为主入口
- 不应依赖用户保留 DMG 才能卸载

## 8. 目录与操作纪律

继续工作时请优先守住：

- 不误改历史目录
- 不误用旧图标
- 不把 Downloads 里的测试包目录当主工程
- 官网改动只动 `docs`
- App 正式改动只动 `macfan-control-v2`
- 安装体验实验只动 `distribution-a`

## 9. 新窗口接手建议

如果在新窗口继续接力，建议先阅读：

1. `/Users/puremilk/Documents/mac fancontrol/macfan-control-v2/PROJECT_MEMORY.md`
2. `/Users/puremilk/Documents/mac fancontrol/macfan-control-v2/PROJECT_TIMELINE.md`
3. 如继续做 App：`/Users/puremilk/Documents/mac fancontrol/macfan-control-v2/Sources/MacFanControl/main.swift`
4. 如继续做实验安装线：`/Users/puremilk/Documents/mac fancontrol/distribution-a/README.md`
5. 如继续做官网：`/Users/puremilk/Documents/mac fancontrol/docs/index.html`

## 10. 一句话总结

当前最重要的三个真实工作目录是：

- App 正式工程：`/Users/puremilk/Documents/mac fancontrol/macfan-control-v2`
- Web 正式工程：`/Users/puremilk/Documents/mac fancontrol/docs`
- 安装体验实验线：`/Users/puremilk/Documents/mac fancontrol/distribution-a`

## 11. GitHub 与 CI 当前事实

- 主仓库：`https://github.com/PureMilkchun/iFanControl`
- `v2.8.24` Release 现已改为 ZIP-only，现已提供：
  - `iFanControl-macOS.zip`
  - `iFanControl-macOS-2.8.24.zip`
- CI `Swift` 工作流当前已恢复绿色，关键状态为：
  - 无测试文件时不再强制失败
  - `Package.swift` 已兼容 GitHub Runner 的 Swift 版本
  - `actions/checkout` 已升级到 `v5`

## 12. 当下结论（重要）

- 实测结论：DMG 路径下双击 `.command` 在网络下载场景容易被系统持续拦截，安装成功率不稳定。
- 当前最终策略：**全链路 ZIP**（官网 ZIP 下载 + 应用内 ZIP 更新）。
- 文档与更新器都已对齐到“拖拽 `install.sh` 到终端执行”。
- 当前 `2.8.24` 重点包含：自动检查更新不再被 24 小时 `last_check` 节流挡住；启动后只要开启自动检查，就会请求 manifest，确保新版本能及时弹窗。
