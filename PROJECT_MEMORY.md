# iFanControl 固定记忆

关联时间戳记忆：`/Users/puremilk/Documents/mac fancontrol/macfan-control-v2/PROJECT_TIMELINE.md`
读取建议：先读本文件，再读时间戳记忆，避免遗漏最新变更。

更新时间：2026-04-28（build 38 发布）

## 1. 项目当前基线

iFanControl 是一个面向 Apple Silicon 带风扇机型的风扇控制工具。

核心功能：
- 自动 / 手动模式
- 5 点风扇曲线编辑 + 3 预设 Tab 切换（双击重命名，切换即时生效，关闭自动保存）+ 拖拽时实时显示温度/RPM
- 温度源选择 + 安全兜底转速
- 应用内自动更新（ZIP 链路）
- 中英文切换（菜单切换，重启生效）
- 匿名活跃统计（每日上报，可关闭）
- 告诉开发者（菜单栏反馈入口，发送时顺便上报心跳）
- 开机自启动（SMAppService 原生登录项 API，系统设置中可直接管理）

当前版本：`2.9.5` / build 38

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

### 后台面板顺序
1. 卡片数据（当前用户/下载/累计/刷新时间）
2. 当前版本分布
3. **用户反馈**（带勾选框，勾选后变灰+删除线，移到末尾；状态存 localStorage）
4. 用户活跃趋势
5. 近 30 天趋势
6. 近 30 天明细

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
- 硬件 I/O：`BackgroundHardwareReader` 在后台线程执行，NSLock 保护缓存
- 控温循环：从 `MenuBarManager.currentFanCurve` 读内存曲线，不轮询 config.json
- `ConfigManager.loadConfig()` 检查 mtime，未变化返回缓存
- `FanManager` 是 `@MainActor`，硬件调用必须在后台线程
- **Process 超时保护（已撤回）**：v2.9.5/build 37 曾添加 `DispatchSemaphore` 8 秒超时，但实际导致温度读取变慢/卡住。已撤回为原始 `waitUntilExit()` 直接等待。教训见 `CODE_AUDIT.md#6`
- **菜单栏恢复**：监听 `NSApplication.didChangeScreenParametersNotification` 检测 SystemUIServer 重启，自动重建 `NSStatusItem`；2 秒轮询中也做健康检查兜底
- **开机自启动**：使用 `SMAppService.mainApp.register()` 原生 API，在系统设置「登录项与扩展」中显示为 App 类型开关；旧的 LaunchAgent plist 在首次启动时自动迁移清理
- **更新校验**：仅依赖 SHA256 校验，不校验文件大小（Cloudflare CDN 传输时大小可能变化 5 字节导致误判）

## 7b. 心跳上报架构（v2.9.5 重构 + 热修复）

- **每日上报**：15 分钟入队一条事件，每天上报**昨天**的事件（本地日期判断）
- **离线缓存**：`~/Library/Application Support/MacFanControl/heartbeat_queue.json`，最大 192 条（48 小时）
- **启动**：`startup()` 入队今天的事件 → `flushAll()` 异步发送所有积压事件（含今天），首次安装也能立即上报
- **tick**：`tick()` 检查 `lastFlushDate != 今天 && 有昨天事件` 才 flush（只取昨天的）
- **退出**：`shutdown()` 同步发送昨天及更早的事件，保留今天的
- **反馈携带**：`dequeueAllPendingEvents()` 取出**所有**待上报事件（不限于昨天），反馈失败时 `requeueEvents()` 放回队列
- **防丢数据**：tick flush 只取昨天的；反馈携带全部但失败会 requeue；shutdown 只发昨天的
- **payload 格式**：`{install_id, version, build, events: [{ts, type}]}`
- **并发安全**：`pendingEvents`、`lastRecordAt` 在 NSLock 内读写
- **install_id**：随机 UUID，存 UserDefaults，跨卸载/重装保持不变；SHA-256 由服务端做
- **服务端**：`heartbeat.js` 不动（兼容老版本）；`feedback.js` 也处理 events（复用 heartbeat 逻辑）
- **series_15m 修复**：两个端点处理批量事件时，改为遍历 `uniqueBuckets` 逐个重算活跃用户数，确保历史桶数据不丢失

## 8. 多语言

- 支持中文 / English，存储在 `UserDefaults("ifancontrol.ui.language")`
- 切换后需重启，三个模块各自定义 `currentLanguage`（main.swift / SensorCatalog.swift / FanCurveWindow.swift）

## 9. 操作纪律

- 不误改历史目录、不误用旧图标
- App 改动只动 `macfan-control-v2`，官网只动 `docs`，实验只动 `distribution-a`
- 发布必须同步：新包 + 官网 ZIP + update-manifest.json + GitHub Release
- `iFanControl-2.8.27/` 是打包参考目录（含 kentsmc、icon.png、安装说明.html 等）

## 10. 新窗口接手建议

1. 本文件（PROJECT_MEMORY.md）
2. `PROJECT_TIMELINE.md`
3. App：`Sources/MacFanControl/main.swift`
4. 官网：`docs/index.html`
5. 官网部署规范：`docs/DEPLOY.md`
6. 统计后台：`ifan-stats/functions/api/dashboard/summary.js`
7. 代码审查经验：`CODE_AUDIT.md`
