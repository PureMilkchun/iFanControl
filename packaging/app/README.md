# App源元数据

`Info.plist` 是App版本、build、通道和系统要求的提交来源。`scripts/build_app.py` 将它与编译结果及根目录图标组装成 `build/iFanControl.app`，再执行原有ad-hoc签名校验。

品牌字标位于 `Sources/MacFanControl/Resources/Brand/`，直接使用已定稿Soft Cast字形的矢量PDF，不依赖额外字体。SwiftPM将其生成到 `MacFanControl_MacFanControl.bundle`；App组装时必须将整个资源bundle拷贝到 `Contents/Resources/`。`BrandIdentity` 使用原生label色适配浅色/深色，原风扇App图标仍由根目录 `icon.png` 提供。

本地审查构建：`python3 scripts/build_app.py --output build/brand-review/iFanControl.app`。真实窗口中英文、浅深色截图：`python3 packaging/pkg/test_ui.py --capture-directory packaging/pkg/output/app-brand-review`（隔离配置与硬件，截图使用原生窗口捕获）。这两步均不安装或发布软件。

未来发布先修改并提交此文件。生成的App bundle和签名不入库；根目录原有 `iFanControl.app` 可暂时保留作为本机历史构建，不再作为版本配置来源。
