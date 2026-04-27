# iFanControl 时间戳记忆

关联固定记忆：`/Users/puremilk/Documents/mac fancontrol/macfan-control-v2/PROJECT_MEMORY.md`  
读取建议：先读固定记忆，再读本文件，用本文件补足最近发生的变化。

## 2026-04-27

### 2026-04-27 — v33 风扇曲线预设系统（两次尝试均失败，已回滚）

#### 第一次尝试（早些时候）
- 目标：3 个预设 Tab 切换，一键在安静/均衡/性能场景间切换
- 编译通过，二进制已替换
- 运行时 UI 未显示，`showFanCurveEditor()` 从未被调用
- 已回滚

#### 第二次尝试（晚间）
- 采用分阶段增量策略：
  - 阶段 1：Config 数据层 + NSLog 调试日志 → 编译通过，NSLog 确认 showFanCurveEditor 被调用
  - 阶段 2：预设 Tab UI → 编译通过，但 UI 不显示
- 尝试了多种 UI 方案均不显示：
  - NSSegmentedControl
  - NSStackView + NSButton (recessed)
  - 自定义 PresetTabButton (NSView 子类)
  - 替换 contentView 为新 NSView
- 原始 UI（FanCurveView + 按钮）始终正常，但任何新增 addSubview 都不可见
- clean build、codesign 重签均无效
- 已完全回滚到 build 32

#### 关键发现
- `setupUI()` 确实被调用（日志证实）
- 菜单 action 正常连接（`sendAction:` 日志出现）
- 二进制 MD5 验证一致（替换成功）
- 但新增的子视图在运行时不可见，原因未明
- 可能与 `@MainActor` 隔离、AppKit 内部缓存、或 window.contentView 生命周期有关

#### 下次实现建议
1. 不修改现有 FanCurveWindowController，创建全新的 NSWindowController 子类
2. 或用 SwiftUI 替代 AppKit 实现预设 UI
3. 或在 FanCurveView 内部直接绘制预设 Tab（避免 addSubview 问题）
4. 先做最小可行测试：在 setupUI 中添加一个最简单的 NSView，确认能显示后再逐步构建

## 2026-04-26

### 2026-04-26 晚间 — 登录故障排查与统计后台大改

#### 登录故障排查（3 个根因）
1. **`_worker.bundle` 覆盖 functions/ 目录**：
   - `ifan-stats/` 中残留的 `_worker.bundle` 带有旧 KV 路由表
   - Cloudflare Pages 优先使用该 bundle，导致所有 API 请求走旧代码
   - 修复：删除 `_worker.bundle`，重新部署
2. **`drawTrendTooltip` 重复声明**：
   - `app.js` 中存在两个同名函数声明，导致 SyntaxError
   - 整个 JS 无法执行（包括登录表单的事件绑定），页面闪烁后输入清空
   - 修复：删除重复的函数声明
3. **Cloudflare WAF 自定义域名拦截**：
   - `stats.puremilkchun.top` 被 Cloudflare managed challenge 拦截，返回 403
   - `pages.dev` 地址可正常访问
   - 用户已设置 WAF 例外规则，但未完全解决
   - 当前状态：使用 `ifan-stats.pages.dev` 访问

#### 会话有效期延长
- `SESSION_TTL_SECONDS` 从 12 小时改为 365 天
- 登录 cookie `Max-Age` 同步改为 365 天
- 用户需求："只要登录，就不需要重新登录了"

#### 趋势图 hover 版本分布
- 为近 30 天趋势图添加鼠标事件监听（mousemove / mouseleave）
- hover 浮窗显示每日各版本的去重用户数
- 版本数量右对齐

#### 活跃度图每桶版本分布（重大改动）
- **数据库**：`bucket_activity` 表新增 `version TEXT` 列
- **心跳端点**：`INSERT INTO bucket_activity` 增加 `version` 字段（格式 `2.9.1-32`）
- **老数据回填**：从 `flags` 表的 `version:{day}:{versionBuild}:{installHash}` 模式提取版本信息，回填 32 行
- **后端查询**：改为单源查询 `GROUP BY bucket_index, version`，同时计算活跃用户数和版本分布
- **前端改动**：移除 `dailyVersionsMap`，改从 `point.versions` 读取每个桶的版本分布
- **active_users 一致性修复**：hover 中的活跃人数 = 各版本人数之和（均来自同一查询）

