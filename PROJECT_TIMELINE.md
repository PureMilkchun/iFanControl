# iFanControl 时间戳记忆

关联固定记忆：`/Users/puremilk/Documents/mac fancontrol/macfan-control-v2/PROJECT_MEMORY.md`
读取建议：先读固定记忆，再读本文件，用本文件补足最近发生的变化。

## 2026-10-13

### 2026-10-13 — Git开发与发布机制

- 用户授权规范Git。将Beta70完整源码/测试/研发记录保存到codex/3.0-beta并建立注释标签；main和正式线路保持52，基线PR为Draft。
- App元数据移到packaging/app/Info.plist，新增从源码生成App的脚本及输入哈希校验；发布记录补录70的公网包/源码/部署身份，明确是发布后记录而非包内已有Git提交。
- 停止追踪生成App/签名与Cloudflare缓存，保留磁盘文件和旧历史；实验/邮件仍本机保留。69张已检查的原生截图迁为研发文档证据，图片字节不改。
- CI运行Release和真实更新/UI/启动回归，覆盖codex开发分支及PR；长期分支要求PR和build检查，禁止强推/删除，不要求单维护者取得第二人审核。
- 干净检出03e3d1d的App组装、更新/UI/启动回归和PKG构建通过。远端构建/更新检查通过后暴露反馈测试固定100ms等待的时序问题，改成有界等待真实发送完成；未改产品代码或已推送70标签。版本标签增加v*更新/删除规则保护。最终远端CI以PR #5检查项为准。规则见CONTRIBUTING.md。


### 2026-10-13 — 真实启动等待面板与回执顺序，Beta70

- 用户观察启动无持续反馈。原日志证实69硬件profile约7.7秒且随后仍有读取/解锁。新增非激活轻量面板，先显示再安排初始化，原生独立线程指示器覆盖同步探测，按硬件/偏好/菜单与控制阶段说明。
- 菜单、风扇解锁调用、控制循环及后台任务安排好即收起；更新完成回执及首次引导在其后，退出时停止并收起。首次引导之前控制循环已准备。保持现有探测/硬件顺序/控温安全/更新校验与PKG，不造百分比或固定等待，不以初始化完成声明硬件可控。
- Release、控制器、真实updater回归及新增实际AppDelegate隔离六场景通过；实际中文浅色/英文深色、三个阶段、启动后英文完成勾已查看。新夹具无真实硬件/网络，独立配置/偏好/日志。用户实际安装应用与进程未操作。
- Beta70 SHA256 `b446cf03a71c2d3e3652c715f702d7ad14ce4f4c52cc4fe5f53a709090b5cf7a`；Production `6066e693-f572-417a-b5b9-cd784c371078`。只Beta feed/独立70包，保留60个旧非Beta-feed资产及后端/绑定；公网逐字节、三feed JSON/no-store、正式/旧/download52核验见 output/beta-70/verification.json。
- 记录见 `docs/development/3.0-ui-startup.md`；新增test_startup.py/swift可重复验证。未安装/真实控温/发反馈、正式Release或提交/推送；夹具进程/偏好已清理。维护者69→70体验，下一build大于70。


### 2026-10-13 — 帮助侧栏比例与官网入口，Beta69

- 按截图反馈，导航文字12→14点、侧栏176→164点、选中背景152×30→140×28点；简介页原生“访问官网”位于检查更新/GitHub之间，打开项目官方域名。
- Release/原生控制器回归通过；实际中文浅色、英文深色、支持页和十次图标解锁后的开发者页均查看，官网按钮记录完整URL、HEAD200。修改仅HelpWindowController；其他源码/PKG脚本、反馈邀请、状态语义与完成勾保持。
- Beta69 PKG SHA256 `0e5f10be77debae51e87a1ea04495a65a97572887312e466e8a7981727800fb8`；Production `79022cbb-d7e0-4e84-842a-2b140f38bb21`。仅Beta feed/新69PKG，保留59个旧非Beta-feed资产及相同后端/绑定；公网逐字节/SHA和正式/旧/download52验收见 output/beta-69/verification.json。
- 记录见 `docs/development/3.0-ui-help-sidebar.md`。没有安装/真实控温、替换用户应用、发送反馈、正式Release、提交/推送；原生夹具进程/偏好已清理。维护者可从68在线更新69验收，下一build大于69。


### 2026-10-13 — 恢复反馈邀请设计与正确解释状态时间，Beta68

- 维护者明确邀请文本框用于鼓励反馈，不能因与标题同向或不可直接编辑删除。68恢复原文案/外观与点击进入独立窗口，透明原生按钮负责完整点击区域；中英文控件点击后反馈正文获得焦点。
- 核实recordedAt普通相同mode/detail签名不重写、force路径可强制写。顶部改“控制正常 + 自动/手动”，时间只在“最近一次状态记录”提示中；未改变记录频率或控温规则。
- Release/原生控制器回归通过，菜单夹具用12分钟前记录检验状态文案/邀请框/全部命令/菜单原地刷新；实际中文浅色、英文深色手动模式和进入反馈窗口已看。
- 只改MenuBarManager呈现与反馈点击路径，其他代码/PKG脚本保持。68包SHA256 aca31c48e7e2b1ed820748d031ab74c065dd2d935765e4d2179366c1fcf89ed2；Production9b2ca0fa-eb39-417d-a8f5-1d25fcb6b665，保护58个非Beta-feed资产/后端/绑定。正式/旧feed及官网下载仍52，最终线上核验见 output/beta-68/verification.json。
- 设计意图已提升到CLAUDE.md和固定记忆，原审视中“精简重复反馈入口”的建议已撤回；记录见 docs/development/3.0-ui-feedback-intent.md。未安装/控温/发送真实反馈/替换用户应用，未正式发布、提交或推送。


### 2026-10-13 — 主菜单与完成提示修正，Beta67

- 维护者确认“下拉框繁杂”指主菜单。信息栏设置简化试稿撤回，原设置精确恢复66。
- 主菜单状态卡收为一行；低频设置集中子菜单，硬件/当前温度源信息进入对应子菜单；常用操作与全部selector保留，重复标题/分隔线移除，同一菜单原地刷新保持。
- 完成提示采用单一圆角填充及原生阴影，勾24→36点；0.24秒描边、减少动态效果和非阻断自动消失保持。实际中文浅色/英文深色、手动菜单、子菜单与深浅色提示已看；原生RGBA四角alpha0、深色边缘亮像素0。
- Release、控制器回归通过；最终菜单夹具运行全部13个操作/手动可见性/选中态/同一菜单对象断言后展示。保护记录证实只改菜单呈现与InteractionNotice，其他控温/配置/更新/PKG行为保持。
- Beta67 PKG SHA256 `18fba494216e4e4ebb85223ea4ea9f5d9f250cfe64a257706083f59daf836e92`；Production `62d8bf39-9351-4f9f-8d1b-89e91ec69651`。公网重下载/SHA相同，原57个非Beta-feed资产和后端/绑定保持；正式/旧feed及HEAD官网下载仍52。
- 记录见 `docs/development/3.0-ui-menu-notice.md`。没有真实安装/控温、替换用户应用、发送反馈、正式Release或提交/推送；人工从66在线升级67体验，下一build大于67。


### 2026-10-13 — 原生UI第二轮与Beta66

- 用户认为第一轮视觉不如原版；安装/阅读redesign-existing-projects、macos-app-design及原生参考，按菜单栏工具重新设计层级和密度，不将测试通过视为审美结论。
- 显示设置横向精简、曲线数值按需展开并保留无效输入可见、调速/功耗读数分级、700×500帮助只布局活动页、支持/反馈主次动作调整、完成勾0.24秒描边且尊重减少动态效果。详见 `docs/development/3.0-ui-polish.md`。
- Release/原生控制器/真实updater隔离回归通过；中文浅色、英文深色主要窗口与分档/无数据/反馈成功/下载大小未知/打开失败重试/取消/回执勾实际查看。原生九/十次隐藏解锁及Beta独立选择核对。
- 对照65保护硬件/遥测/控温/Config/更新协议和传输/反馈传输/生命周期/PKG脚本。没有替换用户应用、真实安装/控温或发送反馈；系统Installer完成页未重新复演。
- Beta66 PKG SHA256 `202343b95ef5938d1f3508a05d05843a92d03da3efd6f90db5c9427803c24057`；Production `91662a64-a4c5-41ca-9a1a-7b1109678715`，前一65部署保留。原56个非Beta-feed资产、后端bundle/绑定不变，线上PKG重下载匹配；正式/旧manifest及HEAD `/download` 保持52。
- 用户从65在线更新66验收原设置与真实安装收尾，随后评价视觉与日常操作。下一build大于66；未创建正式Release、提交/推送或整理旧文件。


### 2026-10-13 02:21 — 四组UI改善完成自主验收，交付人工验收

