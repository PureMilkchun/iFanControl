# iFanControl 固定记忆

关联时间戳记忆：`/Users/puremilk/Documents/mac fancontrol/macfan-control-v2/PROJECT_TIMELINE.md`
读取建议：先读本文件，再读时间戳记忆，避免遗漏最新变更。

更新时间：2026-05-04

## 1. 项目当前基线

iFanControl 是一个面向 Apple Silicon 带风扇机型的风扇控制工具。

核心功能：
- 自动 / 手动模式
- 5 点风扇曲线编辑 + 3 预设 Tab 切换（双击重命名，切换即时生效，关闭自动保存）+ 拖拽时实时显示温度/RPM
- 温度源选择 + 安全兜底转速
- 应用内自动更新（ZIP 链路）
- 中英文切换（菜单切换，重启生效）
- 匿名活跃统计（每日上报，可关闭）
- 告诉开发者（菜单栏反馈入口）
- 开机自启动（SMAppService 原生登录项 API，系统设置中可直接管理）
- 信息栏展示设置（完整/简洁两种模式，存 `ifancontrol.ui.display_mode`，切换即时生效）

当前版本：`2.9.7` / build 43

### build 43 说明

- **GitHub / 官网 / App 内更新真实版本**：`2.9.7 / build 43`
- **新增功能**：迷你双行显示模式（菜单栏两行紧凑显示：上行转速，下行温度｜模式字母）
- **UI 改进**：菜单分组重排、控制状态卡片颜色编码、菜单宽度收窄
- **Bug 修复**：温度源选中态同步

### build 41 说明

- **GitHub / 官网 / App 内更新真实版本**：`2.9.5 / build 41`
- **新增功能**：信息栏展示设置（完整/简洁两种模式）

### build 40 灰度说明

- **GitHub / 官网 / App 内更新真实版本**：`2.9.5 / build 40`
- **灰度方式**：不增加 build 号，直接替换 build 40 的 ZIP 包与官网下载包
- **公开口径**：
  - 心跳 / 后台统计相关改动，对外统一写成”修复若干问题，提升整体稳定性”
  - 其他用户可感知改动（如关屏稳定性、控制状态显示、启动误报修复）继续正常写明
  - `update-manifest.json` 保持纯泛化文案；GitHub Release 与官网时间线可保留非心跳类具体改动

## 2. 真实工作目录

| 用途 | 路径 |
|------|------|
| App 主工程 | `/Users/puremilk/Documents/mac fancontrol/macfan-control-v2` |
| 官网 | `/Users/puremilk/Documents/mac fancontrol/docs` |
| 统计后台 | `/Users/puremilk/Documents/mac fancontrol/ifan-stats` |
| 安装体验实验线（仅实验） | `/Users/puremilk/Documents/mac fancontrol/distribution-a` |
| ~~不要当主工程~~ | `/Users/puremilk/Downloads/iFanControl-2.8` |

## 3. 分发策略

- **首装走 ZIP，更新走 ZIP**（全链路 ZIP）
- 安装指导：将 `install.sh` 拖入终端执行
- 官网下载入口：`https://ifan-59w.pages.dev/download`（302 到 ZIP）
- 自动更新 manifest：`https://ifan-59w.pages.dev/update-manifest.json`
- GitHub Release：`https://github.com/PureMilkchun/iFanControl/releases`

## 4. 官网部署纪律

详细部署规范见 `docs/DEPLOY.md`。

```bash
cd '/Users/puremilk/Documents/mac fancontrol/docs'
npx wrangler pages deploy ./ --project-name ifan --no-bundle --skip-caching
```

**禁止**：不要在 `docs/` 放 `_worker.js` 或 `_worker.bundle`（会覆盖 functions/ 自动构建）

### 官网板块结构

1. Landing Screen（首页）
2. Iteration Section（开发者也是用户本身）
3. **Timeline Section（项目时间线）** — 默认展示最近 1 天，可展开查看全部
4. Showcase Section（界面展示）
5. Support Modal（支持作者）

### 时间线维护规范

- 数据文件：`docs/timeline.json`，JS 通过 `fetch("./timeline.json")` 加载，失败时静默不显示
- 发布新版本时，在 `timeline.json` 对应日期的 `entries` 开头插入新条目；新的一天则新建日期组放在数组最前面
- **文案规范**：`desc` 直接使用 GitHub Release Notes 的内容，面向用户的正式表述，不暴露内部实现细节
- 时间用 GitHub Release 的 `published_at` 转换为本地时间（HH:MM）
- HTML/CSS 不需要改动
- 默认展示天数：`TIMELINE_RECENT_DAYS = 1`（在 `index.html` 的 JS 中配置）

### CSS 缓存策略

