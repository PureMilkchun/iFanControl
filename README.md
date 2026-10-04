<p align="center">
  <img src="icon.png" width="128" height="128" alt="iFanControl Icon">
</p>

<h1 align="center">iFanControl</h1>

<p align="center">
  Apple Silicon 带风扇 Mac 的菜单栏风扇控制工具
</p>

<p align="center">
  A menu bar fan control utility for Apple Silicon Macs with built-in fans
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-26.0+-black" alt="Platform">
  <img src="https://img.shields.io/badge/Apple%20Silicon-M%20Series-black" alt="Architecture">
  <img src="https://img.shields.io/badge/license-MIT-black" alt="License">
</p>

---

## 项目简介

iFanControl 是一个面向 Apple Silicon Mac 的原生菜单栏应用，提供实时温度与转速查看、自动/手动风扇控制、5 点风扇曲线、应用内更新，以及面向带风扇 M 系列设备的更稳健传感器探测。

当前仓库只保留源码、安装脚本和必要资源。历史发布包不再提交到仓库，统一通过 GitHub Releases 和官网分发。

English readers can use [README_EN.md](README_EN.md).

## 当前能力

- 菜单栏显示当前温度、风扇转速和控制模式
- 自动模式：根据 5 点风扇曲线调速
- 手动模式：固定目标 RPM
- 曲线编辑器支持 Y 轴正向 / 反向显示，方便按不同习惯编辑 RPM 曲线
- 安全兜底转速：高温时只托底，不压低用户更高转速
- 温度源选择：默认选择最热传感器，也支持 CPU / GPU 分别计算平均温度或手动指定传感器
- 应用内更新：支持手动检查，也支持后台自动检查
- 关于窗口：整合版本号、检查更新、自动检查更新、GitHub 和重启入口
- 匿名统计用户量：按固定间隔上报，可在关于/帮助中关闭
- 开机自启动
- 安装诊断与一键卸载脚本

## 适用范围

- macOS 26 及以上
- 带风扇的 Apple Silicon Mac
- 开发者仅有一台 Mac mini M4，已稳定运行数月；其他机型理论上可用，实际需试用确认

说明：无风扇设备不会获得有效的风扇控制能力。温度源列表展示的是系统实际暴露的热传感器，不一定与 CPU / GPU 核心数量一一对应。

## 安装

从 [GitHub Releases](https://github.com/PureMilkchun/iFanControl/releases) 或[官网](https://ifancontrol.puremilkchun.top)下载 PKG。

1. 先从菜单栏退出 iFanControl，再双击安装包。
2. 按系统安装向导操作，现有设置会保留。
3. 完成后从“应用程序”打开 iFanControl；若系统阻止打开，前往“系统设置 → 隐私与安全性”，点“仍要打开”，再确认“打开”。

2.9.8 及更早版本先通过原有应用内更新升级到 2.9.9，再通过 PKG 更新到后续版本。[旧版升级包](https://ifan-59w.pages.dev/iFanControl-legacy-2.9.9.zip)长期保留；若手动使用它，请解压后把 `install.sh` 拖入终端并按回车。

## Support & Logs / 反馈与日志

### English

- Support email: `puremilkchun@foxmail.com`
- Open `About / Help...` from the app menu, then use:
  - `Export Diagnostics`
  - `Open Log Folder`
  - `Contact Support`
- Exported diagnostics package: `~/Desktop/iFanControl-Diagnostics-*.zip`
- Manual log path (advanced): `~/Library/Logs/iFanControl/ifancontrol.log`

### 中文

- 支持邮箱：`puremilkchun@foxmail.com`
- 在应用菜单打开 `关于/帮助...` 后使用：
  - `导出诊断包`
  - `打开日志目录`
  - `联系支持`
- 导出的诊断包位置：`~/Desktop/iFanControl-Diagnostics-*.zip`
- 日志原始路径（高级排查）：`~/Library/Logs/iFanControl/ifancontrol.log`

## 使用说明

1. 打开 `/Applications/iFanControl.app`
2. 应用会驻留在菜单栏
3. 在菜单中切换自动/手动模式、编辑曲线、调整安全兜底转速
4. 在 `关于 iFanControl...` 中查看版本、检查更新、设置自动检查更新或跳转 GitHub

## 隐私与统计

iFanControl 会默认发送定期的匿名用户量统计数据，用于改进产品体验与稳定性。内容仅包含随机匿名 ID、版本号和 build；不会发送姓名、邮箱、序列号、设备名称或风扇/温度数据。你可以在 `关于/帮助 -> 简介` 中关闭“匿名统计用户量”。

## 仓库结构

```text
.
├── Package.swift
├── Sources/
│   ├── FanCurveEditor/
│   └── MacFanControl/
├── iFanControl.app/        # App bundle 模板资源
├── install.sh
├── diagnose.sh
├── uninstall.sh
├── Install.command
├── 安装说明.html
└── icon.png
```

## 开发

本项目使用 Swift Package Manager：

```bash
swift build
swift run
```

CI 位于 `.github/workflows/swift.yml`，默认会对 `main` 执行构建检查。

## 更新机制

- 手动检查：`关于 iFanControl... -> 检查更新`
- 自动检查：启动后延迟检查，并带 24 小时节流
- 2.9.9 起：独立的 `update-manifest-pkg.json` 通道，直接下载并校验 PKG，打开系统安装器后退出 App
- 旧版通道：`update-manifest.json` 永久停在 2.9.9，提供兼容 ZIP；不会向旧版推送后续版本
- 更新失败时：会直接引导到 GitHub Releases 手动下载

## 卸载

```bash
./uninstall.sh
```

如果脚本来自下载的 ZIP，推荐像安装一样将 `uninstall.sh` 拖入终端执行；不要依赖双击 `.command` 文件。

## 致谢

- [kentsmc](https://github.com/exelban/kentsmc)
- [Stats](https://github.com/exelban/stats)

## 许可证

[MIT](LICENSE)
