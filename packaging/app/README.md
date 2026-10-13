# App源元数据

`Info.plist` 是App版本、build、通道和系统要求的提交来源。`scripts/build_app.py` 将它与编译结果及根目录图标组装成 `build/iFanControl.app`，再执行原有ad-hoc签名校验。

未来发布先修改并提交此文件。生成的App bundle和签名不入库；根目录原有 `iFanControl.app` 可暂时保留作为本机历史构建，不再作为版本配置来源。