#### 版本数量右对齐
- `drawCanvasTooltip` 和 `drawTrendTooltip` 中，版本行改为版本号左对齐、数量右对齐
- 宽度计算拆分为 `verWidth + gap + cntWidth`

### 2026-04-26 15:00 左右
- 诊断并修复统计后台数据为 0 的问题：
  - 根因：`docs/` 目录中残留的 `_worker.bundle` 带有 `/functions/` 前缀路由表
  - Cloudflare Pages 优先使用该 bundle，导致所有 API 请求路径不匹配，返回 HTML（405 或 200）
  - 心跳上报 `/api/heartbeat` 实际命中了 `/functions/api/heartbeat`，被 Pages 当作静态文件处理
- 修复动作：
  - 删除 `docs/_worker.bundle`
  - 用 `wrangler pages functions build --outdir /tmp/ifan-build` 从 `functions/` 目录构建正确的 `_worker.js`
  - 部署时必须带 `--no-bundle --skip-caching`，否则 wrangler 会尝试重新打包或检测不到文件变化
- 修复后验证：
  - `/api/heartbeat` 返回 `{"ok":true}`
  - `/api/stats` 返回正确 JSON 数据
  - `/download` 正确 302 到 ZIP 并累计下载计数
  - 心跳数据开始正常写入 KV

### 2026-04-26 16:00 左右
- 新增"下载活跃趋势"15 分钟粒度折线图，涉及 4 个文件：
  - `docs/functions/download.js`：新增 `updateDownloadSeries15m()` 函数，写入 `download:series15m:{day}`（96 槽位 JSON 数组，TTL 7 天）
  - `ifan-stats/functions/api/dashboard/summary.js`：新增 `readDownloadSeries15m()` 读取下载 15 分钟序列，响应新增 `downloads_15m` 字段
  - `ifan-stats/index.html`：新增"下载活跃趋势"面板（`<canvas id="downloadChart">`）
  - `ifan-stats/app.js`：新增 `getDownloadChartModel()`、`renderDownloadChart()`、`drawDownloadCanvasTooltip()`，蓝色折线，支持 hover tooltip
- 前端 `drawHover()` 改为支持可选 `color` 参数，活跃用户用橙色 `#f97316`，下载用蓝色 `#2563eb`
- 两个项目均已部署验证通过

### 2026-04-26 16:30 左右
- 将本次调试与开发经验写入 `PROJECT_MEMORY.md`：
  - 新增"Cloudflare Pages Functions 部署纪律"章节，记录正确部署流程、禁止事项和原因
  - 新增"5b. 统计后台（ifan-stats）"章节，记录项目位置、线上地址、架构、部署命令和功能列表

### 2026-04-26 晚间 — 内存优化 + 预设尝试 + 菜单响应优化

#### 第一阶段：内存优化
- 分析发现 `updateMenu()` 每 2 秒重建整个 NSMenu 是内存飙升根因（~90MB）
- 实现 `buildMenuOnce()` + `updateDynamicMenuItems()` 模式：菜单结构只建一次，后续仅原地更新 title/state
- 删除 `temperatureHistory` 死代码（仅写入从未读取）
- 优化后内存稳定在 ~39MB，用户确认
- **发布 v2.9.0 / build 30**

#### 第二阶段：风扇曲线预设系统尝试（已回滚）
- 完成方案设计：3 个 Tab 按钮、双击重命名、config.json 存储 `curvePresets`
- 代码实现并编译通过，但运行时 UI 未显示（原因未明）
- 用户决定回滚，保留方案规划到 `project_fan_curve_presets_plan.md`
- 回滚事故：`git checkout` 连带回滚了未提交的内存优化，已重新应用

#### 第三阶段：菜单响应性能优化
- 用户反馈菜单点击有延迟（优化前就存在）
- 根因分析：
  1. `ConfigManager.loadConfig()` 每 2 秒从磁盘读取 + 解析 JSON
  2. `refreshTelemetry()` 在主线程逐个调用 `kentsmc` 子进程（每个传感器一个 Process），阻塞主线程
  3. `startAutoControlLoop()` 也有独立的 2 秒定时器，同样在主线程做硬件 I/O