- 完成更新状态/取消/重试及真实安装版本确认、原生菜单与展示预览、曲线数值与真实保存反馈、帮助支持/反馈/功率/首次说明四组工作，细项见 `docs/development/3.0-ui-delivery.md`。
- 沿用已核实的设计理由：菜单一次构建/原地刷新、曲线关闭保存与预设即时通知、RPM显式应用、SHA256唯一校验、110℃保护规则、正常退出恢复系统控风与原生PKG完成勾。
- Release构建、真实updater夹具、实际原生控制器回归通过；原生中文浅色/英文深色、键盘控制点/边界/无效输入、保存失败/重试、九/十次解锁、下载/取消/失败恢复与轻量完成提示已查看。修正自绘曲线越界遮挡、英文赞赏文字截断、发送旧状态与重开延时关闭问题。
- 64本地验收起点 SHA256 `7b5bc24472446ed4fcecf2288d15b488dc70599063cfef3896f657adcd7019b8`；65线上目标 `d4778e53e8420faf1e359c9176cf9094ec9c114e49709cf515fcd23061d393bd`。两者签名前执行代码相同，仅build/签名不同；源码/构建记录在各 output/beta-* 目录。
- Production `61e8903f-d65f-48fd-b6ad-15dfbbf52431` 成功；仅Beta feed/独立65PKG新增变化，55个非Beta-feed旧资产和后端/绑定不变。公网65包逐字节/SHA核对通过，Beta65/正式52/旧52 JSON/no-store，HEAD `/download` 仍52。
- 实际Installer查看65欢迎/目的宗卷/安装类型，未安装、未替换用户应用、未发真实反馈、未运行真实控温。人工需先本地安装64，再Beta升级65，验收PKG系统完成动画、重启、设置及设备控制。测试应用进程/偏好清理，用户原运行进程保留；未提交/推送源码或创建正式Release。


### 2026-10-12至13日 — 3.0 UI 全流程审视

- 用户确认已通过Beta更新到63，要求先梳理全部UI，再改善“简洁、优雅、高效”；明确PKG流程及系统完成勾是设计基准。
- 新增 `docs/development/3.0-ui-audit.md`，盘点菜单、设置/曲线/功率/反馈、五个帮助页面、首次启动、更新状态、安装/失败/卸载等入口，注明当前设计理由和观察/源码证据边界。
- 隔离原生探针使用独立偏好/配置与模拟遥测，不启动AppDelegate或控温；CUA查看中文浅色、代表性深色及英文深色，观察应用反馈、空输入验证、原生菜单和十次解锁。截图在 `packaging/pkg/output/ui-audit-63/`。
- Installer实际查看63包的介绍/目的宗卷/安装类型，未点击安装，预览已关闭。保留原生完成勾的依据来自用户体验说明及未自定义conclusion的包配置，不宣称本轮复演了完成动画。
- 发现更新下载/校验期间无可见状态、信息栏组合缺少最终预览、曲线自动保存缺少完整完成反馈、支持动作/卸载层级及英文标题截断；核对安全文案95℃与明确改为110℃的历史，UI说明改进不能反向改控温规则。
- 整理分批方案与验收：优先完整更新状态反馈，随后菜单/展示、曲线、帮助/支持；产品源码/安装脚本经hash核对保持Beta63原样，无新构建或线上发布。

## 2026-10-12

### 2026-10-12 — 2.9.10 Beta/build63 在线升级联调发布

- 用户要求发布更高 Beta build 测试62→63更新线路；本次只增加 Info.plist Beta身份并递增build，重新生成ad-hoc签名，签名前可执行代码与62一致，资源/控温/配置/安装脚本未改。
- PKG `packaging/pkg/output/beta-63/iFanControl-2.9.10.pkg`，SHA256 `fd8c59d08c02f1f3a6dcd6c05f8bc2de662d61786b6617bb28b946dec80a7391`；包展开/签名/脚本检查及更新测试通过。
- 独立原生帮助窗口实际截图查看“版本2.9.10 Beta (63)”，只使用隔离偏好域，未运行AppDelegate/硬件控制；测试窗口已关闭、测试偏好已清理。
- 只上传Beta manifest和独立63 PKG，复用上一Production的完全相同后端bundle/routes；保留原54个非Beta-feed资产、D1/环境/兼容设置和旧62包。
- Production `a0b0d0c8-ba6c-4102-bf91-53b43b6fccf4` 成功，线上Beta63包及三份manifest重新下载匹配；Beta标识/JSON/no-store正确，正式/旧manifest及 `/download` 保持52。
- 未创建正式Release、提交/推送源码或操作用户安装；实际下载安装、重启及配置/Beta偏好保留待用户执行。

### 2026-10-12 — 仅部署 Beta 线路，正式渠道保留 build52

- 用户确认手动安装 build62 种子包，再独立迭代 Beta，安全后才正式发布。
- 新增 `update-manifest-beta.json`、独立 build62 PKG 与 Beta feed 的 no-store 规则；不改正式 manifest/PKG、旧 manifest/双 ZIP、官网下载入口、页面、时间线或正式 GitHub Release。
- 使用旧 Production 资产清单构建隔离 staging，新部署保留原 53 个资产哈希、7 个后端函数源码、D1/环境及兼容设置；保留与线上不同的本地 schema 修改。
- Wrangler 连接失败后，经已授权 Cloudflare API 提交同一编译 bundle/资产清单，Production `cb249cea-6cb3-4703-84b2-477f13454a28` 成功。
- 线上 Beta build62 PKG 与本地种子包 SHA256 一致；正式/旧 manifest 仍为 build52，正式 PKG 与旧版 ZIP 哈希不变。实际在线安装升级待大于 62 的新 Beta build 联调。

### 2026-10-12 — 3.0 筹备与 2.9.10/build62 候选版

- 完整梳理当前 App 源码、更新/打包链路与关键提交，记录设计约束、资料差异和分阶段整理建议。
- 用户确认先完成隐藏 Beta 更新通道：简介大图标同次开窗十次解锁，开发者模式持久保存，单独勾选 Beta；关闭/退出仅切后续更新路线。
- 候选版本设为 2.9.10/build62（52 加 10），保持正式用户原有界面与更新体验；硬件、控温、曲线、配置、遥测、菜单轮询和 PKG 安装脚本未改动。
- 新增更新偏好与 Beta feed 支持，复用正式 PKG 流程，避免通道切换后旧请求结果提示或安装；加入通道隔离、损坏包、真实更新服务夹具及 CI 检查。
- 生成候选 PKG 与两份 native manifest 的独立待发布预览，legacy 文件及线上正式入口未改动；初始 Beta feed 使用同一正式包的独立副本。
- 完成原生帮助窗口十次点击/默认隐藏/退出和深浅色检查。候选包仅在开发目录构建，尚未安装、发布或推送给用户。

## 2026-10-05

### 2026-10-05 — v2.9.9 / build 52（安装与更新通道修正）

- 先撤下 build51 的 GitHub 安装包和官网分发，再以同一公开版本发布修正版。
- 2.9.9/build52 起通过独立新通道下载 PKG、校验、打开系统安装器并退出 App；去掉应用内 ZIP 解压与终端安装。
- 旧 update-manifest.json 永久停在 2.9.9/build52，保留原有完整 ZIP 更新方式及官网下载入口；后续版本只更新新通道。
- 添加冻结通道版本/哈希保护和 PKG 元数据、校验失败测试；未替换用户 /Applications 中的 2.9.8。

## 2026-10-04

### 2026-10-04 — v2.9.9 / build 51（优化安装体验）

- 将用户已完成网络安装测试的 PKG 方案用于新安装：真实 App 图标、简洁介绍、系统原生完成打钩，以及打开 App 的提示。
- 卸载密码说明使用加粗紫色，紧邻实际密码输入位置；同步 App 内与独立卸载脚本。
- 保留 2.9.8 的 ZIP 应用内更新兼容入口，build 递增至 51。官网与 Release 同时提供 PKG/ZIP，公开更新说明“优化安装体验”。
- 旧版到 2.9.9 的实际升级测试由用户执行。

## 2026-07-23

### 2026-07-23 — v2.9.8 / build 50 发布（曲线 Y 轴方向切换）

- 风扇曲线编辑器新增 Y 轴「正向 / 反向」显示选项，默认保持正向
- 只改变坐标显示与拖拽换算，不修改曲线数据、预设或实际控温逻辑
- 保留 CPU / GPU 平均温度来源，并修复部分问题、提升稳定性

## 2026-07-16

### 2026-07-16 — v2.9.8 / build 48 发布（CPU/GPU 平均温度源）

- **新增温度源**：支持分别按 CPU 传感器平均值或 GPU 传感器平均值驱动风扇曲线
- **传感器兼容性**：静态传感器目录与动态发现并行，未知但可读取的温度 key 仍可参与选择
- **对外说明**：新增 CPU / GPU 平均温度来源，修复部分问题并提升稳定性

## 2026-05-27

### 2026-05-27 — v2.9.8 / build 47 发布

- **对外说明**：修复部分 bug，提高稳定性。
- **发布渠道状态**：官网 `timeline.json`、`update-manifest.json` 与 App 内更新基线已同步到 `v2.9.8 / build 47`
- **文档补记**：主仓项目文档在 2026-06-10 补齐本条，避免固定记忆继续停留在 build 46

## 2026-05-11

### 2026-05-11 — 官网新增「用户声音」板块

