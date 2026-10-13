# Git历史与回退约定

本阶段只建立源码历史、远端备份和回退点。提交或推送不触发构建、测试、打包或部署；GitHub构建workflow已停用，源码中的触发方式也只保留手动入口。现有构建/测试工具保留供将来明确需要时使用，不是保存代码的前置条件。

## 分支与检查点

- `main`：正式版本代码，目前为2.9.9/build52。正式发布另行决定。
- `codex/3.0-beta`：当前开发代码。已保存Beta70完整基线，后续可以直接小步提交和推送。
- `codex/<任务名>`：较大实验或需要隔离的修改，可按需创建；PR也是可选的审阅入口。
- 两条长期分支只防止强推和删除，没有必须构建或PR的门槛。
- 发布检查点用注释标签，例如 `v2.9.10-beta.70`。v*标签禁止更新/删除，已发布检查点不覆盖。

Beta70源码基线提交为 `03e3d1d`；对应标签和 `docs/releases/2.9.10-beta.70.json` 保存已发布包的源码输入与哈希。它是发布后补录的基线，未伪造62～69提交，也不声称原包中嵌入了此Git提交。

## 日常保存

```sh
git status --short
git diff
# 明确选择本次文件，例如：
git add Sources/MacFanControl/main.swift
git diff --cached
git commit -m "fix: describe the concrete change"
git push
```

按能独立理解的改动提交，常用feat/fix/docs/chore前缀。不混入其他尚未完成的工作，不使用未经查看的整目录提交。构建、安装、替换用户App和云端发布与Git保存分开；本阶段不执行这些操作。

## 查看与回退

```sh
git log --oneline --decorate -12
git show v2.9.10-beta.70
```

已推送的错误修改用 `git revert <提交>` 生成反向提交，再推送，保留发生问题和修复的完整历史。它只改变源码，不会自动降级已安装的软件。

需要查看完整旧状态时，先提交或暂存当前改动，再从标签创建恢复分支：

```sh
git switch -c codex/recovery-beta70 v2.9.10-beta.70
```

不对共享分支使用reset --hard加force push，不删除现有历史，也不重写发布标签。回退前先确认需要撤销的范围；这里提供操作方法，不代表已执行产品回退。

## 文件范围

追踪Sources、源码元数据 `packaging/app/Info.plist`、图标/现有工具输入、脚本、研发文档和截图证据。生成App/PKG/签名、Cloudflare/Xcode缓存、用户配置、反馈邮件与实验数据不入库。

原本已追踪的App/缓存仅取消Git追踪，现有磁盘文件和旧Git历史保留。analysis、HTML试稿及旧公告经本机.git/info/exclude留在工作区；以后需要维护时单独审阅加入。研发截图保存在docs/development/assets；完整旧构建诊断仍在忽略的packaging/pkg/output。