- 解决方案：
  1. **Config 缓存**：`loadConfig()` 增加 mtime 检查，文件未变化时返回缓存，避免磁盘 I/O
  2. **BackgroundHardwareReader**：独立的非 MainActor 类，在后台 DispatchQueue 上执行硬件读取，通过 NSLock 保护缓存
  3. **菜单定时器改造**：定时器 dispatch 硬件读取到后台，`updateDynamicMenuItems()` 只从后台缓存读取
  4. **自动控温循环改造**：`startAutoControlLoop()` 改为从 BackgroundHardwareReader 缓存读取温度，不再触发主线程硬件 I/O
- 效果：菜单点击从"有延迟"变为"即时弹出"
- **发布 v2.9.1 / build 31**

#### 附：Cloudflare KV 用量预警
- 收到 Cloudflare 邮件：Workers KV 免费层已达 50%
- 免费层限制：每天 1,000 次写入；当前约 5 个日活用户（每人每天 96 次心跳写入）
- 结论：暂不需要升级，但用户继续增长时需注意（$5/月付费计划可支撑 ~10,000 日活）

### 2026-04-26 深夜 — KV 迁移 D1 + 批量心跳系统

#### 背景
- KV 免费层 1,000 次写入/天，5 个日活用户已接近 50%
- D1 免费层提供 100,000 行写入/天 + 1,000 次查询/天
- 决定将统计后端从 KV 迁移到 D1，并重新设计心跳上报机制

#### D1 迁移
- 创建 D1 数据库 `ifan-stats-db`（database_id: `383dadba-cf12-47f1-bf53-dbf2f087458f`）
- 新建 `wrangler.toml` 配置 D1 绑定（docs + ifan-stats 两个项目）
- 重写 `docs/functions/api/heartbeat.js`：KV → D1，支持批量事件格式
- 重写 `docs/functions/download.js`：KV → D1
- 重写 `docs/functions/api/stats.js`：KV → D1
- 重写 `ifan-stats/functions/api/dashboard/summary.js`：KV → D1
- 重写 `ifan-stats/functions/api/_lib/auth.js`：KV → D1（登录限流）
- D1 表结构：`counters`、`flags`（替代旧 `seen`）、`bucket_activity`、`series_15m`
- 删除 `docs/_worker.js`（旧打包文件会覆盖 functions/ 目录），保留 `.bak`

#### 批量心跳系统
- 问题：即使迁移到 D1，每个用户每天仍产生 ~96 次查询（每 15 分钟 1 次心跳 × 每次 ~4 条 SQL）
- 解决方案：App 端本地缓存心跳事件，每小时批量上报
- App 端改动（`PrivacyStatsService`）：
  - 每 15 分钟记录一条带时间戳的事件到本地队列
  - 每小时通过 `POST /api/heartbeat` 批量上报所有缓存事件
  - 离线事件缓存在 `~/Library/Application Support/iFanControl/heartbeat_queue.json`
  - 启动时先 flush 缓存事件，再记录新心跳
  - 退出时 flush 所有待上报事件
- 服务器端改动（`heartbeat.js`）：
  - 接收 `{install_id, version, build, events: [{ts, type}, ...]}` 格式
  - 按 (day, bucket_index) 去重，批量写入 D1
  - 从 `bucket_activity` 重新聚合 `series_15m` 活跃用户数
- 查询量估算：~5 次查询/批 × 每天 24 批/用户 × 5 用户 ≈ 600 次/天（远低于 1,000 免费上限）

#### 前端改动
- `ifan-stats/index.html`：卡片区"最近刷新"下方注明"每小时更新"

#### 部署验证
- 两个项目均部署到 Cloudflare Pages
- 本地测试通过（heartbeat、stats、download 三个接口）
- 远程测试通过

## 2026-04-24

### 2026-04-24 00:00 左右
- 明确采用“双记忆”结构：
  - 固定记忆：`PROJECT_MEMORY.md`
  - 时间戳记忆：`PROJECT_TIMELINE.md`