- **新板块上线**：在 Iteration Section 和 Timeline Section 之间新增 voices-section，展示真实用户反馈如何推动产品改进
- **板块布局**：左栏三张统计卡片（已采纳建议 2 条 / 平均响应 <24h / 采纳到上线 ≈0.5d）+ 右栏反馈轮播卡片
- **卡片设计**：方正上下分区结构——上部「用户反馈」标签 + 引用正文（display font），下部「我们做了什么」标签 + 改进描述（sans font），底部时间线 meta 栏
- **两条反馈内容**：风扇曲线三预设系统（开发者自身） + 散热异常提醒（1836654086@qq.com 已授权匿名引用）
- **轮播机制**：圆点导航 + 6 秒自动切换 + hover 暂停 + 中英双语渲染
- **响应式**：四大断点适配（>1179px 左右并排 / <819px 上下堆叠 / <640px 统计上一下二排列）
- **技术细节**：数据通过 fetch `voices.json` 加载（部署后生效）、CSS 按规范重命名为 `styles.20260511a.css` 避免 CDN 缓存
- 涉及文件：`docs/index.html`、`docs/voices.json`、`docs/styles.20260511a.css`
- 已部署到 Cloudflare Pages

## 2026-05-10

### 2026-05-10 — v2.9.8 / build 46 发布（菜单栏显示修复 + 遥测稳健性提升）

- **菜单栏不显示修复**：修复少数设备上 App 进程已启动但菜单栏没有显示的问题。启动阶段不再因为同步动态传感器发现阻塞主线程，菜单栏与控制循环可先正常起来。
- **传感器发现增强**：温度传感器从“纯静态白名单”升级为“静态 catalog + 动态发现”双轨策略；未知但可稳定读取的 `T*` key 不再被直接忽略。
- **遥测容错与安全控制增强**：后台单轮温度 / RPM 读取全失败时不再立即清空最后成功快照；控制循环改为区分 `fresh / cached_stale / expired` 三种状态，短时遥测空窗优先继续使用最后成功快照并进入更保守控制。
- **诊断增强**：fallback / fail-safe 日志新增 `model / os / telemetryState / tempAge / rpmAge / reason code`，便于后续定位 M4 / M5 / MacBook Pro 机型上的真实根因。
- **发布渠道状态**：本次按新 build 46 正式发布，不覆盖 build 45；已同步新 ZIP、官网 ZIP、`update-manifest.json`、`timeline.json` 与 GitHub Release。

## 2026-05-05

### 2026-05-05 — v2.9.8 / build 45 发布（功率展示 + 规则型散热异常提醒）

- **状态栏遥测失效显示修复**：后台温度 / RPM 遥测超过 stale 阈值后，菜单栏完整 / 简洁 / 迷你三种模式统一显示 `--` 占位，不再继续挂旧数值
- **信息栏展示重构**：双层信息栏改为上层 / 下层内容可多选，并新增核心功率展示；样式统一作用于每层已选内容
- **电力消耗窗口**：新增“电力消耗...”窗口，可直接查看 CPU / GPU / ANE / RAM / PCI / DC In 等实时功率
- **散热异常提醒**：新增基于 10 分钟窗口、低输入功率 + 高风扇 + 高温条件的规则型异常提醒，带 12 小时冷却期
- **发布渠道状态**：GitHub Release、官网 ZIP、`update-manifest.json`、`timeline.json` 已同步到 `v2.9.8 / build 45`

## 2026-05-04

### 2026-05-04 — v2.9.8 / build 44 发布（迷你模式自定义 + 信息栏弹窗设置）

- **迷你模式上下行自定义**：上行/下行均可选择温度或转速的任意组合（含单位、模式），不再固定「温度在上、转速在下」
  - 7 种内容选项：温度、温度+单位、温度+模式、温度+全部、转速、转速+单位、转速+简称（`2400R`）
  - 交换按钮：一键互换上下行内容
  - 默认配置：上行 `65℃｜A`，下行 `2400 RPM`（带单位）
- **信息栏展示改为弹窗设置**：新增 `DisplaySettingsWindowController`，菜单栏「信息栏展示...」点击后弹出独立窗口，显示模式（完整/简洁/迷你）+ 迷他选项均在弹窗内操作，设置即时生效
  - 迷你选项区缩进 + 次级标签（小字灰色），与主选项视觉分层
- **清理死代码**：移除 `menuKeepOpen`、`menuDidClose`、9 个未赋值的 `NSMenuItem?` 属性、5 个旧 action 方法、`NSMenuDelegate` 协议遵循
- **Release 发布**：GitHub Release、官网 ZIP、update-manifest.json、timeline.json 已同步到 build 44

### 2026-05-04 — v2.9.7 / build 43 发布（迷你双行显示模式）

- **迷你双行显示模式**：菜单栏可显示两行紧凑信息，大幅减少横向占用
  - 上行：转速数字（如 `1204`）
  - 下行：温度｜模式字母（如 `45｜A`）
  - 颜色编码：A/M 正常时绿色，异常状态红色
  - 技术实现：`renderMiniStatusImage()` 渲染 NSBitmapImageRep 为图片（NSStatusBarButton 不支持多行文字）
  - 上下两行独立居中，避免 monospacedDigitSystemFont 中空格与数字宽度不同导致的对齐问题
- **菜单栏布局优化**：重新排布菜单分组（控制→设置→帮助→反馈→退出）
- **温度源选中态修复**：修复选择特定温度源后"自动选择（最热）"仍显示勾选的 bug
- **控制状态卡片颜色编码**：正常（绿色）、2200 RPM 兜底（红色）、已交还系统（橙色）
- **菜单宽度收窄**：整体菜单更窄，减少屏幕占用
- **发布渠道同步**：GitHub Release、官网 ZIP、update-manifest.json、timeline.json 已同步到 build 43

## 2026-05-03

### 2026-05-03 — v2.9.6 / build 42 发布（菜单布局优化）

- **菜单分组重排**：控制项（自动/手动、风扇曲线、温度源）在顶部，设置项（安全转速、开机自启）在中部，帮助/反馈/退出在底部
- **温度源选中态修复**：`hottestItem` 改为实例变量，`updateDynamicMenuItems()` 正确更新选中态
- **控制状态卡片重设计**：字段标签改为"控制状态"/"状态刷新"，底部左侧显示状态值（粗体彩色），右侧显示时间
- **菜单收窄**：移除冗余间距，整体更紧凑
- **发布渠道同步**：GitHub Release、官网 ZIP、update-manifest.json、timeline.json 已同步到 build 42

### 2026-05-03 — v2.9.5 / build 41 发布（信息栏展示设置）

- **信息栏展示设置**：菜单新增「信息栏展示」子菜单，支持「完整」和「简洁」两种模式
  - 完整模式：保留原有 `65℃ | 2400 RPM [Auto] 🔥` 样式
  - 简洁模式：`53｜981｜A`，无单位显示，全角竖线分隔，模式只显示首字母
  - 偏好存 `UserDefaults("ifancontrol.ui.display_mode")`，切换即时生效，无需重启
- **统计后台改进**：
  - 用户详情页「首次出现时间」从纯日期改为显示具体时间戳（`toLocaleString`）
  - 累计下载卡片新增「今日 +X」小字显示，复用用户卡片样式
  - 后端 `summary.js` 新增 `today_downloads` 字段，从 `daily[daily.length - 1].downloads` 取今日下载数
- **每周升级公告规范**：新建 `ANNOUNCEMENT_SPEC.md`，记录公告格式模板、数据统计获取方式、叙述口径
- **发布**：ZIP + 官网 + update-manifest.json + GitHub Release 四项同步
- 涉及文件：`Sources/MacFanControl/main.swift`、`ifan-stats/user.js`、`ifan-stats/app.js`、`ifan-stats/functions/api/dashboard/summary.js`、`docs/update-manifest.json`、`docs/timeline.json`

## 2026-05-02

### 2026-05-02 — 用户详情页 + 活跃日历重设计

- **用户详情页**：新建 `user.html?id=N`，深度展示单用户数据
  - 卡片：用户编号、使用时长排名、首次出现、在线状态、等效使用时长、活跃天数、最长连续活跃、留存率
  - 活跃日历：≤30 天用水平条纹视图（自适应条形图 + X 轴刻度 + 网格线），"全部"保留 GitHub 周网格
  - 活跃时段：折线图 + Canvas hover tooltip（时段 + 桶数）
  - 版本升级时间线（HTML/CSS）、用户反馈表格、用户故事叙事
  - 用户快速切换：顶栏 `←` / `→` 箭头 + 下拉选择器
- **后端 API**：
  - `GET /api/dashboard/user?id=N`：单用户全维度聚合数据（bucket_activity + flags + feedback）
  - `GET /api/dashboard/users`：用户列表 + total_buckets（两条 batch 查询，JS 层合并，避免 D1 子查询超时）
- **主页入口**：用户筛选旁新增「详情」按钮，选中用户后显示
- **主页改进**：累计用户量卡片显示「今日 +N」新增用户数（`today_new_users` 字段）
- **SPA 式切换**：`history.pushState` + `sessionStorage` 缓存用户列表，切换只需 1 次 fetch
- **Bug 修复**：
  - 热力日历列数：`cols = Math.ceil(days.length / 7)` 未考虑 firstDow
  - `daysToRender` TDZ：`const` 变量在声明前使用导致 `ReferenceError`，被 catch 吞掉显示为"网络异常"
  - D1 查询超时：users.js 子查询全表扫描导致超时，拆为 batch 并行
- **UI 精简**：卡片从 16 个精简为 8 个（2 组）；移动端卡片改为每行 2 个
- 涉及文件：`ifan-stats/user.html`、`ifan-stats/user.js`、`ifan-stats/index.html`、`ifan-stats/app.js`、`ifan-stats/styles.css`、`ifan-stats/functions/api/dashboard/user.js`、`ifan-stats/functions/api/dashboard/users.js`、`ifan-stats/functions/api/dashboard/summary.js`

