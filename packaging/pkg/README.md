# iFanControl PKG 构建

从 active 工程的 App 与 kentsmc 构建系统安装包，不执行安装。

```sh
python3 packaging/pkg/build.py --app iFanControl.app --tool kentsmc
python3 packaging/pkg/verify_channels.py
```

也支持用 --source-zip /path/archive.zip --manifest /path/legacy-manifest.json 读取经过校验的旧版 ZIP。

包内包含 App、kentsmc 与所需授权配置，不包含用户 config.json。介绍页嵌入真实 App 图标，结束页保留系统原生打钩；左侧提供打开 App 和系统阻止打开时的操作提示。适用于 Apple Silicon、macOS 26 或更新版本、当前启动磁盘；安装前须退出 App。已有配置、日志和开机自启动设置会保留。

构建会展开最终安装包并核对文件、脚本、代码签名与校验值。输出中的 build-info.json 记录来源与验证。

旧版 update-manifest.json 和 iFanControl-legacy-2.9.9.zip 永久保留在 2.9.9/build52；legacy-channel.json 固定版本与哈希，verify_channels.py 在发布前检查。2.9.9/build52 开始只读取 update-manifest-pkg.json，后续发布只修改新通道和最新 PKG，绝不覆盖旧通道或旧 ZIP。
