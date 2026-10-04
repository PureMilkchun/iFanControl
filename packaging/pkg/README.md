# iFanControl PKG 构建

从已校验的发布 ZIP 构建系统安装包，不执行安装。界面与脚本源自已通过用户网络下载测试的安装实验。

```sh
python3 packaging/pkg/build.py --source-zip /path/iFanControl-macOS.zip --manifest /path/update-manifest.json --output /path/output
```

包内包含 App、kentsmc 与所需授权配置，不包含用户 config.json。介绍页嵌入真实 App 图标，结束页保留系统原生打钩；左侧提供打开 App 和系统阻止打开时的操作提示。适用于 Apple Silicon、macOS 26 或更新版本、当前启动磁盘；安装前须退出 App。已有配置、日志和开机自启动设置会保留。

构建会展开最终安装包并核对文件、脚本、现有代码签名与校验值。输出中的 build-info.json 记录来源与验证。