## 2026-05-01

### 2026-05-01 — 统计后台暗色模式

- **暗色模式**：统计后台新增手动主题切换，顶栏 pill 按钮（🌙/☀），偏好存 `localStorage("ifan_theme")`
  - CSS：`[data-theme="dark"]` 变量覆盖 + 选择器覆盖（面板 `#1a1a1e`、卡片 `#242428`、文字 `#e8e6e1`、输入框 `#2a2a2e`）
  - 新增 4 个 Canvas CSS 变量：`--chart-bg`、`--chart-grid`、`--chart-axis`、`--chart-tick`
  - JS：`getChartColors()` 读取 CSS 变量同步 Canvas 绘图；饼图双色调色板 `PIE_PALETTE_LIGHT` / `PIE_PALETTE_DARK`
  - `drawXAxisLabels()`、`drawHover()`、`drawPie()` 新增 colors/palette 参数
  - 防闪烁：`<head>` 内联脚本，首屏前设置 `data-theme`
- **饼图对比度修复**：暗色模式下浅色切片文字从 `#e8e6e1` 改为 `#1a1a1e`，解决最大切片可读性问题
- **收工流程写入 CLAUDE.md**：新增「收工流程」章节，规定用户说收工时自动更新 PROJECT_TIMELINE / PROJECT_MEMORY / CLAUDE.md / CODE_AUDIT.md 等文档
- 涉及文件：`ifan-stats/index.html`、`ifan-stats/styles.css`、`ifan-stats/app.js`、`macfan-control-v2/CLAUDE.md`
- 已部署到 Cloudflare Pages（`ifan-stats`）

## 2026-04-28

## 2026-04-30

### 2026-04-30 — 心跳事件计数逻辑修复 + 历史数据重算

- **`heartbeat.js` 计数逻辑修复**：`daily:${day}:events` 原先按 15 分钟桶去重后累加（`uniqueBuckets`），语义混乱且有重复计数风险；改为遍历原始 `events` 数组，按天累加真实事件数
- **历史数据一次性迁移**：通过 `bucket_activity` 表按天聚合重算所有 `daily:*:events` 计数器，临时迁移脚本（`recalc-events.js`）已用完删除
- 两个项目均已部署（`ifan` + `ifan-stats`）

### 2026-04-30 — 统计后台趋势图改为累计曲线 + CLAUDE.md 创建

- **30 天趋势图改为累计增长曲线**：折线不再展示每日快照，改为累计下载量和累计去重用户数的增长趋势
  - 后端新增查询 `install:*` flags（用户首次出现时间），按日期分组得到每日新增用户数，附加到 daily 响应的 `new_unique` 字段
  - 前端将每日 `downloads` 和 `new_unique` 累加后再绘制折线
  - 浮窗（tooltip）同步改为显示"累计下载"和"累计用户"数值
  - Y 轴最大值以全部去重用户数为上限，与卡片数字对齐
  - 涉及文件：`ifan-stats/functions/api/dashboard/summary.js`（后端）、`ifan-stats/app.js`（前端）
- **CLAUDE.md 创建**：项目根目录新增 `CLAUDE.md`，Claude Code 每次新会话自动加载，内容为项目红线 + 操作地图，核心价值是防止 Claude 自作聪明
- **Claude Code hooks 配置**：在 `~/.claude/settings.json` 新增 Notification 和 Stop 两个 hook，分别播放 Glass/Ping 音效并弹出 macOS 通知

### 2026-04-30 — 用户编号系统 + 活跃趋势多维度筛选

- **用户编号系统（user_index 表）**：为每个 install_hash 分配递增短编号（#1、#2、#3...），持久化到 D1
  - 新增 `user_index` 表（id 自增 PK、install_hash UNIQUE、first_seen）
  - `docs/functions/api/heartbeat.js`：新安装时 INSERT OR IGNORE 写入 user_index；首次请求时从 `install:*` flags 批量回填存量用户
  - `ifan-stats/functions/api/dashboard/summary.js`：查询 user_index 全表，响应新增 `user_index` 字段
  - 存量回填：15 个用户全部按首次出现时间顺序分配编号（#1: 2026-04-26 ~ #15: 2026-04-29）
- **活跃趋势多维度筛选器**：活跃趋势图上方新增版本/用户编号筛选栏
  - `summary.js`：解析 `filter_version` 和 `filter_user_id` 参数，动态拼接 bucket_activity 和 version_breakdown 的 SQL WHERE 条件
  - `app.js`：`populateFilters()` 从 API 返回的 version_list 和 user_index 构建下拉选项；用户选项显示 `#N (首次: YYYY-MM-DD)`
  - `index.html`：panel-title 内新增 `.filter-bar`（版本下拉 + 用户下拉 + 清除筛选按钮）
  - `styles.css`：新增 `.filter-bar`（inline-flex + flex-wrap），`.panel-title` 加 flex-wrap 支撑三组子元素
  - 单用户模式 tooltip 显示「#N 活跃：是/否」替代「活跃用户：N」
  - 版本和用户筛选可叠加使用

## 2026-04-29

### 2026-04-29 — 统计后台前端 UI 优化

- **饼图深色切片文字可见性修复**：用 BT.601 亮度阈值（0.35）自动判断切片深浅，深色切片（#1c1c1c、#3e3329、#5d4b38）始终使用白色文字，hover 状态不再变黑导致不可见
- **用户反馈隐藏归档按钮**：标题栏新增 pill 按钮，点击可切换显示/隐藏已勾选的归档条目，状态存 localStorage `ifan_feedback_hide_archived`
- **30 天趋势图优化**：过滤掉全零天数，底部新增日期标签（最多 6 个均匀分布，格式 MM-DD）
- **30 天明细表优化**：隐藏全零行，日期由近至远排列（今天在最上面）
- 涉及文件：`ifan-stats/app.js`、`ifan-stats/index.html`、`ifan-stats/styles.css`

### 2026-04-29 — v2.9.5 / build 40 发布（关屏稳定性与控制状态可观测性）

- **关屏 / 无显示器场景稳定性提升**：围绕后台遥测、控制循环与安全兜底补强，降低关屏后风扇控制失效风险
- **安全策略分层化**：温度遥测缺失时优先进入 2200 RPM 保守兜底，只有在控制能力本身也不可靠时才交还系统
- **冷启动误报修复**：加入启动宽限期与连续失败门槛，避免应用刚启动就误判异常并弹窗
- **控制状态可观测性增强**：菜单中新增最近控制状态展示，亮屏后可回看是否处于正常控制、2200 RPM 兜底或已交还系统
- **风扇曲线默认值更新**：重置默认曲线改为当前预设 A
- **发布渠道同步**：GitHub Release、官网 ZIP、update-manifest.json、timeline.json 已同步到 build 40
- **公开文案口径修正**：心跳 / 后台统计相关改动对外统一归为“修复若干问题，提升整体稳定性”；其他用户可感知改动继续正常写明

### 2026-04-29 — build 40 心跳修复第一阶段 + 灰度发布

- **首次上线补发修复**：当前 build 未收到 heartbeat 成功确认时，后续 `tick()` 会持续补发，不再只赌启动时那一次发送
- **队列版本归属修复**：本地心跳事件开始携带自身 `version/build`，更新后旧积压事件不再被当前版本吞掉
- **反馈链路解耦**：反馈不再顺带携带或清空心跳队列，避免误删事件
- **灰度策略**：直接替换 build 40 的官网 ZIP 与 GitHub ZIP 资产，不增加新 build
- **公开文案策略**：
  - `update-manifest.json` 继续使用“修复若干问题，提升整体稳定性”
  - GitHub Release 与官网时间线对心跳相关改动保持泛化，但保留关屏稳定性、控制状态显示、启动误报修复等非心跳类具体说明

### 2026-04-28 — 统计后台版本分布面板重构

- **双面板并排布局**：版本分布拆为两个对称面板 — 左侧版本列表，右侧环形饼图
- **饼图交互**：鼠标悬停切片向外弹出 + 放大，对应图例高亮，其他切片淡出
- **响应式**：窄屏（≤860px）自动纵向堆叠
- **饼图设计**：暖灰色调，环形（donut）样式，中心显示总用户数，透明背景无边框，retina 高清渲染
- 版本排序改为新版在上

### 2026-04-28 — v2.9.5 / build 38 发布（SMAppService 登录项 + 更新校验修复）

- **开机自启动改用 SMAppService**：从 LaunchAgent plist 迁移到 `SMAppService.mainApp.register()` 原生 API
  - 在系统设置「登录项与扩展」中显示为 App 类型开关，不再是 hidden legacy agent
  - 首次启动自动清理旧的 `~/Library/LaunchAgents/com.ifancontrol.app.plist`
  - 卸载时调用 `SMAppService.mainApp.unregister()`
- **更新校验修复**：移除文件大小校验，仅保留 SHA256
  - Cloudflare CDN 传输 ZIP 时大小会变动 5 字节（6008350 → 6008345），但内容不变
  - 大小校验导致更新误报失败，用户被导向 GitHub Release
- **发布渠道同步**：GitHub Release ZIP、官网 manifest（build 38）、timeline.json 三者一致
- 版本号：v2.9.5 / build 38
- GitHub Release: https://github.com/PureMilkchun/iFanControl/releases/tag/v2.9.5