CSS 文件名包含日期（如 `styles.20260427a.css`）。CSS 有改动时需重命名文件并更新 `index.html` 中的 `<link>` 引用，避免 Cloudflare CDN 缓存旧版本。

## 5. 统计后台（ifan-stats）

- 位置：`/Users/puremilk/Documents/mac fancontrol/ifan-stats`
- 线上：`https://ifan-stats.pages.dev`（自定义域名 `stats.puremilkchun.top`）
- 架构：Cloudflare Pages + D1（database_id: `383dadba-cf12-47f1-bf53-dbf2f087458f`）
- 部署：`npx wrangler pages deploy ./ --project-name ifan-stats --no-bundle --skip-caching`

### 数据库表
- `counters`：通用计数器（每日下载、活跃用户、版本计数、登录限流）
- `flags`：去重标记（INSERT OR IGNORE）
- `bucket_activity`：15 分钟桶活跃（install_hash + day + bucket_index + version）
- `series_15m`：15 分钟时序（active / download）
- `feedback`：用户反馈（install_hash + content + email + version + created_at）
- `user_index`：用户编号映射（id 自增 PK + install_hash UNIQUE + first_seen），心跳端点新安装时自动写入，存量数据首次请求时回填

### 后台面板顺序
1. 卡片数据（当前用户/下载/累计/刷新时间）
2. 当前版本分布（饼图：深色切片使用白色文字，基于亮度阈值自适应；支持暗色模式双色调色板）
3. **用户反馈**（带勾选框，勾选后变灰+删除线，移到末尾；状态存 localStorage；支持"隐藏已归档"按钮切换显示/隐藏已勾选条目）
4. 用户活跃趋势（支持按版本/用户编号筛选：下拉选版本或用户编号后图表只显示对应数据，tooltip 单用户模式显示「#N 活跃：是/否」；清除筛选恢复全部）
5. 近 30 天趋势（只显示有数据的天，底部带日期标签）
6. 近 30 天明细（隐藏全零行，日期由近至远排列）
- **暗色模式**：顶栏手动切换（🌙/☀），偏好存 `localStorage("ifan_theme")`；`<head>` 内联脚本防闪烁；Canvas 绘图通过 `getChartColors()` 同步主题色
- **累计用户量**：显示今日新增用户数（`今日 +N`）

### 用户详情页（`user.html?id=N`）

- 入口：主页用户筛选旁「详情」按钮；支持 `←`/`→` 箭头 + 下拉快速切换用户
- SPA 式切换：`history.pushState` + `sessionStorage` 缓存用户列表，切换仅 1 次 fetch
- 卡片（2 组 8 个）：用户画像 + 排名、核心指标
- 活跃日历：≤30 天水平条纹视图（自适应条形图 + X 轴刻度），"全部"保留 GitHub 周网格
- 活跃时段：24 小时折线图 + Canvas tooltip
- 版本升级时间线（HTML/CSS）、用户反馈表格、用户故事叙事
- 后端 API：
  - `GET /api/dashboard/user?id=N`：单用户聚合数据
  - `GET /api/dashboard/users`：用户列表 + total_buckets（batch 查询，避免 D1 子查询超时）

### 版本统计口径
- 版本分布表：使用 `ROW_NUMBER() OVER (PARTITION BY install_hash ORDER BY day DESC, bucket_index DESC)` 确保每个用户只计一次（取最新版本），避免升级用户被重复计数
- hover 版本分布：每个桶/每天按 `install_hash` 去重
- 隐私设计：用户 UUID 仅存 SHA-256 哈希，服务端无法反推原始 ID

## 6. App 构建与打包

### iFanControl.app 是构建产物

`macfan-control-v2/iFanControl.app/` 从 `.build/` 复制，不是源码。重建方法：
```bash
swift build -c release
mkdir -p iFanControl.app/Contents/MacOS iFanControl.app/Contents/Resources
cp .build/release/MacFanControl iFanControl.app/Contents/MacOS/iFanControl
cp iFanControl-2.8.27/iFanControl.app/Contents/Resources/icon.png iFanControl.app/Contents/Resources/
git checkout iFanControl.app/Contents/Info.plist  # 然后改版本号
codesign --force --sign - iFanControl.app
```

### ZIP 打包规范

完整安装包必须包含（参考 `iFanControl-2.8.27/`）：
- `iFanControl.app/`（binary + icon.png + Info.plist，**不含 config.json**）
- `install.sh`、`kentsmc`
- `Install.command`、`diagnose.command`、`diagnose.sh`、`uninstall.command`、`uninstall.sh`
- `LICENSE`、`README.md`、`README_EN.md`、`安装说明.html`

