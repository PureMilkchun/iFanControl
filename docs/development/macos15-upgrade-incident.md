# macOS 15 用户收到不兼容更新：2026-10-15

维护者转述：用户从旧版更新至2.9.9后被提示需要macOS26，用户系统是15.2，已自行降级恢复。用户降级后的确切版本/build、遥测及实际调速情况尚待确认。

## 已确认的原因

- 官方2.9.8/build50 ZIP的App声明最低macOS13；2.9.9/build51开始将 `LSMinimumSystemVersion` 提高到26，build52过渡ZIP沿用26。3.0/build71也保持26。
- 旧更新器仅比较 `latest_build > currentBuild`，没有系统版本判断，也没有发送专门的系统字段。故“旧ZIP → 2.9.9 → PKG”仅说明包格式衔接，并不保证旧系统能运行中间版本。
- 71发布保留了52 ZIP和旧清单的字节，没有引入这一最低系统变化；但发布前没有验证整个迁移链对macOS15成立，属于明确的系统兼容验收遗漏。
- `min_supported_build` 和 `rollout_percent` 不是旧客户端的macOS门槛；添加一个旧客户端不读取的字段无法止住本次问题。

Apple的 [LSMinimumSystemVersion说明](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/LaunchServicesKeys.html)定义了App运行的系统门槛。不能仅以SPM target为macOS13或可执行文件能够链接，推断整个安装包满足旧系统运行要求。

## 已上线的临时保护

Production：`6f3a60a0-a09b-42d7-99dc-cd5258aa943f`，前一部署 `56371256-511d-4101-9f6d-0a8d25713eab` 保留。

仅为旧 `/update-manifest.json` 的GET/HEAD增加Pages响应保护：

- 能识别为原生CFNetwork、Darwin主版本≥25的请求继续读取原始2.9.9/build52清单。
- 低版本、缺少或无法识别系统信息的请求，返回 `latest_build: 0`、`assets: null` 的暂停响应。旧客户端会在下载前的build比较处停止，因此不提供不兼容安装包。0是临时协议哨兵，不是真实发布版本。
- 返回no-store及Vary: User-Agent，避免系统分流结果被复用。User-Agent不是可靠的身份凭据，未知情况必须保守暂停，不能推断为最新系统。
- 仍处于旧更新器的macOS26用户若请求头不含可识别信息，也可能暂时看不到过渡更新；可使用系统安装器的正式PKG。现有71客户端和Beta更新读取独立清单，不受此保护影响。

全部63个静态资产（含52清单、两个旧ZIP、71包、官网及时间线）、正式/Beta71 feed和运行绑定保持不变；没有改App或风扇策略。原始文件永久保留不代表所有系统都应收到该包。手动访问旧ZIP仍可下载，旧系统应保留已验证可用的版本，不能因自动更新暂停就认为旧ZIP现在兼容。

保护源码：`packaging/pkg/legacy-update-os-guard.mjs`。网站函数源副本位于父工程 `docs/functions/update-manifest.json.js`。该应急部署先执行、后补录Git源码；以记录的源码SHA256和部署内容为证据，不声称原发布标签已包含此保护。

## 验证与范围

运行 `scripts/verify_legacy_os_guard.mjs`，使用实际提交给Pages的worker模块和本地只读ASSETS完成16个断言：macOS13/14/15、未知/缺失/浏览器/异常UA暂停；macOS26及更高可识别请求返回原始52字节；native feeds、两个ZIP及/download不变；HEAD无正文。

公网复核macOS15.2模拟请求返回0/null，未知请求返回0/null，macOS26模拟请求返回与固定文件完全相同的52清单；全部63个资产及D1/环境/兼容参数保持。这里验证的是请求分流和旧客户端的比较契约，不是模拟出了macOS15运行环境。未实际安装、运行风扇工具或改转速。

完整证据在忽略的 `packaging/pkg/output/macos15-incident/`，持久摘要见 `docs/releases/macos15-incident-2026-10-15.json`。

## 旧系统兼容判断：继续调查，不直接降门槛发包

维护者选择优先兼容旧系统；若兼容困难，则保留旧系统维护线。

| 项目 | 2.9.8/build50 | 3.0/build71 | 含义 |
| --- | --- | --- | --- |
| App Info.plist最低系统 | 13.0 | 26.0 | 2.9.9起的实际启动阻断来自此声明 |
| App Mach-O最低系统 | 13.0 | 13.0 | 主程序具有回到13+验证的基础，不证明所有路径可用 |
| kentsmc哈希 | 56b9b4…7254605 | 相同 | 公开build50与71实际使用同一工具，不能凭版本名假设旧工具更兼容 |
| kentsmc Mach-O最低系统 | 26.0 | 26.0 | 工具的旧系统执行、符号和SMC行为必须实机确认 |
| PKG最低系统 | 不适用 | 26.0 | 需与App、工具及验证结果一致 |

已核对官方build50 ZIP SHA256为 `39fe6298e1cd8ec754ef9d64b7a82cefbf1737971234ecf540203e7c703ea532`。同一份工具在旧版中出现，不等于已证明它能在15.2读写硬件；Mach-O的26声明本身也不能替代实际执行结果，不能据此断言它在15必然失败。

主程序使用的SMAppService属于macOS13起的接口，未在Sources中发现直接使用26专属UI接口；但当前kentsmc没有对应源码/编译提交，公开原版缺少自定义解锁逻辑，无法直接用原版重新编译替换。把版本门槛改低、修补Mach-O或替换旧工具都不能视为完成兼容。

下一步需确认用户真实可用的降级版本，以及macOS15上的工具加载、温度/RPM读取、调速和系统接管。前两项可先做只读验证，控制写入再单独验收。取得对应源码和旧系统测试结果后，才将候选包标为兼容13/14/15；正式Mac mini M4线路和控制策略继续保持。

已准备本地`packaging/pkg/output/macos15-incident/iFanControl-macOS15-readonly-check.zip`（SHA256 `88313a07d5f72d9bf30fe792d0bd906a4056ee585028863ac3f79f54ca69dd42`），可由维护者转交受影响用户。内含固定工具和只读.command，报告系统/架构/机型以及已安装工具和附带工具的哈希、读取输出与退出码；只读FNum/F0Ac/Tp01/Tf04，不sudo、不安装、不联网、不写风扇。代理仅执行bash语法检查，未实际运行工具。个别温度key不可读不等于整体不兼容；该检测也不能证明控制写入、系统接管或整个App兼容。包未上传/推送为正式或Beta安装包。