### 2026-04-28 — 代码审查 + 多项修复（build 37，已合并到 build 38）

- **全面代码审计**：对 Swift 前端和 Cloudflare Workers 后端进行系统性审查
- **修复 1：series_15m 历史桶数据丢失**（heartbeat.js / feedback.js）
  - 每日批量上报时，原代码只为当前时间桶更新 `series_15m`，历史桶的活跃用户数永远为零
  - 改为遍历 `uniqueBuckets` 逐个重算，确保所有桶的活跃用户数完整
- **修复 2：版本分布重复计数**（summary.js）
  - 原查询 `COUNT(DISTINCT install_hash) GROUP BY version` 导致升级用户在多个版本中都被计入
  - 改用 `ROW_NUMBER() OVER (PARTITION BY install_hash ORDER BY day DESC, bucket_index DESC)` 确保每个用户只计一次
- **修复 3：Process.waitUntilExit() 超时保护**（main.swift）
  - `kentsmc` 子进程调用均添加 8 秒 DispatchSemaphore 超时，超时后 `terminate()` 防止永久阻塞硬件监控
  - 涉及 `BackgroundHardwareReader.executeRead`、`FanManager.executeReadCommand`、`CommandExecutor.executeCommand`
- **修复 4：lastSetRPM 初始化为 0**（main.swift）
  - 应用启动时 `lastSetRPM` 从 0 起步，导致风扇可能先骤降到最低再爬升到目标值
  - 改为硬件探测完成后从实际 RPM 读取初始值：`if let initialRPM = cachedFanRPMs.values.max(), initialRPM > 0 { lastSetRPM = initialRPM }`
- **修复 5：菜单栏图标随机消失**（main.swift）
  - macOS SystemUIServer 崩溃后 NSStatusItem 失效，进程仍在但图标消失
  - 新增 `createStatusItem()` 方法和 `handleScreenOrDisplayChange()` handler
  - 监听 `NSApplication.didChangeScreenParametersNotification` 自动恢复
  - 2 秒轮询中增加 `statusItem.button?.window == nil` 健康检查兜底
- **审查经验**：见 `CODE_AUDIT.md`（本次审查中的误判与教训）
- **当前状态**：build 37 在 `/Applications` 本地运行测试中（版本号未升，仍为 2.9.5）

### 2026-04-28 — v2.9.5 / build 35 发布（含热修复，ZIP 已覆盖）

- **告诉开发者**：菜单栏新增反馈入口（灰色斜体输入框样式），点击弹出反馈窗口
  - 支持多行内容 + 邮箱（选填），发送后提示"收到！我会尽快回复你"
  - 客户端限流：每小时最多 5 条，服务端同样限流
  - 发送反馈时顺便带上积压的心跳事件，一次请求干两件事
- **心跳上报改为每日上报**：从每小时批量上报改为每天上报昨天的事件，请求量减少 96%
  - 离线缓存从 24h 扩展到 48h（192 条事件）
  - `lastFlushDate` 存 UserDefaults，发送成功才标记，失败 tick 会重试
  - flush 只取昨天的事件，今天的始终保留
- **服务端**：feedback.js 处理反馈 + 心跳事件，heartbeat.js 完全不动（兼容老版本）
- **热修复（覆盖 build 35 ZIP，未升版本号）**：
  - install.sh 增加旧备份清理：更新前自动删除 `iFanControl.app.backup-*` 和 `iFanControl.app.malformed-*`
  - 反馈携带心跳 bug 修复：`dequeueYesterdayEvents()` 改为 `dequeueAllPendingEvents()`，新用户首天反馈也能带上心跳
  - 首次启动立即上报：`startup()` 入队今天事件后调用 `flushAll()` 发送所有积压，不再等到第二天
  - 反馈失败时 `requeueEvents()` 把事件放回队列，不丢数据
- **统计后台（ifan-stats）**：
  - 用户反馈板块移到第三个位置（当前版本分布之后、用户活跃趋势之前）
  - 反馈记录增加勾选框：勾选后变灰+删除线，移到列表末尾；取消勾选恢复原位
  - 勾选状态存 localStorage，刷新不丢
- **公开文案规范**：心跳上报相关改动对外一律称为"Bug 修复与性能优化"，不暴露实现细节
- GitHub Release: https://github.com/PureMilkchun/iFanControl/releases/tag/v2.9.5
- 官网已部署: https://ifan-59w.pages.dev

## 2026-04-27

### 2026-04-27 — 官网新增「项目时间线」板块

- 在官网 iteration-section（开发者也是用户）和 showcase-section（界面展示）之间新增时间线板块
- 数据文件：`docs/timeline.json`，JS 通过 fetch 加载，失败时静默不显示
- 默认展示最近 1 天的条目，点击「展开完整时间线」可查看全部（目前 5 天共 17 条）
- 文案采用 GitHub Release Notes 风格，不暴露内部实现细节
- CSS 文件名改为 `styles.20260427a.css`（从 `20260424a` 改名），解决 Cloudflare CDN 缓存问题
- 新建 `docs/DEPLOY.md` 部署规范文档，记录发版流程、timeline.json 维护方法、CSS 缓存策略
- 部署规范：以后每次发版只需更新 timeline.json + manifest + ZIP，HTML/CSS 不动
- 时间线中去掉了所有统计后台相关条目，只保留 App 本身的更新
- 初始数据从 PROJECT_TIMELINE.md 提取，覆盖 v2.8.21 ~ v2.9.4

### 2026-04-27 — v2.9.4 / build 34 发布

- **风扇曲线编辑器优化**：拖拽控制点时右下角实时显示当前温度和转速（`drawEditingInfo()` 方法，灰色小字，与坐标轴风格一致）
- **心跳上报重构**：从旧版"每 15 分钟发一条 HTTP"升级为批量架构
  - 本地事件队列 + `heartbeat_queue.json` 文件持久化
  - 15 分钟入队 + 每小时批量上报
  - 启动 flush 缓存 + 退出 flush（同步发送，Semaphore 等待）
  - `events` 数组格式 payload，与服务端匹配
  - 并发安全：关键状态变量加 NSLock 保护
- **修复 Timer 双注册 bug**：移除了重复的 `RunLoop.main.add(timer, forMode: .common)`
- 发现旧版 PrivacyStatsService 实际从未升级过（服务端已改造，App 端遗漏）
- install_id 仍发送原始 UUID（SHA-256 由服务端做，改动需服务端配合，当前 HTTPS 保护足够）
- GitHub Release: https://github.com/PureMilkchun/iFanControl/releases/tag/v2.9.4
- 官网已部署: https://ifan-59w.pages.dev

### 2026-04-27 — 统计后台版本分布去重修复

- `version_breakdown` 原从 `counters` 表加总每日计数，同一用户跨天重复计数
- 改为从 `bucket_activity` 表 `COUNT(DISTINCT install_hash)` 跨整个时间段去重
- 标签从"版本分布（近 30 天累计）"改为"当前版本分布"
- 涉及文件：`ifan-stats/functions/api/dashboard/summary.js`（后端查询）、`ifan-stats/index.html`（标签文案）
- 确认隐私设计有效：7 位用户各有唯一 UUID，服务端仅存 SHA-256 哈希，无法反推原始 ID

### 2026-04-27 — v2.9.3 ZIP 包内容修复 + config.json 教训

- 第一次打包只含 iFanControl.app + install.sh，缺少 kentsmc、diagnose、uninstall、LICENSE、README 等
- 参照 `iFanControl-2.8.27/` 目录补全了所有文件
- 打包过程中意外删除了项目根目录的 `iFanControl.app/`，已从 `.build/release/` 重建
- **config.json 教训**：第一次打包的 app bundle 误带了旧 config.json，用户安装后应用读到错误配置，误判为"无风扇"。卸载后从官网重新安装（无 bundled config.json）恢复正常
- **结论**：ZIP 包的 app bundle 里绝不能包含 config.json，应用应在首次运行时自动生成
- 教训写入 PROJECT_MEMORY.md 的"ZIP 打包规范"和"config.json 教训"

### 2026-04-27 — v2.9.3 / build 33 风扇曲线预设系统（第三次尝试，成功发布）

- 采用纯 AppKit 架构（NSStackView + NSButton），彻底避免 addSubview 不可见问题
- 3 个预设 Tab 按钮横排在底部，左侧预设 + 右侧重置/关闭
- 双击预设名称弹出 NSAlert 重命名
- 切换预设立即通过 FanCurveDidSwitch 通知应用曲线
- 控温循环改为从 MenuBarManager.currentFanCurve 读取内存曲线（不再轮询 config.json）
- 窗口关闭自动静默保存（windowWillClose 通知）
- 移除保存按钮和保存成功弹窗
- 重置按钮恢复所有预设到官方默认曲线（预设 A）
- 官方默认曲线 `defaultFanCurve(maxRPM:)` 作为首次启动和重置的基准
- 底部提示："双击预设名称可重命名 · 关闭窗口自动保存"
- GitHub Release: https://github.com/PureMilkchun/iFanControl/releases/tag/v2.9.3
- 官网已部署: https://ifan-59w.pages.dev

### 2026-04-27 — v33 风扇曲线预设系统（两次尝试均失败，已回滚）

