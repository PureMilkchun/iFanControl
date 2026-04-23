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
