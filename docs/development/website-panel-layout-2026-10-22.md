# 首页右侧文字重排 · 本地审核版

范围仅为首屏右侧产品介绍、语言切换、功能、下载及兼容性说明。沿用静态 HTML、原生 JavaScript、现有 CSS、Avenir Next / Baskerville 和暖纸色。项目约定参考 `CLAUDE.md`、父目录 `docs/WORKSPACE_GOVERNANCE.md`；没有适用的 AGENTS.md。左侧视觉、后续网页和更新分发不在本次范围。

## Scope and coverage

| Domain | Evidence inspected | Result |
| --- | --- | --- |
| Accessibility | index.html:57 原生链接、按钮及 details；Tab / Return、AX 名称、可见焦点；320px 与文字放大 | 已查范围 Clear；完整 VoiceOver 未验证 |
| Layout | styles.20261022b.css:2172；中英桌面、窄屏、RTL 结构 | 下表两项已修复 |
| Writing | index.html:69 及双语字典；能力说明、下载、兼容性回退 | Clear；保留未实测设备提示 |
| Typography | CSS:2244 起；实际字号、行高、英文换行 | Clear；说明按功能标题下方排列 |
| Colors | panel 局部语义色；渲染后的前景/背景对比度 | Clear；辅助正文 5.452:1、主按钮 17.179:1 |
| UI | CTA、语言控件、focus、原生折叠 cue、状态 CSS | 已查范围 Clear；系统动态偏好只查 CSS |

## Findings

以下两项是本次调整前、与用户反馈对应的根因，均已实施修复；不是将项目原有视觉风格判定为缺陷。

| Severity | Domain | Location | Before | After | Why |
| --- | --- | --- | --- | --- | --- |
| MEDIUM | Layout | 基线 styles.20261022a.css:2176、2183；新 styles.20261022b.css:2237 | 产品介绍与下载分别 `flex:1 0 auto`，各自消化剩余高度 | `.panel-main` 整体居中，内含介绍、功能、下载；组内固定 32px 间隔 | 相关内容的关系不再随屏高改变，阅读顺序更连续 |
| MEDIUM | Layout | 基线 styles.20261022a.css:2180；新 styles.20261022b.css:2263 | 功能名称与说明分两列，说明 `text-align:right` | 单列标题/解释，共用起始边；组内 4px、组间 16px | 用户无需来回扫描两条边；窄面板和英文换行更稳定 |

顶栏合并品牌和语言，下载作为唯一实心主操作，源码降为文字链接；兼容性信息与 build 归入页脚。保留 M4 实测边界和 2.9.8 回退，不恢复支持作者或手动 2.9.9 入口。

## Verification

Passed：

- CUA 实际查看最终 1440×1000 中文、1280×800 英文、390×844 中文及 820×900 中文截图。
- 320×844 英文无横向溢出；820×900、1920×1080 DOM 几何检查无内容裁切；英文笔记本下载按钮在首屏可见。
- 320px 下 `html{font-size:200%}` 专用本地 fixture，无横向裁切、控件仍在自然文档流。此项是文字放大，不等于浏览器缩放。
- RTL 专用 fixture 的品牌/语言顺序镜像，正文 start 对齐，无横向溢出；不代表阿拉伯语翻译已测试。
- 键盘依次到达语言、下载、源码、兼容性控件；焦点轮廓可见，Return 展开原生 details。仅检查下载链接地址，未触发真实下载。
- `node --check packaging/pkg/output/website-layout-skill-20261022/inline-0.js` 通过。
- HTTP 读取本地根页面和新 CSS，均与实际源文件逐字节一致。已发布 a 样式表未改变；b 的共享 CSS 前缀逐字节保留。

Not verified：完整 VoiceOver、全站 WCAG 审计、浏览器菜单 200% 缩放、系统 reduced-motion / forced-colors 实机切换。左侧已有动画与后续网页未重新审计。

## Verdict

Approve：仅限以上已检查的本地右侧范围，未发现仍待处理的 HIGH 项；六个领域均已按说明检查，未验证项如上。视觉方案等待维护者审核，**未部署**。

## Reproduction and history

JSON 记录基线、源文件哈希、截图和验证结果。以线上 80d80198 为基线，将 a CSS 复制为 b 再应用 CSS patch，随后应用 HTML patch。旧 a 保留供当前线上版本使用。父仓库有其他改动，因此活动 app 仓库仅保存本次独立补丁与记录，不批量提交父仓库。