#### 第一次尝试（早些时候）
- 目标：3 个预设 Tab 切换，一键在安静/均衡/性能场景间切换
- 编译通过，二进制已替换
- 运行时 UI 未显示，`showFanCurveEditor()` 从未被调用
- 已回滚

#### 第二次尝试（晚间）
- 采用分阶段增量策略：
  - 阶段 1：Config 数据层 + NSLog 调试日志 → 编译通过，NSLog 确认 showFanCurveEditor 被调用
  - 阶段 2：预设 Tab UI → 编译通过，但 UI 不显示
- 尝试了多种 UI 方案均不显示：
  - NSSegmentedControl
  - NSStackView + NSButton (recessed)
  - 自定义 PresetTabButton (NSView 子类)
  - 替换 contentView 为新 NSView
- 原始 UI（FanCurveView + 按钮）始终正常，但任何新增 addSubview 都不可见
- clean build、codesign 重签均无效
- 已完全回滚到 build 32

#### 关键发现
- `setupUI()` 确实被调用（日志证实）
- 菜单 action 正常连接（`sendAction:` 日志出现）
- 二进制 MD5 验证一致（替换成功）
- 但新增的子视图在运行时不可见，原因未明
- 可能与 `@MainActor` 隔离、AppKit 内部缓存、或 window.contentView 生命周期有关

#### 下次实现建议
1. 不修改现有 FanCurveWindowController，创建全新的 NSWindowController 子类
2. 或用 SwiftUI 替代 AppKit 实现预设 UI
3. 或在 FanCurveView 内部直接绘制预设 Tab（避免 addSubview 问题）
4. 先做最小可行测试：在 setupUI 中添加一个最简单的 NSView，确认能显示后再逐步构建

## 2026-04-26

### 2026-04-26 晚间 — 登录故障排查与统计后台大改

#### 登录故障排查（3 个根因）
1. **`_worker.bundle` 覆盖 functions/ 目录**：
   - `ifan-stats/` 中残留的 `_worker.bundle` 带有旧 KV 路由表
   - Cloudflare Pages 优先使用该 bundle，导致所有 API 请求走旧代码
   - 修复：删除 `_worker.bundle`，重新部署
2. **`drawTrendTooltip` 重复声明**：
   - `app.js` 中存在两个同名函数声明，导致 SyntaxError
   - 整个 JS 无法执行（包括登录表单的事件绑定），页面闪烁后输入清空
   - 修复：删除重复的函数声明
3. **Cloudflare WAF 自定义域名拦截**：
   - `stats.puremilkchun.top` 被 Cloudflare managed challenge 拦截，返回 403
   - `pages.dev` 地址可正常访问
   - 用户已设置 WAF 例外规则，但未完全解决
   - 当前状态：使用 `ifan-stats.pages.dev` 访问

#### 会话有效期延长
- `SESSION_TTL_SECONDS` 从 12 小时改为 365 天
- 登录 cookie `Max-Age` 同步改为 365 天
- 用户需求："只要登录，就不需要重新登录了"

#### 趋势图 hover 版本分布
- 为近 30 天趋势图添加鼠标事件监听（mousemove / mouseleave）
- hover 浮窗显示每日各版本的去重用户数
- 版本数量右对齐

#### 活跃度图每桶版本分布（重大改动）
- **数据库**：`bucket_activity` 表新增 `version TEXT` 列
- **心跳端点**：`INSERT INTO bucket_activity` 增加 `version` 字段（格式 `2.9.1-32`）
- **老数据回填**：从 `flags` 表的 `version:{day}:{versionBuild}:{installHash}` 模式提取版本信息，回填 32 行
- **后端查询**：改为单源查询 `GROUP BY bucket_index, version`，同时计算活跃用户数和版本分布
- **前端改动**：移除 `dailyVersionsMap`，改从 `point.versions` 读取每个桶的版本分布
- **active_users 一致性修复**：hover 中的活跃人数 = 各版本人数之和（均来自同一查询）

#### 版本数量右对齐
- `drawCanvasTooltip` 和 `drawTrendTooltip` 中，版本行改为版本号左对齐、数量右对齐
- 宽度计算拆分为 `verWidth + gap + cntWidth`

### 2026-04-26 15:00 左右
- 诊断并修复统计后台数据为 0 的问题：
  - 根因：`docs/` 目录中残留的 `_worker.bundle` 带有 `/functions/` 前缀路由表
  - Cloudflare Pages 优先使用该 bundle，导致所有 API 请求路径不匹配，返回 HTML（405 或 200）
  - 心跳上报 `/api/heartbeat` 实际命中了 `/functions/api/heartbeat`，被 Pages 当作静态文件处理
- 修复动作：
  - 删除 `docs/_worker.bundle`
  - 用 `wrangler pages functions build --outdir /tmp/ifan-build` 从 `functions/` 目录构建正确的 `_worker.js`
  - 部署时必须带 `--no-bundle --skip-caching`，否则 wrangler 会尝试重新打包或检测不到文件变化
- 修复后验证：
  - `/api/heartbeat` 返回 `{"ok":true}`
  - `/api/stats` 返回正确 JSON 数据
  - `/download` 正确 302 到 ZIP 并累计下载计数
  - 心跳数据开始正常写入 KV

### 2026-04-26 16:00 左右
- 新增"下载活跃趋势"15 分钟粒度折线图，涉及 4 个文件：
  - `docs/functions/download.js`：新增 `updateDownloadSeries15m()` 函数，写入 `download:series15m:{day}`（96 槽位 JSON 数组，TTL 7 天）
  - `ifan-stats/functions/api/dashboard/summary.js`：新增 `readDownloadSeries15m()` 读取下载 15 分钟序列，响应新增 `downloads_15m` 字段
  - `ifan-stats/index.html`：新增"下载活跃趋势"面板（`<canvas id="downloadChart">`）
  - `ifan-stats/app.js`：新增 `getDownloadChartModel()`、`renderDownloadChart()`、`drawDownloadCanvasTooltip()`，蓝色折线，支持 hover tooltip
- 前端 `drawHover()` 改为支持可选 `color` 参数，活跃用户用橙色 `#f97316`，下载用蓝色 `#2563eb`
- 两个项目均已部署验证通过

### 2026-04-26 16:30 左右
- 将本次调试与开发经验写入 `PROJECT_MEMORY.md`：
  - 新增"Cloudflare Pages Functions 部署纪律"章节，记录正确部署流程、禁止事项和原因
  - 新增"5b. 统计后台（ifan-stats）"章节，记录项目位置、线上地址、架构、部署命令和功能列表

### 2026-04-26 晚间 — 内存优化 + 预设尝试 + 菜单响应优化

#### 第一阶段：内存优化
- 分析发现 `updateMenu()` 每 2 秒重建整个 NSMenu 是内存飙升根因（~90MB）
- 实现 `buildMenuOnce()` + `updateDynamicMenuItems()` 模式：菜单结构只建一次，后续仅原地更新 title/state
- 删除 `temperatureHistory` 死代码（仅写入从未读取）
- 优化后内存稳定在 ~39MB，用户确认
- **发布 v2.9.0 / build 30**

#### 第二阶段：风扇曲线预设系统尝试（已回滚）
- 完成方案设计：3 个 Tab 按钮、双击重命名、config.json 存储 `curvePresets`
- 代码实现并编译通过，但运行时 UI 未显示（原因未明）
- 用户决定回滚，保留方案规划到 `project_fan_curve_presets_plan.md`
- 回滚事故：`git checkout` 连带回滚了未提交的内存优化，已重新应用

#### 第三阶段：菜单响应性能优化
- 用户反馈菜单点击有延迟（优化前就存在）
- 根因分析：
  1. `ConfigManager.loadConfig()` 每 2 秒从磁盘读取 + 解析 JSON
  2. `refreshTelemetry()` 在主线程逐个调用 `kentsmc` 子进程（每个传感器一个 Process），阻塞主线程
  3. `startAutoControlLoop()` 也有独立的 2 秒定时器，同样在主线程做硬件 I/O
- 解决方案：
  1. **Config 缓存**：`loadConfig()` 增加 mtime 检查，文件未变化时返回缓存，避免磁盘 I/O
  2. **BackgroundHardwareReader**：独立的非 MainActor 类，在后台 DispatchQueue 上执行硬件读取，通过 NSLock 保护缓存
  3. **菜单定时器改造**：定时器 dispatch 硬件读取到后台，`updateDynamicMenuItems()` 只从后台缓存读取
  4. **自动控温循环改造**：`startAutoControlLoop()` 改为从 BackgroundHardwareReader 缓存读取温度，不再触发主线程硬件 I/O
- 效果：菜单点击从"有延迟"变为"即时弹出"
- **发布 v2.9.1 / build 31**

#### 附：Cloudflare KV 用量预警
- 收到 Cloudflare 邮件：Workers KV 免费层已达 50%
- 免费层限制：每天 1,000 次写入；当前约 5 个日活用户（每人每天 96 次心跳写入）
- 结论：暂不需要升级，但用户继续增长时需注意（$5/月付费计划可支撑 ~10,000 日活）

### 2026-04-26 深夜 — KV 迁移 D1 + 批量心跳系统

#### 背景
- KV 免费层 1,000 次写入/天，5 个日活用户已接近 50%
- D1 免费层提供 100,000 行写入/天 + 1,000 次查询/天
- 决定将统计后端从 KV 迁移到 D1，并重新设计心跳上报机制