打包命令：
```bash
mkdir /tmp/staging && cp -R iFanControl.app /tmp/staging/
cp install.sh kentsmc LICENSE README.md README_EN.md Install.command diagnose.command diagnose.sh uninstall.command uninstall.sh iFanControl-2.8.27/安装说明.html /tmp/staging/
cd /tmp/staging && zip -r /tmp/iFanControl-macOS-X.Y.Z.zip .
```

### config.json 教训

**ZIP 包的 app bundle 里绝不能包含 config.json。** 2026-04-27 实测：打包时误带了旧 config.json，导致应用读到错误配置，误判为"无风扇"。应用应在首次运行时自动生成 config.json。

### 更新校验教训

**SHA256 已足够，不要加文件大小校验。** 2026-04-28 实测：Cloudflare CDN 传输 ZIP 时会将 6008350 字节变为 6008345（差 5 字节），但内容不变（SHA256 一致）。大小校验导致更新误报失败，用户被导向 GitHub Release。已移除大小校验逻辑，仅保留 SHA256。

## 7. 性能架构要点

- 菜单：一次性构建 + 原地更新（`buildMenuOnce` + `updateDynamicMenuItems`），内存 ~39MB
- 硬件 I/O：`BackgroundHardwareReader` 在后台线程执行，NSLock 保护缓存；带 `_refreshInFlight` 防重入锁、`_consecutiveTemperatureFailures` 计数、`_lastSuccessfulTemperatureRefresh` 时间戳；新增 `Snapshot` 结构体供控温循环一次性读取（避免多次锁切换）
- 控温循环：从 `MenuBarManager.currentFanCurve` 读内存曲线，不轮询 config.json
- `ConfigManager.loadConfig()` 检查 mtime，未变化返回缓存
- `FanManager` 是 `@MainActor`，硬件调用必须在后台线程
- **Process 超时保护（已撤回）**：v2.9.5/build 37 曾添加 `DispatchSemaphore` 8 秒超时，但实际导致温度读取变慢/卡住。已撤回为原始 `waitUntilExit()` 直接等待。教训见 `CODE_AUDIT.md#6`
- **菜单栏恢复**：监听 `NSApplication.didChangeScreenParametersNotification` 检测 SystemUIServer 重启，自动重建 `NSStatusItem`；事件触发时还会重新探测硬件（`reprobeHardware`）并刷新遥测
- **信息栏展示设置（build 41）**：`displayMode` 存 `UserDefaults("ifancontrol.ui.display_mode")`，值为 `"full"`（默认）或 `"compact"`；简洁模式 `53｜981｜A` 无单位、全角竖线分隔、模式首字母；菜单「信息栏展示」子菜单带选中态，切换即时生效
- **迷你双行显示模式（build 43）**：`displayMode` 新增 `"mini"` 值，存 `UserDefaults("ifancontrol.ui.display_mode")`；NSStatusBarButton 不支持多行文字，改用 `renderMiniStatusImage()` 渲染 NSBitmapImageRep（Retina 感知，26px 高度），上下两行独立居中（避免 monospacedDigitSystemFont 空格/数字宽度不一致问题）；A/M 颜色从 `ControlStatusStore.load()` 读取，正常绿色、异常红色（nil 时不标红）
- **开机自启动**：使用 `SMAppService.mainApp.register()` 原生 API，在系统设置「登录项与扩展」中显示为 App 类型开关；旧的 LaunchAgent plist 在首次启动时自动迁移清理
- **更新校验**：仅依赖 SHA256 校验，不校验文件大小（Cloudflare CDN 传输时大小可能变化 5 字节导致误判）
- **GCD 定时器（build 40）**：所有 `Timer.scheduledTimer` 改为 `DispatchSource.makeTimerSource`，不依赖 RunLoop，无显示器场景也能正常运行（解决 Mac mini 无显示器风扇控制失效根因）
- **安全策略分层化（build 40）**：温度遥测缺失 → 优先进入 2200 RPM 保守兜底（`sensor_loss_fixed_rpm`）；控制能力本身不可靠 → 才交还系统（`system_auto_fallback`）。启动有 12 秒宽限期，避免冷启动误触发
- **控制状态卡片（build 40）**：菜单新增 `ControlStatusSnapshot`（`ControlStatusStore` 持久化到 UserDefaults），显示当前控制状态（正常控制 / 2200 转兜底 / 已交还系统）+ 时间戳，亮屏后可回看
- **安全弹窗去重（build 40）**：`activeSafetyAlertState` 追踪当前弹窗状态，同一状态不重复弹窗；控温恢复正常后自动清除对应前缀的弹窗状态
- **硬件重探测（build 40）**：`FanManager.reprobeHardware(reason:minimumInterval:)` 支持按需重新探测硬件，带最小间隔节流；显示器变化事件触发时自动调用
- **控温循环增强（build 40）**：监控后台遥测新鲜度（`bgTelemetryStaleThreshold = 8s`），过期时主动触发 `BackgroundHardwareReader.refresh`；`consecutiveMissingTelemetryCount >= 3` 触发安全兜底；诊断日志每 30 秒输出一次状态快照
- **默认曲线调整（build 40）**：最低转速从 0 RPM 提升到 602 RPM，中间点微调；criticalTemp 从 95°C 提升到 110°C

