# iFanControl 固定记忆

关联时间戳记忆：`/Users/puremilk/Documents/mac fancontrol/macfan-control-v2/PROJECT_TIMELINE.md`  
读取建议：先读本文件，再读时间戳记忆，避免遗漏最新变更。

更新时间：2026-04-26

## 1. 项目当前基线

iFanControl 是一个面向 Apple Silicon 带风扇机型的风扇控制工具，当前长期方向是：

- 仅面向带风扇的 M 系列 Mac
- 支持自动 / 手动模式
- 支持 5 点风扇曲线编辑
- 支持温度源选择
- 支持安全兜底转速
- 支持应用内自动更新
- 支持中英文切换（菜单切换，重启生效）
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
- 正式版本：`2.8.28`

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
- 官网下载入口当前固定指向：`./download`（由 Pages Functions 302 到 ZIP 并累计下载计数）
- 应用内更新链路从 `update-manifest.json` 读取 ZIP
- 当前正式策略是”首装与更新均走 ZIP”（全链路 ZIP）
- 官网统计接口：
  - 心跳上报：`POST /api/heartbeat`（匿名活跃统计）
  - 统计查看：`GET /api/stats`（需 `Authorization: Bearer <STATS_ADMIN_TOKEN>`）

### Cloudflare Pages Functions 部署纪律（重要）

**核心教训**：`docs/functions/` 目录中的 JS 文件不会被 Cloudflare Pages 自动处理。必须通过显式构建生成 `_worker.js`，然后用 `--no-bundle` 部署。

**正确部署流程**：
```bash
# 1. 编译 functions → _worker.js
cd '/Users/puremilk/Documents/mac fancontrol/docs'
npx wrangler pages functions build --outdir /tmp/ifan-build
cp /tmp/ifan-build/_worker.js _worker.js

# 2. 部署（必须带 --no-bundle --skip-caching）
cd '/Users/puremilk/Documents/mac fancontrol'
npx wrangler pages deploy docs --project-name ifan --no-bundle --skip-caching --commit-dirty=true
```

**禁止事项**：
- 不要在 `docs/` 中放置手动生成的 `_worker.bundle`（会导致路由错误）
- 不要不带 `--no-bundle` 部署已存在 `_worker.js` 的目录（会尝试重新打包并失败）
- 不要不带 `--skip-caching` 部署（wrangler 可能检测不到文件变化，显示 “0 files uploaded”）

**原因**：
- `_worker.bundle` 或 `_worker.js` 存在时，Cloudflare Pages 会跳过自动构建，直接使用该文件
- 旧的 `_worker.bundle` 路由表带有 `/functions/` 前缀，与实际请求路径不匹配，导致所有 API 返回 HTML
- 没有 `_worker.js` 时，`wrangler pages deploy` 不会自动从 `functions/` 目录构建，函数静默失效

## 5b. 统计后台（ifan-stats）

### 项目位置
- `/Users/puremilk/Documents/mac fancontrol/ifan-stats`

### 当前线上地址
- `https://ifan-stats.pages.dev`
- 自定义域名：`https://stats.puremilkchun.top`

### 架构
- 独立的 Cloudflare Pages 项目，与主站 `ifan` 共享同一个 KV 命名空间 `IFAN_STATS`
- 主站写入数据（heartbeat、download），统计后台读取数据
- 后端 API：`/api/dashboard/summary`（需要登录）
- 登录认证：用户名 + 密码 + TOTP 动态码

### 部署命令
```bash
cd '/Users/puremilk/Documents/mac fancontrol/ifan-stats'
npx wrangler pages deploy . --project-name ifan-stats --no-bundle --skip-caching --commit-dirty=true
```

### 当前功能
- 当前用户量（近 15 分钟）
- 累计下载 / 累计用户量
- 用户活跃趋势图（15 分钟粒度，支持 12h/24h/3d/7d/30d 范围选择）
- 下载活跃趋势图（15 分钟粒度，数据保留 7 天）
- 近 30 天趋势图（每日下载 + 每日活跃用户）
- 近 30 天明细表

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
- `v2.8.25` 已发布为统计能力版本，核心变化：
  - App 新增匿名活跃统计（默认开启，可在 `关于/帮助 -> 简介` 关闭）
  - 官网下载入口改为 `/download`，仅统计用户主动下载
  - 应用内更新 manifest 仍保持 ZIP，不改变更新契约
