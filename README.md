<p align="center">
  <img src="icon.png" width="128" height="128" alt="iFanControl Icon">
</p>

<h1 align="center">iFanControl</h1>

<p align="center">
  A simple fan control app for Apple Silicon Macs
</p>

<p align="center">
  一款适用于 Apple Silicon Mac 的简洁风扇控制应用
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0+-blue" alt="Platform">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/architecture-ARM64-purple" alt="Architecture">
</p>

---

## Features / 功能特性

| English | 中文 |
|---------|------|
| Menu bar app - Shows temperature and fan speed | 菜单栏应用 - 实时显示温度和风扇转速 |
| Automatic mode - Adjusts fan based on temperature curve | 自动模式 - 根据温度曲线自动调节风扇 |
| Manual mode - Set a fixed fan speed | 手动模式 - 设置固定风扇转速 |
| Customizable curves - Edit temperature-to-RPM mapping | 自定义曲线 - 编辑温度到转速的映射 |
| Safe mode - Auto-recovery on failures | 安全模式 - 异常时自动恢复 |
| Exit recovery - Restores auto mode when quitting | 退出恢复 - 退出时自动恢复自动模式 |

## What's New in v2.1 / v2.1 新特性

### v2.1 变更
- **品牌更新**：软件名称由 MacFanControl 更名为 iFanControl
- **版本号更新**：v2.0 → v2.1

### v2.0 改进
- **一次性授权**：安装时只需输入一次密码，之后永久免密运行
- **修复"应用已损坏"**：自动处理 quarantine 属性
- **更稳定的安装**：使用 sudo 直接执行，不再依赖 osascript

---

## Quick Install / 快速安装

### English

1. Download `iFanControl-2.1.zip` from [Releases](https://github.com/PureMilkchun/mac-fan-control/releases/tag/v2.1)
2. Unzip the file
3. Open Terminal and run:
   ```bash
   cd ~/Downloads/iFanControl-2.1 && ./install.sh
   ```
4. Enter your admin password (only once)
5. Done! The app runs without requiring passwords anymore

### 中文

1. 从 [Releases](https://github.com/PureMilkchun/mac-fan-control/releases/tag/v2.1) 下载 `iFanControl-2.1.zip`
2. 解压 ZIP 文件
3. 打开终端，运行以下命令：
   ```bash
   cd ~/Downloads/iFanControl-2.1 && ./install.sh
   ```
4. 输入管理员密码（仅需这一次）
5. 完成！之后运行应用永久免密

### 安装指南

> 解压后可打开 `安装说明.html` 查看图文安装指南

## Usage / 使用方法

### English

1. Open `/Applications/iFanControl.app`
2. The app appears in your menu bar showing temperature and fan speed

**Menu Options:**
- **Fan Curve Editor** - Customize the temperature-to-RPM curve
- **Manual Mode** - Set a fixed fan speed
- **Auto Mode** - Follow the temperature curve (default)
- **Auto Start** - Launch at login

### 中文

1. 打开 `/Applications/iFanControl.app`
2. 应用会出现在菜单栏，显示温度和风扇转速

**菜单选项：**
- **风扇曲线编辑器** - 自定义温度到转速的曲线
- **手动模式** - 设置固定风扇转速
- **自动模式** - 根据温度曲线调节（默认）
- **开机自启动** - 登录时自动启动

## How It Works / 工作原理

### English

iFanControl uses [kentsmc](https://github.com/exelban/kentsmc) to:
- Read CPU temperature from SMC sensors
- Control fan speed via SMC writes
- Run as a normal macOS app with `sudo -S` for privileged operations

### 中文

iFanControl 使用 [kentsmc](https://github.com/exelban/kentsmc) 来：
- 从 SMC 传感器读取 CPU 温度
- 通过 SMC 写入控制风扇转速
- 以普通 macOS 应用运行，使用 `sudo -S` 执行特权操作

## Requirements / 系统要求

- macOS 13.0 or later / macOS 13.0 或更高版本
- Apple Silicon Mac (M1/M2/M3/M4)
- Admin password for initial setup / 首次设置需要管理员密码

## Uninstall / 卸载

在解压目录中运行 `./uninstall.sh` 或执行以下命令：

```bash
cd ~/Downloads/iFanControl-2.1 && ./uninstall.sh
```

## License / 许可证

MIT License - see [LICENSE](LICENSE) for details.

MIT 许可证 - 详见 [LICENSE](LICENSE)。

## Credits / 致谢

- [kentsmc](https://github.com/exelban/kentsmc) - SMC access tool / SMC 访问工具
- [Stats](https://github.com/exelban/stats) - Inspiration for fan curve editor / 风扇曲线编辑器灵感来源

## Disclaimer / 免责声明

### English

This software interacts with low-level hardware controls. Use at your own risk.

### 中文

本软件涉及底层硬件控制，使用风险自负。