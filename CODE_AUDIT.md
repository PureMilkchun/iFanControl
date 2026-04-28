# 代码审查经验记录

记录项目审查中犯过的错误和学到的教训，避免重蹈覆辙。

---

## 1. 把设计意图误判为 bug

**时间**：2026-04-28 审查

**误判内容**：

| 代码 | 我的判断 | 实际情况 |
|------|----------|----------|
| `shutdown()` 同步发送心跳（阻塞退出） | bug，应该异步 | 刻意设计：退出时必须同步确保数据不丢 |
| `fanCommandInFlight` 丢弃并发命令 | bug，可能丢命令 | 刻意设计：硬件控制不能并发，丢掉的命令会在下个 2 秒周期重新评估 |
| `calculateFanRPM` 返回 -1 表示无匹配区间 | bug，-1 会传给硬件 | 调用方在调用前已 `guard !curve.isEmpty`，-1 是不可达路径 |
| `isInfinite` 未检查 | bug，可能产生 NaN 转速 | 硬件传感器数据范围有限，实际不会触发 |

**教训**：
- 不要只看局部代码就下判断，先追踪完整的调用链和数据流
- 遇到"看起来不对"的代码，先问「作者为什么要这样写」，而不是「为什么这样写是错的」
- 如果是独立的工具函数，看所有调用方如何使用它；如果是状态变量，看所有读写点

---

## 2. 修改状态变量位置引发无限递归

**时间**：2026-04-28 修复 `lastSetRPM` 初始化

**错误操作**：
- 为了修复 `lastSetRPM` 的初始化问题，在 `refreshHardwareProfile()` 中移动了 `hasProbedHardware = true` 的位置
- 将它放在了 `refreshTelemetry(force: true)` **之后**

**调用链**：
```
refreshHardwareProfile()
  → hasProbedHardware = true（被移到这里）
  → refreshTelemetry(force: true)
    → probeHardwareIfNeeded()
      → guard !hasProbedHardware else { return }  // 此时还是 false！
      → refreshHardwareProfile()  // 递归！
```

**正确做法**：
- `hasProbedHardware = true` 必须在 `refreshTelemetry()` 之前设置
- 修改状态 flag 前，画出所有依赖该 flag 的调用链

**教训**：
- 移动一行代码之前，必须理解它为什么在那个位置
- 对于 `hasXxx` / `isXxx` 这类 guard flag，追踪所有 `guard` 语句
- 修改后想想：「如果这行提前执行会怎样？如果延后执行会怎样？」

---

## 3. 编译后替换到了错误目录

**时间**：2026-04-28 部署 build 37

**错误操作**：
- 编译后将二进制复制到了 `macfan-control-v2/iFanControl.app/`（开发目录）
- 用户实际运行的是 `/Applications/iFanControl.app/`（系统目录）
- 用户反馈「我本地跑的依旧是 36」

**根因**：
- 开发过程中曾经替换过开发目录的 app bundle
- 后续部署时凭记忆操作，没有确认用户的实际运行路径

**教训**：
- 部署前先确认用户从哪里运行：`pgrep -l iFanControl` 之后 `ls -la /proc/PID/exe` 或检查进程路径
- 不要假设上次的操作对本次也适用
- 项目记忆里记录了「构建产物」，但没有记录「用户运行路径 = /Applications/iFanControl.app/」

---

## 4. 判断严重性时过度自信

**时间**：2026-04-28 审查

**错误操作**：
- 将 `shutdown()` 的同步阻塞、`fanCommandInFlight` 丢弃命令等标记为「致命 bug」
- 语气过于肯定，用户被吓到：「你真的吓到我了。我们刚刚修理的那个 bug 是设计意图还是真的 bug？」

**教训**：
- 报告潜在问题时，先区分「确认的 bug」和「看起来可疑但可能是有意设计的」
- 对不确定的问题使用试探性语气：「这里的设计意图是什么？我看到 X，会不会导致 Y？」
- 不要为了显得「审查得很仔细」而把每个设计决策都标记为问题

---

## 5. CDN 传输会改动文件大小，不能用于校验

**时间**：2026-04-28 build 38 发布

**错误操作**：
- 更新校验逻辑中同时检查文件大小（`data.count != expectedSize`）和 SHA256
- 本地 ZIP 6008350 字节，经 Cloudflare CDN 下载后变为 6008345（差 5 字节）
- 大小校验先触发失败（"安装包大小校验失败"），SHA256 校验根本没走到

**根因**：Cloudflare CDN 在 HTTP 传输层可能微调字节数（chunked encoding 边界处理等），但文件内容不变（SHA256 一致）。

**教训**：
- SHA256 是加密级别的完整性校验，已足够保证文件未损坏/篡改
- 文件大小校验不可靠——CDN、代理、中间件都可能改变传输字节数
- 如果一定要做双重校验，**先验 SHA256，再验大小**（不要反过来）

---

## 6. DispatchSemaphore 超时模式引入线程竞争，导致温度读取卡住

**时间**：2026-04-28 build 38 热修复

**错误操作**：
- 为防止 kentsmc 子进程永久阻塞，在 `Process.waitUntilExit()` 外包了 `DispatchSemaphore` 超时机制
- 模式：`DispatchQueue.global().async { task.waitUntilExit(); semaphore.signal() }` + `semaphore.wait(timeout:)`
- 应用到三个调用点：`BackgroundHardwareReader.executeRead`、`FanManager.executeReadCommand`、`CommandExecutor.executeCommand`

**后果**：
- 温度/转速读取变慢，甚至完全卡住不动
- 用户反馈：「前面读取的温度和速度变慢了，甚至有时候一直卡在那不动」

**根因**：
- `DispatchQueue.global().async` 为每个 kentsmc 子进程创建额外的线程跃点
- 原始 `waitUntilExit()` 在调用线程直接阻塞，行为简单可靠
- 超时模式的线程切换可能引入与 kentsmc 的 SMC 访问之间的竞争条件
- 这是理论上的改进（超时保护）在实际中制造了新问题

**修复**：
- 全部撤回为直接 `task.waitUntilExit()`，恢复原始行为
- 超时保护理论上正确，但 kentsmc 实际不会挂死，引入的复杂性大于收益

**教训**：
- 不要「预防性」地加固尚未出问题的代码路径
- 引入线程/并发变化时，必须考虑与外部进程的交互
- 如果原始代码工作正常，改动后出问题，先撤回改动再分析
- 理论上的改进 != 实际上的改进

---

## 总结

1. **先理解，后判断** — 读调用链、数据流，再下定论
2. **追踪 flag 依赖** — 移动状态变量前，画调用图
3. **确认运行环境** — 部署前验证实际路径
4. **区分确信度** — 报告问题时标明 certainty level
5. **不依赖文件大小校验** — SHA256 足够，CDN 会改字节数
6. **不要预防性加固** — 理论改进可能引入实际问题，先撤回再分析