### 2026-04-24 00:00 左右
- 确认当前真正开发目录是：
  - `/Users/puremilk/Documents/mac fancontrol/macfan-control-v2`
  - `/Users/puremilk/Documents/mac fancontrol/distribution-a`
- 明确 `/Users/puremilk/Downloads/iFanControl-2.8` 只是下载/测试目录，不应继续作为主上下文

### 2026-04-24 00:10 左右
- 继续推进安装体验 A 方案
- 在 `/Users/puremilk/Documents/mac fancontrol/distribution-a` 中建立隔离实验线
- 主工程与官网发布链保持不动

### 2026-04-24 00:15 左右
- 实验线完成：
  - `DMG + Install.command + 首次启动引导页`
  - App 内“诊断与支持”入口补入修复/卸载相关动作

### 2026-04-24 00:20 左右
- 修复实验 DMG 打包脚本误把 `dSYM` 当成主二进制的问题
- 重新生成可正常启动的实验版 App 和 DMG

### 2026-04-24 00:25 左右
- 验证实验 DMG 可正常安装
- 用户确认新的 DMG 安装体验基本可用

### 2026-04-24 00:30 左右
- 收到反馈：`/Applications` 中出现大量 `iFanControl.app.backup-*` 和 `iFanControl.app.malformed-*`
- 定位为历史测试/替换过程中留下的备份残留
- 已全部清理

### 2026-04-24 00:35 左右
- 完成卸载闭环第一阶段：
  - DMG 顶层新增 `Uninstall.command`
  - 新增完整卸载脚本，支持删除：
    - `iFanControl.app`
    - `kentsmc`
    - `sudoers`
    - 配置
    - 日志
    - LaunchAgent

### 2026-04-24 00:40 左右
- 将实验 DMG 外部说明文件命名调整为：
  - `README｜安装指南.txt`
- 原因：
  - macOS 文件名不能直接使用 `/`
  - 使用 `｜` 保留接近“README / 安装指南”的显示语义

### 2026-04-24 00:45 左右
- 完成 App 内完整卸载主入口：
  - 在 `关于/帮助 -> 诊断与支持` 中点 `完整卸载`
  - App 先确认
  - 自动生成一次性临时卸载脚本
  - App 退出后由脚本继续删除 App 和所有残留
- 这意味着卸载不再依赖用户保留 DMG

### 2026-04-24 00:50 左右
- 确定当前分发策略建议：
  - 首次安装：DMG
  - 自动更新：ZIP
- 即：
  - 官网手动下载未来可切到 DMG
  - App 内自动更新暂不改，继续保留 ZIP

### 2026-04-24 01:00 左右
- 将记忆文件正式迁入 `macfan-control-v2`
- 固定记忆改为：
  - `/Users/puremilk/Documents/mac fancontrol/macfan-control-v2/PROJECT_MEMORY.md`
- 时间戳记忆改为：
  - `/Users/puremilk/Documents/mac fancontrol/macfan-control-v2/PROJECT_TIMELINE.md`

### 2026-04-24 01:30 左右
- 官网下载策略正式切换完成：
  - 主下载按钮改为 `./iFanControl-macOS.dmg`
  - 页脚下载入口改为 `./iFanControl-macOS.dmg`
  - 中英文页脚文案改为“下载 DMG / Download DMG”
- `docs` 目录新增固定文件名 DMG：
  - `/Users/puremilk/Documents/mac fancontrol/docs/iFanControl-macOS.dmg`
- 官网已完成发布，发布预览地址：
  - `https://b23c2448.ifan-59w.pages.dev`

### 2026-04-24 01:35 左右
- GitHub Release `v2.8.21` 已确认包含双资产：
  - `iFanControl-macOS.dmg`（官网手动下载安装）
  - `iFanControl-macOS.zip`（应用内自动更新）
- `update-manifest.json` 保持 ZIP 更新链路不变（`macos_arm64_zip_url` 仍指向 ZIP）