- CI `Swift` 工作流当前已恢复绿色，关键状态为：
  - 无测试文件时不再强制失败
  - `Package.swift` 已兼容 GitHub Runner 的 Swift 版本
  - `actions/checkout` 已升级到 `v5`

## 12. 当下结论（重要）

- 实测结论：DMG 路径下双击 `.command` 在网络下载场景容易被系统持续拦截，安装成功率不稳定。
- 当前最终策略：**全链路 ZIP**（官网 ZIP 下载 + 应用内 ZIP 更新）。
- 文档与更新器都已对齐到“拖拽 `install.sh` 到终端执行”。
- 当前 `2.8.25` 重点包含：
  - 自动检查更新不再被 24 小时 `last_check` 节流挡住
  - 启动后只要开启自动检查，就会请求 manifest，确保新版本能及时弹窗
  - 新增隐私优先统计：随机匿名 ID + version/build，每天最多一次，用户可关闭

## 13. 2026-04-25 新增事实

### GitHub Release 当前状态
- GitHub 最新正式 Release 已提升到 `v2.8.28`
- `v2.8.28` Release 地址：
  - `https://github.com/PureMilkchun/iFanControl/releases/tag/v2.8.28`

### 当前线上更新状态
- 官网当前自动更新 manifest：
  - `https://ifan-59w.pages.dev/update-manifest.json`
- 当前线上正式版本：
  - `2.8.28 / build 28`
- 当前线上 ZIP：
  - `https://ifan-59w.pages.dev/iFanControl-macOS.zip`
- 当前 `2.8.28` ZIP 校验：
  - `sha256 = 7b743bd8209686b6cfe732118b2d67b8e2717b8ea01d431f449915173abae1ad`
  - `size = 5971567`

### 匿名统计当前产品设计
- 设置项名称已统一为：
  - 中文：`匿名统计用户量`
  - 英文：`Anonymous user-count stats`
- 设置项右侧新增 `?` 说明按钮
- 点击 `?` 会弹出解释：
  - 只统计“有多少人在使用 iFanControl”
  - 仅发送随机安装 ID、版本号和 build
  - 不发送姓名、邮箱、序列号、设备名称
  - 文案允许适度幽默，明确说明开发者会因为有人在用而更开心
- 当用户尝试关闭匿名统计时：
  - 不直接关闭
  - 先弹出一次带幽默感的确认弹窗
  - 但用户坚持关闭时仍然允许关闭

### 匿名统计当前技术行为
- 旧逻辑“每天最多一次”已替换为：
  - 启动后延迟上报一次
  - 运行期间每 `15 分钟` 尝试上报一次
- App 端 key 已切换为：
  - `ifancontrol.privacy_stats.last_heartbeat_at`
- 官网端已开始长期保存：
  - 最近 `30 天` 的 `15 分钟聚合活跃值`
- 统计后台当前正确口径：
  - 默认显示“近 12 小时”
  - 每个点代表一个 `15 分钟活跃用户值`

### 当前发布纪律（再次强调）
- 只要 App 行为改动会影响用户实际体验，就不能只推代码：
  - 必须同步新包
  - 必须同步官网 ZIP
  - 必须同步 `update-manifest.json`
  - 必须同步 GitHub Release
- 否则用户不会真正收到更新，自动更新链路也不会生效

## 14. 多语言切换功能（2026-04-25 新增）

### 当前多语言方案
- 支持语言：中文 / English
- 存储位置：`UserDefaults`，key 为 `"ifancontrol.ui.language"`，值为 `"zh"` 或 `"en"`
- 生效方式：切换后需重启应用
- 首次安装时弹出语言选择弹窗（硬编码双语，不走 `appL10n`）

### 技术实现
- 三个模块各自定义 `currentLanguage` 变量（`private let`，无法跨模块共享）：
  - `main.swift`：`appL10n()`
  - `SensorCatalog.swift`：`sensorL10n()`
  - `FanCurveWindow.swift`：`fanCurveL10n()`
- 三处逻辑完全一致，都读取同一个 `UserDefaults` key
- 菜单中新增"语言 / Language"子菜单，位于"关于/帮助..."之后
- 切换后弹出"重启生效"提示，可选"立即重启"或"稍后"

### 已关闭的 PR
- PR #2（`lop1381997:codex/english-translation`，"add bilingual UI switcher"）已关闭
  - 该 PR 提出了更复杂的方案（`LocalizationManager` 单例 + 即时切换），但我们的 v2.8.28 已覆盖核心需求
  - 已用得体英文回复作者并关闭
