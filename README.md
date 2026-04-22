<p align="center">
  <img src="icon.png" width="128" height="128" alt="iFanControl Icon">
</p>

<h1 align="center">iFanControl</h1>

<p align="center">
  Apple Silicon 带风扇 Mac 的菜单栏风扇控制工具
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0+-black" alt="Platform">
  <img src="https://img.shields.io/badge/Apple%20Silicon-M%20Series-black" alt="Architecture">
  <img src="https://img.shields.io/badge/license-MIT-black" alt="License">
</p>

---

## 项目简介

iFanControl 是一个面向 Apple Silicon Mac 的原生菜单栏应用，提供实时温度与转速查看、自动/手动风扇控制、5 点风扇曲线、应用内更新，以及面向带风扇 M 系列设备的更稳健传感器探测。

当前仓库只保留源码、安装脚本和必要资源。历史发布包不再提交到仓库，统一通过 GitHub Releases 和官网分发。

## 当前能力

- 菜单栏显示当前温度、风扇转速和控制模式
- 自动模式：根据 5 点风扇曲线调速
- 手动模式：固定目标 RPM
- 安全兜底转速：高温时只托底，不压低用户更高转速
- 温度源选择：默认选择最热传感器，也支持手动指定
- 应用内更新：支持手动检查，也支持后台自动检查
- 关于窗口：整合版本号、检查更新、自动检查更新、GitHub 和重启入口
- 开机自启动
- 安装诊断与一键卸载脚本

## 适用范围

- macOS 13 及以上
- 带风扇的 Apple Silicon Mac
- 重点覆盖 M1 / M2 / M3 / M4 系列

说明：无风扇设备不会获得有效的风扇控制能力。温度源列表展示的是系统实际暴露的热传感器，不一定与 CPU / GPU 核心数量一一对应。

## 安装

### 方式一：从 GitHub Releases 下载

前往 [Releases](https://github.com/PureMilkchun/iFanControl/releases) 下载最新 ZIP，解压后运行：

```bash
cd ~/Downloads/iFanControl-* && ./install.sh
```

### 方式二：从官网下载安装

- 官网：[ifancontrol.puremilkchun.top](https://ifancontrol.puremilkchun.top)
- 更新源：[ifan-59w.pages.dev](https://ifan-59w.pages.dev/update-manifest.json)

解压后也可直接运行 `install.sh`。如果需要图文说明，可打开仓库中的 [安装说明.html](安装说明.html)。

## 使用说明

1. 打开 `/Applications/iFanControl.app`
2. 应用会驻留在菜单栏
3. 在菜单中切换自动/手动模式、编辑曲线、调整安全兜底转速
4. 在 `关于 iFanControl...` 中查看版本、检查更新、设置自动检查更新或跳转 GitHub

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
- 更新包来源：`pages.dev` 上的 `update-manifest.json` 与 ZIP
- 更新失败时：会直接引导到 GitHub Releases 手动下载

## 卸载

```bash
./uninstall.sh
```

如果你更习惯双击，也可以使用 `uninstall.command`。

## 致谢

- [kentsmc](https://github.com/exelban/kentsmc)
- [Stats](https://github.com/exelban/stats)

## 许可证

[MIT](LICENSE)
