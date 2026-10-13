# Stats 适配研究数据

固定上游：`exelban/stats@88d5359ad3466efaa16985646a0bb15c6599109f`，2026-10-13 获取。

- `temperature-catalog.csv`：从 `Modules/Sensors/values.swift` 提取的 204 条温度声明，分为 193 条 SMC 模板、11 条 HID 模板。保留平台、类别、平均资格、源文件行号；不展开 `%`，不把 HID 名称当四字符 SMC key。
- `upstream.json`：平台集合、固定提交和已阅读源文件的 SHA256。这里包含上游的 M6/A18 Pro 等声明，**仅表示上游存在该声明，不表示本产品已支持或实测过这些设备**。
- `LICENSE.stats`：派生目录数据所对应的完整 MIT 许可和版权声明。
- `acceptance-scenarios.json`：后续适配的合成输入和验收要求，**尚未接入产品测试，也未运行硬件验证**。

完整分析见 [设备适配研究](../3.0-device-compatibility.md)。这些数据目前不被 App 加载，也不会改变控温行为。

## 离线复核

在项目根目录运行：

```sh
python3 scripts/audit_stats_compatibility.py
```

生成详细差异：

```sh
python3 scripts/audit_stats_compatibility.py --output packaging/pkg/output/stats-compatibility/catalog-audit.json
```

若已取得 `upstream.json` 指定提交的原始文件，可核对全部下载文件的哈希，并重新提取温度目录验证 CSV：

```sh
python3 scripts/audit_stats_compatibility.py --verify-upstream packaging/pkg/output/stats-compatibility/upstream
```

脚本不联网、不构建、不调用 kentsmc、不写风扇。它比较 Swift 源码中的静态字面量；目录结构或构造方式变化时需要更新解析器。名称差异不等于温度值错误，静态 key 覆盖不等于运行时支持，验收要求不等于现有功能已经通过测试。

原始下载放在忽略的 `packaging/pkg/output/stats-compatibility/`；持久证据由本目录的快照、哈希、固定源链接提供。以后更新上游时应另存提交记录，复核变化，不自动覆盖固定输入或生产传感器表。