#### D1 迁移
- 创建 D1 数据库 `ifan-stats-db`（database_id: `383dadba-cf12-47f1-bf53-dbf2f087458f`）
- 新建 `wrangler.toml` 配置 D1 绑定（docs + ifan-stats 两个项目）
- 重写 `docs/functions/api/heartbeat.js`：KV → D1，支持批量事件格式
- 重写 `docs/functions/download.js`：KV → D1
- 重写 `docs/functions/api/stats.js`：KV → D1
- 重写 `ifan-stats/functions/api/dashboard/summary.js`：KV → D1
- 重写 `ifan-stats/functions/api/_lib/auth.js`：KV → D1（登录限流）
- D1 表结构：`counters`、`flags`（替代旧 `seen`）、`bucket_activity`、`series_15m`
- 删除 `docs/_worker.js`（旧打包文件会覆盖 functions/ 目录），保留 `.bak`

#### 批量心跳系统
- 问题：即使迁移到 D1，每个用户每天仍产生 ~96 次查询（每 15 分钟 1 次心跳 × 每次 ~4 条 SQL）
- 解决方案：App 端本地缓存心跳事件，每小时批量上报
- App 端改动（`PrivacyStatsService`）：
  - 每 15 分钟记录一条带时间戳的事件到本地队列
  - 每小时通过 `POST /api/heartbeat` 批量上报所有缓存事件
  - 离线事件缓存在 `~/Library/Application Support/iFanControl/heartbeat_queue.json`
  - 启动时先 flush 缓存事件，再记录新心跳
  - 退出时 flush 所有待上报事件
- 服务器端改动（`heartbeat.js`）：
  - 接收 `{install_id, version, build, events: [{ts, type}, ...]}` 格式
  - 按 (day, bucket_index) 去重，批量写入 D1
  - 从 `bucket_activity` 重新聚合 `series_15m` 活跃用户数
- 查询量估算：~5 次查询/批 × 每天 24 批/用户 × 5 用户 ≈ 600 次/天（远低于 1,000 免费上限）

#### 前端改动
- `ifan-stats/index.html`：卡片区"最近刷新"下方注明"每小时更新"

#### 部署验证
- 两个项目均部署到 Cloudflare Pages
- 本地测试通过（heartbeat、stats、download 三个接口）
- 远程测试通过

## 2026-04-24

### 2026-04-24 00:00 左右
- 明确采用“双记忆”结构：
  - 固定记忆：`PROJECT_MEMORY.md`
  - 时间戳记忆：`PROJECT_TIMELINE.md`

### 2026-04-24 00:00 左右
- 确认当前真正开发目录是：
  - `/Users/puremilk/Documents/mac fancontrol/macfan-control-v2`
  - `/Users/puremilk/Documents/mac fancontrol/distribution-a`
- 明确 `/Users/puremilk/Downloads/iFanControl-2.8` 只是下载/测试目录，不应继续作为主上下文

### 2026-04-24 00:10 左右
- 继续推进安装体验 A 方案
- 在 `/Users/puremilk/Documents/mac fancontrol/distribution-a` 中建立隔离实验线
- 主工程与官网发布链保持不动

### 2026-04-24 00:15 左右
- 实验线完成：
  - `DMG + Install.command + 首次启动引导页`
  - App 内“诊断与支持”入口补入修复/卸载相关动作

### 2026-04-24 00:20 左右
- 修复实验 DMG 打包脚本误把 `dSYM` 当成主二进制的问题
- 重新生成可正常启动的实验版 App 和 DMG

### 2026-04-24 00:25 左右
- 验证实验 DMG 可正常安装
- 用户确认新的 DMG 安装体验基本可用

### 2026-04-24 00:30 左右
- 收到反馈：`/Applications` 中出现大量 `iFanControl.app.backup-*` 和 `iFanControl.app.malformed-*`
- 定位为历史测试/替换过程中留下的备份残留
- 已全部清理

### 2026-04-24 00:35 左右
- 完成卸载闭环第一阶段：
  - DMG 顶层新增 `Uninstall.command`
  - 新增完整卸载脚本，支持删除：
    - `iFanControl.app`
    - `kentsmc`
    - `sudoers`
    - 配置
    - 日志
    - LaunchAgent

### 2026-04-24 00:40 左右
- 将实验 DMG 外部说明文件命名调整为：
  - `README｜安装指南.txt`
- 原因：
  - macOS 文件名不能直接使用 `/`
  - 使用 `｜` 保留接近“README / 安装指南”的显示语义

### 2026-04-24 00:45 左右
- 完成 App 内完整卸载主入口：
  - 在 `关于/帮助 -> 诊断与支持` 中点 `完整卸载`
  - App 先确认
  - 自动生成一次性临时卸载脚本
  - App 退出后由脚本继续删除 App 和所有残留
- 这意味着卸载不再依赖用户保留 DMG

### 2026-04-24 00:50 左右
- 确定当前分发策略建议：
  - 首次安装：DMG
  - 自动更新：ZIP
- 即：
  - 官网手动下载未来可切到 DMG
  - App 内自动更新暂不改，继续保留 ZIP

### 2026-04-24 01:00 左右
- 将记忆文件正式迁入 `macfan-control-v2`
- 固定记忆改为：
  - `/Users/puremilk/Documents/mac fancontrol/macfan-control-v2/PROJECT_MEMORY.md`
- 时间戳记忆改为：
  - `/Users/puremilk/Documents/mac fancontrol/macfan-control-v2/PROJECT_TIMELINE.md`

### 2026-04-24 01:30 左右
- 官网下载策略正式切换完成：
  - 主下载按钮改为 `./iFanControl-macOS.dmg`
  - 页脚下载入口改为 `./iFanControl-macOS.dmg`
  - 中英文页脚文案改为“下载 DMG / Download DMG”
- `docs` 目录新增固定文件名 DMG：
  - `/Users/puremilk/Documents/mac fancontrol/docs/iFanControl-macOS.dmg`
- 官网已完成发布，发布预览地址：
  - `https://b23c2448.ifan-59w.pages.dev`

### 2026-04-24 01:35 左右
- GitHub Release `v2.8.21` 已确认包含双资产：
  - `iFanControl-macOS.dmg`（官网手动下载安装）
  - `iFanControl-macOS.zip`（应用内自动更新）
- `update-manifest.json` 保持 ZIP 更新链路不变（`macos_arm64_zip_url` 仍指向 ZIP）

### 2026-04-24 01:40 左右
- 修复 GitHub Actions 长期构建告警：
  - 原因 1：仓库无 `Tests/` 时 `swift test` 直接失败
  - 原因 2：`Package.swift` 使用 `swift-tools-version: 6.2`，而 GitHub Runner 为 6.1
- 处理动作：
  - workflow 调整为“仅在存在测试文件时运行 `swift test`”
  - `Package.swift` tools version 下调为 `6.1`
  - `actions/checkout` 升级到 `v5`，消除 Node20 弃用警告
- 结果：
  - 最新 CI 连续通过，`Swift` workflow 已恢复绿色

### 2026-04-24 01:50 左右
- 为验证更新链路，创建 `2.8.22` 测试更新：
  - 基于 `2.8.21` 复制出测试 ZIP
  - 将 `update-manifest.json` 提升到 `2.8.22 / build 22`
  - 发布到 Pages，并创建 GitHub `v2.8.22` Release

### 2026-04-24 02:00 左右
- 收到反馈：App 内“完整卸载”入口消失
- 根因定位：
  - 完整卸载实现停留在 `distribution-a/prototype-app` 实验线
  - 正式更新 ZIP 仍使用主线旧包，未包含该功能
- 处理动作：
  - 将完整卸载能力正式并回 `macfan-control-v2` 主线
  - 在 `关于/帮助 -> 诊断与支持` 恢复 `完整卸载 / Full Uninstall`
  - 保留一次性临时卸载脚本流程（退出后继续清理）

### 2026-04-24 02:05 左右
- 重新打包并发布 `2.8.22` 正式更新 ZIP（包含完整卸载恢复）
- 同步更新：
  - `docs/iFanControl-macOS.zip`
  - `docs/update-manifest.json`（新 hash/size）
  - GitHub `v2.8.22` Release 资产
- 主仓库代码已推送并通过 CI

### 2026-04-24 02:15 左右
- 新发现：网络下载场景下，DMG 中双击 `.command` 依旧容易被 Gatekeeper 持续拦截
- 决策变更：
  - 放弃 DMG 作为正式安装主链路
  - 回退为“拖拽 `install.sh` 到终端执行”的 ZIP 安装模式
- 同步动作：
  - 安装指南 HTML 回退并修正文案（明确不要双击 `Install.command`）
  - README 中英文同步改为拖拽安装推荐
  - 更新器逻辑改为优先 `install.sh`，避免 command-first 行为

### 2026-04-24 02:20 左右
- 虽然重打了可包含 `.sh` 的 DMG 并验证成功，但最终仍确认正式策略为 ZIP-only
- 官网最终发布状态：
  - 官网下载按钮：`ZIP`
  - 应用内更新：`ZIP`
  - `update-manifest.json` 说明已更新为“全链路 ZIP”
- 最终结论：
  - **首装走 ZIP**
  - **更新走 ZIP**