### 2026-04-24 01:40 左右
- 修复 GitHub Actions 长期构建告警：
  - 原因 1：仓库无 `Tests/` 时 `swift test` 直接失败
  - 原因 2：`Package.swift` 使用 `swift-tools-version: 6.2`，而 GitHub Runner 为 6.1
- 处理动作：
  - workflow 调整为“仅在存在测试文件时运行 `swift test`”
  - `Package.swift` tools version 下调为 `6.1`
  - `actions/checkout` 升级到 `v5`，消除 Node20 弃用警告
- 结果：
  - 最新 CI 连续通过，`Swift` workflow 已恢复绿色

### 2026-04-24 01:50 左右
- 为验证更新链路，创建 `2.8.22` 测试更新：
  - 基于 `2.8.21` 复制出测试 ZIP
  - 将 `update-manifest.json` 提升到 `2.8.22 / build 22`
  - 发布到 Pages，并创建 GitHub `v2.8.22` Release

### 2026-04-24 02:00 左右
- 收到反馈：App 内“完整卸载”入口消失
- 根因定位：
  - 完整卸载实现停留在 `distribution-a/prototype-app` 实验线
  - 正式更新 ZIP 仍使用主线旧包，未包含该功能
- 处理动作：
  - 将完整卸载能力正式并回 `macfan-control-v2` 主线
  - 在 `关于/帮助 -> 诊断与支持` 恢复 `完整卸载 / Full Uninstall`
  - 保留一次性临时卸载脚本流程（退出后继续清理）

### 2026-04-24 02:05 左右
- 重新打包并发布 `2.8.22` 正式更新 ZIP（包含完整卸载恢复）
- 同步更新：
  - `docs/iFanControl-macOS.zip`
  - `docs/update-manifest.json`（新 hash/size）
  - GitHub `v2.8.22` Release 资产
- 主仓库代码已推送并通过 CI

### 2026-04-24 02:15 左右
- 新发现：网络下载场景下，DMG 中双击 `.command` 依旧容易被 Gatekeeper 持续拦截
- 决策变更：
  - 放弃 DMG 作为正式安装主链路
  - 回退为“拖拽 `install.sh` 到终端执行”的 ZIP 安装模式
- 同步动作：
  - 安装指南 HTML 回退并修正文案（明确不要双击 `Install.command`）
  - README 中英文同步改为拖拽安装推荐
  - 更新器逻辑改为优先 `install.sh`，避免 command-first 行为

### 2026-04-24 02:20 左右
- 虽然重打了可包含 `.sh` 的 DMG 并验证成功，但最终仍确认正式策略为 ZIP-only
- 官网最终发布状态：
  - 官网下载按钮：`ZIP`
  - 应用内更新：`ZIP`
  - `update-manifest.json` 说明已更新为“全链路 ZIP”
- 最终结论：
  - **首装走 ZIP**
  - **更新走 ZIP**

### 2026-04-24 13:15 左右
- 准备发布 `2.8.23 / build 23`：
  - 修复关于/帮助窗口在系统深浅色切换后卡片不换色的问题
  - 支持作者二维码改为随深浅色重新生成（亮色黑码白底，暗色白码深底）
  - 手动转速弹窗新增“实际 RPM 不一定完全等于设定值”的解释入口
  - App 内完整卸载补齐旧配置目录 `~/Library/Application Support/iFanControl` 清理
- 官网与自动更新继续保持 ZIP-only：
  - `docs/iFanControl-macOS.zip`
  - `docs/iFanControl-macOS-2.8.23.zip`
  - `docs/update-manifest.json` 升到 `2.8.23 / build 23`
- 官网发布目录中移除残留 `iFanControl-macOS.dmg`，避免公开 DMG 入口继续误导用户。

### 2026-04-24 13:35 左右
- 发现自动检查更新机制存在节流问题：
  - 旧逻辑会在请求 manifest 前用 `last_check` 做 24 小时拦截
  - 如果用户在新版本发布前刚检查过，发布后自动检查会直接返回，不会联网，也不会弹窗
- 修复策略：
  - 自动检查开启时，启动后始终请求一次 manifest
  - `last_check` 只保留为记录信息，不再阻止发现新版本
- 准备发布 `2.8.24 / build 24`，专门修复自动检查更新不弹窗问题。

