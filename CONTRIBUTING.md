# 开发与发布约定

## 分支与提交

- `main` 保存正式版本代码。目前是2.9.9/build52；合并开发分支不等于获准发布正式版。
- `codex/3.0-beta` 保存3.0筹备期间的Beta开发基线，目前对应2.9.10 Beta/build70。
- 日常改动从Beta分支创建 `codex/<具体任务>`，通过PR合回Beta分支。准备正式版时另开Beta到main的PR，由维护者决定合并与正式发布。
- 两条长期分支要求PR和`build`检查通过，禁止强推/删除。当前为单维护者，不强制第二个人审批；管理员也遵循检查。基线初始化PR保持Draft。
- 提交按可独立理解的改动拆分，使用 `feat:`、`fix:`、`refactor:`、`test:`、`docs:`、`chore:`。不为补历史而伪造旧Beta的提交。62～69保留原构建记录，70从当前完整源码建立真实Git基线。
- 提交前查看 `git diff`、`git diff --cached`、`git diff --cached --check`，逐项选择文件，不使用未经检查的整目录提交。

```sh
git fetch origin
git switch -c codex/your-task origin/codex/3.0-beta
```

## 构建与验证

App元数据唯一来源为 `packaging/app/Info.plist`，图标为根目录 `icon.png`。根目录 `kentsmc`是现有固定工具输入，版本来源尚未在本项目映射，不在本轮更换。源码和输入文件纳入Git；生成的App/PKG、签名、缓存、用户配置、反馈邮件与实验数据不纳入。

```sh
python3 scripts/build_app.py
bash packaging/pkg/test_updates.sh
python3 packaging/pkg/test_ui.py
python3 packaging/pkg/test_startup.py
```

构建生成 `build/iFanControl.app` 和 `build/app-build.json`，记录源提交、工作区是否有改动、版本/build/通道和输入哈希。不会启动或安装App。测试使用隔离状态及硬件/网络替身；UI变化仍须实际检查原生中英文、深浅色与相关状态，不能把自动测试通过当视觉验收。

GitHub Actions对main/codex分支推送及长期分支PR运行Release构建、更新契约/实际updater回归、原生控制器/启动回归。检查不会发布、安装或操作真实风扇。CI还核对已发布70标签与其源码记录，后续源码变化不会被要求继续等于70。

## Beta发布

1. 在 `packaging/app/Info.plist` 更新版本、全局递增build和Beta身份，完成测试/原生验收，提交源码。正式与Beta共用build序列；下一个必须大于70。
2. 从该代码构建App与PKG，不向 `/Applications` 复制程序，不强杀运行中的App：

   ```sh
   python3 scripts/build_app.py
   python3 packaging/pkg/build.py --app build/iFanControl.app --tool kentsmc --output packaging/pkg/output/beta-71
   ```

   示例输出名71应与已提交Info.plist保持一致。CLI版本/build/channel覆盖仅用于明确的候选构建；发布必须与提交元数据相符。

3. 按现有Beta隔离流程发布，仅修改Beta feed和独立含build的PKG。保留正式/旧feed、包、官网下载、官网版本与后端。Git推送和CI不会自动执行部署。正式版发布由维护者另行决定。
4. 公网重下载并核对包SHA256、feed身份/build/no-store及原资产保留。将包URL/哈希、源码输入哈希、部署身份与验证摘要记录到 `docs/releases/<version>-beta.<build>.json`，并提交记录。标签提交中的源文件应与实际构建输入一致；使用 `verify_release_source.py` 检查。
5. 创建不可重写的注释标签，例如 `v2.9.10-beta.71`，推送到GitHub。仓库规则保护v*版本标签，禁止更新和删除（管理员也无绕过名单）；不覆盖已经发布的标签或包；修复发布需要新build、新提交和新标签。Beta标签不创建正式GitHub Release，不推进main或稳定线路。

```sh
python3 scripts/verify_release_source.py docs/releases/2.9.10-beta.70.json --ref v2.9.10-beta.70
```

70的记录是在已发布包之后补录，标签未嵌入原PKG。保存的源码/输入哈希与已发布70基线核对一致；这不声称从新机器重新打包会得到逐字节相同的签名或PKG。

## 本机历史资料

Cloudflare状态与App产物只取消Git追踪，磁盘上的现有文件保留，旧Git历史不改写。现有离线 `analysis/`、UI HTML试稿和旧公告经本机 `.git/info/exclude` 留在工作区，不混入70源码基线；若以后要维护这些实验，单独审阅并以PR加入。反馈邮件明确在 `.gitignore` 排除，避免误传公开仓库。

本仓库的 `docs/development/` 为研发文档，相邻目录中的官网是另一发布范围。研发截图证据在 `docs/development/assets/`；完整构建与部署诊断仍在忽略的 `packaging/pkg/output/`。发布后的原生启动/设备控制仍由维护者实际升级验收。
