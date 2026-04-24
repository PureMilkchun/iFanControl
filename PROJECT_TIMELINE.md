# iFanControl 时间戳记忆

关联固定记忆：`/Users/puremilk/Documents/mac fancontrol/macfan-control-v2/PROJECT_MEMORY.md`  
读取建议：先读固定记忆，再读本文件，用本文件补足最近发生的变化。

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