### 2026-04-24 14:40 左右
- 新增“隐私优先统计”全链路（不改变 ZIP 更新契约）：
  - 官网新增 `Pages Functions`：
    - `GET /download`：302 到 `iFanControl-macOS.zip`，并写入聚合下载计数
    - `POST /api/heartbeat`：写入匿名活跃计数（仅随机安装 ID 的哈希、version、build）
    - `GET /api/stats`：统计读取接口，已加 `Bearer` token 鉴权
  - Cloudflare Pages 项目 `ifan` 已绑定 KV 命名空间 `IFAN_STATS`
  - 线上已验证：
    - `/download` 返回 302 且可累计 `download:total`
    - `/api/heartbeat` 返回 `{"ok":true}` 且可累计活跃计数
    - `/api/stats` 未带 token 返回 401，带 token 可读统计
- App 端同步改动：
  - 新增 `PrivacyStatsService`，应用启动后延迟上报每日一次匿名心跳
  - `关于/帮助 -> 简介` 新增“共享匿名活跃统计”开关及说明文案
- 发布产物升级到 `2.8.25 / build 25`：
  - `docs/update-manifest.json` 升到 `2.8.25 / 25`
  - `docs/iFanControl-macOS.zip` 已替换为 `2.8.25`，sha256 为 `553f9861894e65394fcaf911799d201412c927d5d56f798c8d248e169b22805c`
  - 官网页面下载入口改为 `./download`，构建标记更新为 `build 20260424b`

## 2026-04-25

### 2026-04-25 22:00 左右
- 对 `main.swift` 和 `SensorCatalog.swift` 进行了代码质量审查，识别出多个内存优化机会：
  - Config 每 2 秒从磁盘重新读取（应缓存）
  - 温度读数每 2 秒重复构建（应缓存）
  - NSMenu 每 2 秒完整重建（应原地更新）
  - `temperatureHistory` 死代码
  - HelpWindow 视图未在关闭时释放
  - `category`/`sortKey` 计算属性应缓存
  - `ISO8601DateFormatter` 应 lazy 初始化
  - 心跳 Timer 双重注册
- 完成了内存优化的代码实现并编译通过
- 后因用户要求回滚，所有内存优化改动已 `git restore`，暂不发布

### 2026-04-25 23:00 左右
- 实现多语言切换功能：
  - 将三个模块的 `private let` 布尔语言判断替换为从 `UserDefaults` 读取的 `currentLanguage`
  - 涉及文件：`main.swift`、`SensorCatalog.swift`、`FanCurveWindow.swift`
  - 菜单新增"语言 / Language"子菜单（位于"关于/帮助..."之后）
  - 首次安装弹出语言选择弹窗（中文 / English）
  - 切换后提示重启生效，可选"立即重启"或"稍后"
- 版本号升级到 `2.8.28 / build 28`
- 完成全链路发布：
  - 官网 ZIP 替换（`docs/iFanControl-macOS.zip` + `docs/iFanControl-macOS-2.8.28.zip`）
  - `update-manifest.json` 升到 `2.8.28 / 28`
  - Cloudflare Pages 部署完成
  - GitHub 代码推送（commit `52c014c`）
  - GitHub Release `v2.8.28` 创建：
    - `https://github.com/PureMilkchun/iFanControl/releases/tag/v2.8.28`
- 新包校验值：
  - `sha256 = 7b743bd8209686b6cfe732118b2d67b8e2717b8ea01d431f449915173abae1ad`
  - `size = 5971567`

### 2026-04-25 23:30 左右
- 处理 PR #2（`lop1381997:codex/english-translation`，"add bilingual UI switcher"）：
  - 该 PR 提出了 `LocalizationManager` 单例 + 即时切换方案（+351 行）
  - 我们的 v2.8.28 已用更简单的方式覆盖核心需求（+66 行，重启生效）
  - 已用得体英文回复作者并关闭 PR

### 2026-04-25 14:10 左右
- 统计后台 `stats` 继续迭代：
  - 初步加入 12 小时活跃趋势图与时间范围切换
  - 后续澄清需求后，改为“默认近 12 小时、15 分钟粒度”的真实活跃曲线
