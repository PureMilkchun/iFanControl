# macOS 15 间接兼容性研究（2026-10-15）

维护者补充：底层控制近期没有修改，自己也由旧系统升级；目前只能间接查询，不以取得旧设备实测作为本轮研究的前提。

结论：**优先恢复macOS15兼容具有充分的技术调查依据，目前没有查到必须因风扇控制而要求26的证据。** 已确认的用户启动阻断是App声明26，PKG也另设26门槛。现有工具的26二进制声明值得处理，但不能单凭该声明认定15必然无法运行。此为静态/上游源码推断，不是旧系统运行验收；当前正式71仍要求26，没有发布兼容包。

## 证据及推断边界

### 1. 底层工具没有随本轮UI/PKG发布而改变

当前kentsmc、工程保留的2.8.27工具、Git提交d28e47f（2.8.20）的工具，以及公开2.9.8/build50 ZIP内工具，SHA256均为`56b9b4f7239b4b043b8b69c92ed23f184eaf55a6b7d67c419d899da3a7254605`。

因此，此次2.9.9/3.0并没有换入一个新的风扇工具；“旧工具正常、新工具不兼容”不符合已检查产物。维护者旧系统使用经历是有利的历史线索，但未对应到精确系统/build/工具哈希，不把它写成已完成的15.2测试。更早d95c524工具哈希不同，不能外推所有历史版本均为同一工具。

### 2. 主程序与安装入口的要求不一致

Package.swift目标为13，发布71的App Mach-O最低13；但packaging/app/Info.plist的LSMinimumSystemVersion为26，packaging/pkg/build.py将PKG产品要求也写成26。Apple明确说明[LSMinimumSystemVersion控制App最低系统及不满足时的提示](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/LaunchServicesKeys.html#//apple_ref/doc/uid/TP40009249-SW1)。

因此，“升级后提示需要26”已有确定的声明层原因，不能当作风扇算法或硬件接口已在15失败的证据。App target13也不代表所有附带工具自动符合13。

### 3. 工具实际导入的硬件接口早于15存在

只读nm/otool确认当前工具的IOKit导入包括IOMainPort、kIOMainPortDefault、IOServiceMatching、IOServiceGetMatchingService、IOServiceOpen、IOConnectCallStructMethod、IOServiceClose、IOObjectRelease。

Apple的[IOKitUser头文件](https://github.com/apple-oss-distributions/IOKitUser/blob/323ead896d04424f87184d8f6ff0cce811aab106/IOKitLib.h)将IOMainPort及kIOMainPortDefault标为macOS12起可用；其余列出的服务/调用接口也没有26专属标注。此证据支持API可用性，不承诺每台机器的SMC键、写入权限或固件行为一致。

当前工具还导入Swift的getTypeByMangledNameInContext2/getTypeByMangledNameInContextInMetadataState2。两者已存在于[Swift6.0 RuntimeFunctions.def](https://github.com/swiftlang/swift/blob/swift-6.0-RELEASE/include/swift/Runtime/RuntimeFunctions.def)，后者分类为SignedDescriptorAvailability；[FeatureAvailability.def](https://github.com/swiftlang/swift/blob/swift-6.0-RELEASE/include/swift/AST/FeatureAvailability.def)将SignedDescriptor归入Swift5.9，并非26才有的新特性。实现可见同tag的stdlib/public/runtime/MetadataLookup.cpp。这排除了这两个重点符号“只在26出现”的猜测，没有完成对226个未定义符号在15.2系统实际导出表中的逐项确认。API基线JSON不是系统动态库导出表，不拿它充当全部符号已满足的证据。

### 4. 命令行工具minos不能与App启动门槛混为一谈

工具LC_BUILD_VERSION为minos26/sdk26.4，属于构建时的最低目标声明，确实不规范地高于期望支持系统；但不能推导“看到26就一定被内核/dyld拒绝”。

Apple [dyld-1231.3 Loader.cpp](https://github.com/apple-oss-distributions/dyld/blob/dyld-1231.3/dyld/Loader.cpp#L2790)中，tooNewErrorAddendum用于缺失符号报错的附加说明；先有Symbol not found路径，才附上built for newer OS文字。Apple [XNU mach_loader.c](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/mach_loader.c)的LC_BUILD_VERSION处理记录platform/sdk/minos，所检查分支未仅按minos高于系统拒绝。所查dyld的MachOAnalyzer/JustInTimeLoader也没有发现仅据此执行的通用版本拒绝。

这些源码支持“不能仅凭minos作失败判断”，不构成所有加载路径都兼容的证明。缺失强链接库/符号、签名格式和运行时行为仍可能失败；不修补工具Mach-O来制造兼容结论，也不把App的LaunchServices门槛取消后称为已经实测。

### 5. Stats提供同类实现的旁证

[Stats固定源码](https://github.com/exelban/stats/blob/88d5359ad3466efaa16985646a0bb15c6599109f/SMC/smc.swift)同样通过AppleSMC、IOServiceOpen和IOConnectCallStructMethod读写，包含F*Md/md、F*Tg及Ftst路径；其[工程配置](https://github.com/exelban/stats/blob/88d5359ad3466efaa16985646a0bb15c6599109f/Stats.xcodeproj/project.pbxproj)存在12/14等低于26的目标。Stats当前README声明支持12+。这说明同类控制不天然要求26，但不能把Stats测试结果直接归给我们的二进制，也不因此替换现有控制策略。

## 后续方向

1. 先以macOS15为兼容目标，统一App/PKG/更新准入规则，不一次扩展承诺到13/14或所有Apple设备。
2. 保持现有M4控制程序与kentsmc字节，先审查新旧App的依赖/界面调用、安装脚本和系统接管路径；若需工具重编译，取得对应源码后再处理，公开原版不能直接替换自定义解锁工具。
3. 允许据静态证据准备独立Beta候选，并明确尚未在15实测；不要因为没有旧设备就停止兼容工作，也不因搜索未发现问题就移除现有线上保护或直接推正式包。

本轮只进行网络查询、源码/二进制静态读取及文档记录。没有构建、安装、运行硬件命令、修改产品或部署。完整上游快照及导入列表留在忽略的packaging/pkg/output/macos15-incident/research/。