## 7b. 心跳上报架构（当前基线）

- **每日上报**：15 分钟入队一条事件，每天上报**昨天**的事件（本地日期判断）
- **离线缓存**：`~/Library/Application Support/MacFanControl/heartbeat_queue.json`，最大 192 条（48 小时）
- **启动**：`startup()` 入队今天的事件 → `flushAll()` 异步发送所有积压事件（含今天），首次安装也能立即上报
- **tick**：
  - 日常活跃链路：`lastFlushDate != 今天 && 有昨天事件` 才 flush（只取昨天及更早的事件）
  - 当前 build 首次上线链路：如果当前 `version-build` 还未收到成功确认，后续 `tick()` 会继续补发当前 build 的事件
- **退出**：`shutdown()` 同步发送昨天及更早的事件；若当前 build 尚未确认，也会一并尝试补发当前 build 事件
- **反馈解耦**：反馈请求不再顺带携带或清空心跳队列
- **payload 格式**：`{install_id, version, build, events: [{ts, type}]}`；发送时按事件自带的 `(version, build)` 分组请求
- **并发安全**：`pendingEvents`、`lastRecordAt` 在 NSLock 内读写
- **install_id**：随机 UUID，存 UserDefaults，跨卸载/重装保持不变；SHA-256 由服务端做
- **服务端**：本阶段不改服务端，继续兼容老版本客户端
- **series_15m 修复**：两个端点处理批量事件时，改为遍历 `uniqueBuckets` 逐个重算活跃用户数，确保历史桶数据不丢失

### 7c. 心跳修复（build 40，客户端第一阶段）

- **首次上线补发**：当前 build 只有在收到 heartbeat endpoint 成功响应后，才记录为已确认；未确认时，后续 `tick()` 会继续补发当前 build
- **队列事件带版本信息**：`heartbeat_queue.json` 中每条事件都携带自己的 `version/build`，避免更新后旧事件被新版本吞并
- **兼容旧队列格式**：旧格式事件会在客户端读取时迁移到新结构
- **反馈与心跳解耦**：反馈不再顺带携带或清空心跳队列，避免误删/串版本
- **客户端优先修复**：本阶段不改服务端，兼容大量存量用户

### 7d. 心跳事件计数修复（2026-04-30）

- **问题**：`heartbeat.js` 中 `daily:${day}:events` 的计数逻辑实际是按 15 分钟桶去重后累加（`uniqueBuckets`），不是原始事件数，且无用户维度去重、无请求去重
- **修复**：改为遍历原始 `events` 数组，按天累计原始事件数（不再按桶去重）
- **历史数据修正**：通过 `bucket_activity` 表按天聚合重算，一次性迁移脚本已删除
- **语义**：修复后"近 30 天明细"中的"心跳事件"列 = 每天上报的原始心跳事件总数（来自所有用户）

## 8. 多语言

- 支持中文 / English，存储在 `UserDefaults("ifancontrol.ui.language")`
- 切换后需重启，三个模块各自定义 `currentLanguage`（main.swift / SensorCatalog.swift / FanCurveWindow.swift）

## 9. 操作纪律

- 不误改历史目录、不误用旧图标
- App 改动只动 `macfan-control-v2`，官网只动 `docs`，实验只动 `distribution-a`
- 发布必须同步：新包 + 官网 ZIP + update-manifest.json + GitHub Release
- `iFanControl-2.8.27/` 是打包参考目录（含 kentsmc、icon.png、安装说明.html 等）

## 10. 已解决问题

- **Mac mini 无显示器时风扇控制失效**（已解决）：断开显示器后控温循环不工作，连接显示器瞬间恢复。已在 v2.9.5 / build 40 中修复并发布。

## 11. 新窗口接手建议

1. `CLAUDE.md`（Claude Code 自动加载的项目红线与操作地图）
2. 本文件（PROJECT_MEMORY.md）
3. `PROJECT_TIMELINE.md`
4. App：`Sources/MacFanControl/main.swift`
5. 官网：`docs/index.html`
6. 官网部署规范：`docs/DEPLOY.md`
7. 统计后台：`ifan-stats/functions/api/dashboard/summary.js`
8. 用户详情页：`ifan-stats/user.html` + `ifan-stats/user.js`
9. 代码审查经验：`CODE_AUDIT.md`