- 底层数据口径统一为：
  - 使用官网心跳写入的 `15 分钟聚合活跃值`
  - 最近 `30 天` 的 15 分钟点位长期保留
  - 统计后台再按所需范围读取并绘制

### 2026-04-25 14:20 左右
- 官网发布了 `2.8.26 / build 26`：
  - `docs/update-manifest.json` 升到 `2.8.26 / 26`
  - 官网 ZIP 与应用内更新 ZIP 保持一致
- 随后确认：
  - GitHub Release 侧当时还停留在 `v2.8.25`
  - 需要单独补发 `v2.8.26` Release

### 2026-04-25 14:30 左右
- 补发 GitHub `v2.8.26` Release：
  - 上传 `iFanControl-macOS-2.8.26.zip`
  - 在 Release 说明中明确写入：
    - 适配已覆盖 `M5`
    - 已在真实 `MacBook Pro M5` 上完成运行验证

### 2026-04-25 14:40 左右
- 对匿名统计设置项做产品体验修正：
  - 设置项名称统一改为 `匿名统计用户量`
  - 在开关右侧新增 `?` 说明按钮
  - 帮助文案改为更直白解释：
    - 只统计有多少人在使用 iFanControl
    - 仅上报随机安装 ID、版本号、build
    - 不上传姓名、邮箱、序列号、设备名称
  - 用户尝试关闭时，新增一次带幽默感的确认弹窗
  - 若用户坚持关闭，仍然允许关闭
- 对应代码已推送到 GitHub：
  - commit `38a0f48`

### 2026-04-25 14:50 左右
- 修正了一个发布流程认知问题：
  - 仅推 GitHub 代码并不能让用户收到 App 行为更新
  - 如果变更要让用户真正拿到，必须同步：
    - 新 ZIP 包
    - 官网当前 ZIP
    - `update-manifest.json`
    - GitHub Release

### 2026-04-25 14:55 左右
- 重新打包并发布 `2.8.27 / build 27`，用于承载“匿名统计说明 + 关闭确认弹窗”这次真实用户可见改动：
  - `Info.plist` 升到 `2.8.27 / 27`
  - `install.sh` 标题同步升到 `2.8.27`
  - 安装脚本兼容设备文案更新为 `(M1/M2/M3/M4/M5)`
- 新 ZIP 产物：
  - `docs/iFanControl-macOS-2.8.27.zip`
  - `docs/iFanControl-macOS.zip`
- 新包校验值：
  - `sha256 = 811cc495bc2b03130d2d22b5395ed1267640a4b383aec5cabc56e39649352450`
  - `size = 5972647`

### 2026-04-25 15:00 左右
- 官网与应用内更新链路同步到 `2.8.27`：
  - `docs/update-manifest.json` 升到 `2.8.27 / 27`
  - `notes` 更新为匿名统计说明与关闭确认弹窗相关内容
  - `https://ifan-59w.pages.dev/update-manifest.json` 线上已验证为 `2.8.27`
- GitHub Release 同步到 `v2.8.27`：
  - Release 地址：`https://github.com/PureMilkchun/iFanControl/releases/tag/v2.8.27`
  - 资产：`iFanControl-macOS-2.8.27.zip`
- 主仓库代码同步：
  - commit `f1e5ff9`
- 结论：
  - 官网 ZIP、应用内更新 ZIP、GitHub Release 三者已重新对齐
  - `2.8.27` 才是这次匿名统计交互改动真正对用户可达的版本

## 2026-04-23

### 2026-04-23
- 正式稳定版本已到 `2.8.21`
- 修复了更新包缺少 `install.sh` 导致更新失败的问题
- 线上 update manifest 与 GitHub Release 已同步到 `2.8.21`

### 2026-04-23
- 帮助页经历多轮重构：
  - 关于/帮助侧边栏
  - 诊断与支持
  - 常见问题
  - 支持作者
- 版本一路迭代到 `2.8.21` 前后

### 2026-04-23
- 对主目录做过一次明显旧物清理：
  - 删除旧工程目录
  - 删除旧 DMG/ZIP
  - 删除测试脚本
  - 保留主工程、官网、交接文档与部分辅助目录
