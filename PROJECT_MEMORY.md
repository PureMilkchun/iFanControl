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
- 正在推进更顺手的 DMG 首装体验

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

这是当前安装体验 A 方案的隔离实验目录，只用于验证：
- DMG 外壳
- `Install.command` 新入口
- App 首次启动引导页
- App 内完整卸载

### 不要作为主工作目录的地方
- `/Users/puremilk/Downloads/iFanControl-2.8`

这个目录只是下载包/测试包所在位置，不应再作为真正开发基线。

## 3. 当前版本与分发策略

### 当前正式稳定版本
- 正式版本：`2.8.21`

### 当前实验产物
- 实验 DMG：`/Users/puremilk/Documents/mac fancontrol/distribution-a/dist/iFanControl-experimental.dmg`

### 当前推荐分发策略
- 首次安装：优先使用 `DMG`
- 自动更新：继续保留 `ZIP`

一句话：
- **首装走 DMG**
- **更新走 ZIP**

## 4. 自动更新当前事实

当前自动更新仍使用 ZIP，而不是 DMG。

相关事实：
- Manifest：`https://ifan-59w.pages.dev/update-manifest.json`
- ZIP：`https://ifan-59w.pages.dev/iFanControl-macOS.zip`

代码位置：
- `/Users/puremilk/Documents/mac fancontrol/macfan-control-v2/Sources/MacFanControl/main.swift`

当前判断：
- 官网下载按钮未来可以切 DMG
- 但 App 内自动更新暂时不要改 DMG，风险更高

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

## 6. 图标与资源规则

### 当前正确 App 图标
- `/Users/puremilk/Documents/mac fancontrol/macfan-control-v2/icon.png`

### 旧图标
- `/Users/puremilk/Documents/mac fancontrol/icon.png`

继续工作时不要再误用旧图标。

## 7. 当前安装 / 卸载设计规则

### 正式主线
- 现有稳定链路仍以 ZIP + 自动更新为主

### 实验线
- DMG 顶层保留：
  - `iFanControl.app`
  - `Applications`
  - `Install.command`
  - `Uninstall.command`
  - `README｜安装指南.txt`
- App 内已接入“完整卸载”主入口
- DMG 内的 `Uninstall.command` 只是备用入口

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
