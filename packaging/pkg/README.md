# iFanControl PKG 构建

2026-10-15应急保护：旧静态清单/双ZIP仍固定52，但线上旧manifest已按系统请求分流，旧系统/未知UA暂停升级。后续部署必须保留当前Production `6f3a60a0-a09b-42d7-99dc-cd5258aa943f`的guard和路由。`verify_channels.py`验证固定文件；线上行为另用`scripts/verify_legacy_os_guard.mjs`与公网UA检查。详见`../../docs/development/macos15-upgrade-incident.md`。当前71仍要求macOS26，旧系统兼容尚未验收。

从 active 工程的 App 与 kentsmc 构建系统安装包，不执行安装。

```sh
python3 scripts/build_app.py
python3 packaging/pkg/build.py --app build/iFanControl.app --tool kentsmc
python3 packaging/pkg/verify_channels.py
bash packaging/pkg/test_updates.sh
```

也支持用 --source-zip /path/archive.zip --manifest /path/legacy-manifest.json 读取经过校验的旧版 ZIP。

包内包含 App、kentsmc 与所需授权配置，不包含用户 config.json。介绍页嵌入真实 App 图标，结束页保留系统原生打钩；左侧提供打开 App 和系统阻止打开时的操作提示。适用于 Apple Silicon、macOS 26 或更新版本、当前启动磁盘；安装前须退出 App。已有配置、日志和开机自启动设置会保留。

构建会展开最终安装包并核对文件、脚本、代码签名与校验值。输出中的 build-info.json 记录来源与验证。

旧版 update-manifest.json 和 iFanControl-legacy-2.9.9.zip 永久保留在 2.9.9/build52；legacy-channel.json 固定版本与哈希，verify_channels.py 在发布前检查。2.9.9/build52 开始只读取 update-manifest-pkg.json，后续发布只修改新通道和最新 PKG，绝不覆盖旧通道或旧 ZIP。

## 开发者 Beta 通道（2.9.10/build62 起）

“关于/帮助 → 简介”的大 App 图标在同次开窗中点击十次，解锁持久保存的开发者模式。解锁不会自动启用 Beta；开发者页单独勾选后，手动与启动后的自动检查都读取 `update-manifest-beta.json`，复用正式版完整 PKG 更新链路。关闭 Beta 或退出开发者模式只改变后续检查路线，不降级当前 App。

正式和 Beta 共用递增的整数 build。Beta manifest 加 `release_channel: "beta"`，App Info.plist 加 `IFanControlReleaseChannel: "beta"`；系统版本仍为数字 `X.Y.Z`，构建号仍为整数。manifest 的可选 `release_url` 使用对应 GitHub Release/tag 的完整 HTTPS 链接，避免 Beta 更新失败时跳到错误的正式版 tag。

Beta 包使用独立且包含 build 的文件名，例如 `iFanControl-beta-3.0.0-63.pkg?build=63`，不能覆盖 `iFanControl-macOS.pkg` 或 legacy ZIP。Beta feed 也可以用 `release_channel: "stable"` 指向正式版本的独立副本；正式发布时同步它，避免 Beta 订阅者错过更高 build 的正式版。两份 native manifest 均需 `Cache-Control: no-store`。官网版本展示及 `/download` 始终保持正式线路。

`verify_channels.py` 在 Beta manifest 存在时额外校验隔离包、哈希和 build 顺序。`test_updates.sh` 验证兼容字段、偏好与点击边界，并编译真实 UpdateService 的隔离夹具：网络、弹窗选择、安装器打开和退出替换为测试接口，不执行实际安装或硬件控制。这些检查已接入 CI。

2.9.10 种子包在 `output/release-candidate/`，由开发者手动本地安装。用户确认先仅部署 Beta 线路，正式渠道维持 2.9.9/build52；初始 Beta feed 指向同一 build62 种子包的独立副本，`release_channel: "stable"` 表示该包的构建身份，不代表已向正式用户发布。下一 Beta build 必须大于 62，真实在线安装联调使用这个更高 build。

首次 Beta 部署准备与校验记录在 `output/beta-bootstrap-62/`。`release-candidate/channel-preview/` 是整套正式发布预览，**不要整体部署到生产做 Beta 测试**。Beta 单独发布只添加/更新 Beta manifest、独立 PKG 和该 feed 的 no-store 规则；不改正式 feed/包、`/download`、官网版本/时间线或正式 GitHub Release。Beta manifest 可省略尚不存在的 `release_url`，客户端失败提示会使用 Releases 首页。

2026-10-12 已单独发布2.9.10 Beta/build63，包与核验记录在 `output/beta-63/`，用于62→63在线安装联调。只增加Beta身份并递增build，签名前可执行代码与62一致，资源及安装脚本保留。云端只更新Beta feed和独立63 PKG，上一后端bundle/routes及其余54个资产完全保留；线上包/manifest及正式52线路核验通过。下一Beta或正式build须大于63。


## UI Beta 验收（2026-10-13）

当前稳定/旧线路52保持；本地64为验收起点，Beta在线65为同代码升级目标。完整原生证据与人工步骤见 `../../docs/development/3.0-ui-delivery.md`。

```bash
swift build -c release
bash packaging/pkg/test_updates.sh
python3 packaging/pkg/test_ui.py
```

原生控制器测试在macOS运行，编译实际源码并使用临时独立bundle/配置目录，替换反馈网络和功率初始化等外部效果。覆盖曲线精度/边界/最小布局/保存失败与配置保留、展示偏好、功率状态/计时器、反馈草稿/重开/发送状态；不安装、不控制风扇、不发送真实反馈。Beta线上资产冻结保护与PKG展开/签名/脚本验证继续按原发布流程执行。

## 启动等待回归（Beta70）

```sh
python3 packaging/pkg/test_startup.py
```

在独立AppKit夹具中运行真实AppDelegate启动流程，替换硬件/特权命令/网络与引导弹窗点击，使用独立偏好、配置和日志。覆盖普通、主线程探测等待6秒、无风扇、解锁失败、未来build回执及首次语言选择；核对先显示等待界面，再初始化菜单/控制循环，收起后才显示更新回执和启动引导。不会安装或控制真实风扇。真实运行时长仍须维护者实际升级后观察。

源码元数据已迁到 `../app/Info.plist`，App由根目录 `scripts/build_app.py` 生成，产物不入Git。分支/标签/发布证据见 `../../CONTRIBUTING.md`；Beta70已发布输入哈希保存在 `../../docs/releases/2.9.10-beta.70.json`。