### 2026-04-24 13:15 左右
- 准备发布 `2.8.23 / build 23`：
  - 修复关于/帮助窗口在系统深浅色切换后卡片不换色的问题
  - 支持作者二维码改为随深浅色重新生成（亮色黑码白底，暗色白码深底）
  - 手动转速弹窗新增“实际 RPM 不一定完全等于设定值”的解释入口
  - App 内完整卸载补齐旧配置目录 `~/Library/Application Support/iFanControl` 清理
- 官网与自动更新继续保持 ZIP-only：
  - `docs/iFanControl-macOS.zip`
  - `docs/iFanControl-macOS-2.8.23.zip`
  - `docs/update-manifest.json` 升到 `2.8.23 / build 23`
- 官网发布目录中移除残留 `iFanControl-macOS.dmg`，避免公开 DMG 入口继续误导用户。

### 2026-04-24 13:35 左右
- 发现自动检查更新机制存在节流问题：
  - 旧逻辑会在请求 manifest 前用 `last_check` 做 24 小时拦截
  - 如果用户在新版本发布前刚检查过，发布后自动检查会直接返回，不会联网，也不会弹窗
- 修复策略：
  - 自动检查开启时，启动后始终请求一次 manifest
  - `last_check` 只保留为记录信息，不再阻止发现新版本
- 准备发布 `2.8.24 / build 24`，专门修复自动检查更新不弹窗问题。

### 2026-04-24 14:40 左右
- 新增“隐私优先统计”全链路（不改变 ZIP 更新契约）：
  - 官网新增 `Pages Functions`：
    - `GET /download`：302 到 `iFanControl-macOS.zip`，并写入聚合下载计数
    - `POST /api/heartbeat`：写入匿名活跃计数（仅随机安装 ID 的哈希、version、build）
    - `GET /api/stats`：统计读取接口，已加 `Bearer` token 鉴权
  - Cloudflare Pages 项目 `ifan` 已绑定 KV 命名空间 `IFAN_STATS`
  - 线上已验证：
    - `/download` 返回 302 且可累计 `download:total`
    - `/api/heartbeat` 返回 `{"ok":true}` 且可累计活跃计数
    - `/api/stats` 未带 token 返回 401，带 token 可读统计
- App 端同步改动：
  - 新增 `PrivacyStatsService`，应用启动后延迟上报每日一次匿名心跳
  - `关于/帮助 -> 简介` 新增“共享匿名活跃统计”开关及说明文案
- 发布产物升级到 `2.8.25 / build 25`：
  - `docs/update-manifest.json` 升到 `2.8.25 / 25`
  - `docs/iFanControl-macOS.zip` 已替换为 `2.8.25`，sha256 为 `553f9861894e65394fcaf911799d201412c927d5d56f798c8d248e169b22805c`
  - 官网页面下载入口改为 `./download`，构建标记更新为 `build 20260424b`

## 2026-04-25

### 2026-04-25 22:00 左右
- 对 `main.swift` 和 `SensorCatalog.swift` 进行了代码质量审查，识别出多个内存优化机会：
  - Config 每 2 秒从磁盘重新读取（应缓存）
  - 温度读数每 2 秒重复构建（应缓存）
  - NSMenu 每 2 秒完整重建（应原地更新）
  - `temperatureHistory` 死代码
  - HelpWindow 视图未在关闭时释放
  - `category`/`sortKey` 计算属性应缓存
  - `ISO8601DateFormatter` 应 lazy 初始化
  - 心跳 Timer 双重注册
- 完成了内存优化的代码实现并编译通过
- 后因用户要求回滚，所有内存优化改动已 `git restore`，暂不发布

### 2026-04-25 23:00 左右
- 实现多语言切换功能：
  - 将三个模块的 `private let` 布尔语言判断替换为从 `UserDefaults` 读取的 `currentLanguage`
  - 涉及文件：`main.swift`、`SensorCatalog.swift`、`FanCurveWindow.swift`
  - 菜单新增"语言 / Language"子菜单（位于"关于/帮助..."之后）
  - 首次安装弹出语言选择弹窗（中文 / English）
  - 切换后提示重启生效，可选"立即重启"或"稍后"
- 版本号升级到 `2.8.28 / build 28`
- 完成全链路发布：
  - 官网 ZIP 替换（`docs/iFanControl-macOS.zip` + `docs/iFanControl-macOS-2.8.28.zip`）
  - `update-manifest.json` 升到 `2.8.28 / 28`
  - Cloudflare Pages 部署完成
  - GitHub 代码推送（commit `52c014c`）
  - GitHub Release `v2.8.28` 创建：
    - `https://github.com/PureMilkchun/iFanControl/releases/tag/v2.8.28`
- 新包校验值：
  - `sha256 = 7b743bd8209686b6cfe732118b2d67b8e2717b8ea01d431f449915173abae1ad`
  - `size = 5971567`

### 2026-04-25 23:30 左右
- 处理 PR #2（`lop1381997:codex/english-translation`，"add bilingual UI switcher"）：
  - 该 PR 提出了 `LocalizationManager` 单例 + 即时切换方案（+351 行）
  - 我们的 v2.8.28 已用更简单的方式覆盖核心需求（+66 行，重启生效）
  - 已用得体英文回复作者并关闭 PR

### 2026-04-25 14:10 左右
- 统计后台 `stats` 继续迭代：
  - 初步加入 12 小时活跃趋势图与时间范围切换
  - 后续澄清需求后，改为“默认近 12 小时、15 分钟粒度”的真实活跃曲线
- 底层数据口径统一为：
  - 使用官网心跳写入的 `15 分钟聚合活跃值`
  - 最近 `30 天` 的 15 分钟点位长期保留
  - 统计后台再按所需范围读取并绘制

### 2026-04-25 14:20 左右
- 官网发布了 `2.8.26 / build 26`：
  - `docs/update-manifest.json` 升到 `2.8.26 / 26`
  - 官网 ZIP 与应用内更新 ZIP 保持一致
- 随后确认：
  - GitHub Release 侧当时还停留在 `v2.8.25`
  - 需要单独补发 `v2.8.26` Release

### 2026-04-25 14:30 左右
- 补发 GitHub `v2.8.26` Release：
  - 上传 `iFanControl-macOS-2.8.26.zip`
  - 在 Release 说明中明确写入：
    - 适配已覆盖 `M5`
    - 已在真实 `MacBook Pro M5` 上完成运行验证

### 2026-04-25 14:40 左右
- 对匿名统计设置项做产品体验修正：
  - 设置项名称统一改为 `匿名统计用户量`
  - 在开关右侧新增 `?` 说明按钮
  - 帮助文案改为更直白解释：
    - 只统计有多少人在使用 iFanControl
    - 仅上报随机安装 ID、版本号、build
    - 不上传姓名、邮箱、序列号、设备名称
  - 用户尝试关闭时，新增一次带幽默感的确认弹窗
  - 若用户坚持关闭，仍然允许关闭
- 对应代码已推送到 GitHub：
  - commit `38a0f48`

### 2026-04-25 14:50 左右
- 修正了一个发布流程认知问题：
  - 仅推 GitHub 代码并不能让用户收到 App 行为更新
  - 如果变更要让用户真正拿到，必须同步：
    - 新 ZIP 包
    - 官网当前 ZIP
    - `update-manifest.json`
    - GitHub Release

### 2026-04-25 14:55 左右
- 重新打包并发布 `2.8.27 / build 27`，用于承载“匿名统计说明 + 关闭确认弹窗”这次真实用户可见改动：
  - `Info.plist` 升到 `2.8.27 / 27`
  - `install.sh` 标题同步升到 `2.8.27`
  - 安装脚本兼容设备文案更新为 `(M1/M2/M3/M4/M5)`
- 新 ZIP 产物：
  - `docs/iFanControl-macOS-2.8.27.zip`
  - `docs/iFanControl-macOS.zip`
- 新包校验值：
  - `sha256 = 811cc495bc2b03130d2d22b5395ed1267640a4b383aec5cabc56e39649352450`
  - `size = 5972647`

### 2026-04-25 15:00 左右
- 官网与应用内更新链路同步到 `2.8.27`：
  - `docs/update-manifest.json` 升到 `2.8.27 / 27`
  - `notes` 更新为匿名统计说明与关闭确认弹窗相关内容
  - `https://ifan-59w.pages.dev/update-manifest.json` 线上已验证为 `2.8.27`
- GitHub Release 同步到 `v2.8.27`：
  - Release 地址：`https://github.com/PureMilkchun/iFanControl/releases/tag/v2.8.27`
  - 资产：`iFanControl-macOS-2.8.27.zip`
- 主仓库代码同步：
  - commit `f1e5ff9`
- 结论：
  - 官网 ZIP、应用内更新 ZIP、GitHub Release 三者已重新对齐
  - `2.8.27` 才是这次匿名统计交互改动真正对用户可达的版本

## 2026-04-23

### 2026-04-23
- 正式稳定版本已到 `2.8.21`
- 修复了更新包缺少 `install.sh` 导致更新失败的问题
- 线上 update manifest 与 GitHub Release 已同步到 `2.8.21`

### 2026-04-23
- 帮助页经历多轮重构：
  - 关于/帮助侧边栏
  - 诊断与支持
  - 常见问题
  - 支持作者
- 版本一路迭代到 `2.8.21` 前后

### 2026-04-23
- 对主目录做过一次明显旧物清理：
  - 删除旧工程目录
  - 删除旧 DMG/ZIP
  - 删除测试脚本
  - 保留主工程、官网、交接文档与部分辅助目录
