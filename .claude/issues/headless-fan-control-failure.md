# 已解决：Mac mini 无显示器时风扇控制失效

**状态**：已解决

**发现日期**：2026-04-29

**解决日期**：2026-04-29

**影响版本**：v2.9.5 / build 39 → v2.9.5 / build 40（已修复并发布）

---

## 表现

- Mac mini 不连接显示器时，风扇控制完全不起作用，机身变热
- 进程存在、菜单栏有显示（连接显示器后可见）
- 连接显示器的瞬间，风扇控制立即恢复

## 已排除

| 假设 | 结论 |
|------|------|
| RunLoop 不迭代导致 Timer 不触发 | 已改为 GCD `DispatchSource`，无改善 |
| Process 超时机制导致线程竞争 | 已撤回 semaphore 超时，无改善 |
| kentsmc 子进程永久阻塞 | 已撤回超时保护，恢复原始 `waitUntilExit()` |

## 当前已加诊断（build 39 本地版）

- 控温循环每 30 秒输出 `ctrl diag` 日志（bgTemps/bgRPMs/sensors/readings）
- 缓存为空时输出 `ctrl loop skip: bgReader cache empty`
- 所有传感器读取失败时输出 `bg refresh: all N sensor reads failed`
- Process.run() 抛异常时输出 `Process.run failed`

## 诊断步骤

1. 断开显示器
2. 等 Mac mini 发热（5-10 分钟）
3. 重新连接显示器
4. 查看日志：
```
cat ~/Library/Application\ Support/MacFanControl/logs/iFanControl-*.log | grep -E 'ctrl diag|ctrl loop skip|bg refresh|hardware profile|Process.run failed'
```

## 已确认现象与根因

### 日志证据

在 `~/Library/Logs/iFanControl/ifancontrol.log` 中出现过：

```text
[INFO] ctrl diag bgTemps=0 bgRPMs=0 sensors=37 readings=0 hasReading=false
[WARN] ctrl loop skip: bgReader cache empty, 37 sensors configured
```

这说明当时：

- 硬件 profile 已经存在（37 个可用传感器）
- 控温循环本身仍在触发
- 但后台读取器缓存为空，导致控制循环直接跳过

### 根因判断

问题不在 Timer / RunLoop 本身，而在于 **后台温度缓存失效后没有恢复路径**：

1. 控温循环主要依赖 `BackgroundHardwareReader` 的异步缓存
2. 当无显示器状态下后台传感器读取连续失败时，原逻辑只会继续等待下一轮后台刷新
3. 如果缓存长时间为空或过旧，控温循环就会持续 `skip`
4. 同时 `FanManager` 的硬件探测是一次性的；显示器连接状态变化后，原来不会主动重新 `refreshHardwareProfile()`
5. 因此“接上显示器瞬间恢复”很符合：显示器变化让传感器重新可读，但旧代码缺少自动重建 / 兜底恢复

### 追加教训（2026-04-29）

曾尝试在控温循环主线程中加入同步 fallback 读取（直接调用 `availableTemperatureReadings()` / `refreshHardwareProfile()` 链路），这会导致菜单栏 UI 卡死。日志里出现过：

```text
[DEBUG] slow read command args=-r FNum duration=65.361s
```

结论：

- 不能在主线程控温循环里做同步硬件探测或全量传感器读取
- 恢复策略必须以异步后台刷新 + 系统 `fan auto` 兜底为主
- 菜单栏可用性比激进恢复更重要

## 已做代码改动

- 三个 `Timer.scheduledTimer` → `DispatchSource.makeTimerSource`（queue: .main）
- 控温循环增加每 30 秒诊断日志
- 后台读取器刷新失败时输出 warning
- Process.run() 异常时输出 error 日志
- `BackgroundHardwareReader` 增加：
  - 连续温度读取失败计数
  - 最近一次成功刷新时间
  - `refresh` 并发保护（避免堆积）
  - 主线程 fallback 后回填缓存能力
- `FanManager` 增加 `reprobeHardware(reason:)`
  - 后台连续失败时可重新探测硬件 profile
  - 显示器 / 屏幕参数变化时强制重探测
- 控温循环增加轻量恢复：
  - 当后台缓存为空、过旧，或失败次数过多时，触发额外一次后台刷新
  - 不再在主线程做同步传感器读取，避免菜单栏卡死
- 控温循环增加系统兜底：
  - 如果最终仍然拿不到可读温度，不再只是 `skip`
  - 现在会调用 `setFanAuto()` 将风扇控制权还给系统
  - 增加 30 秒节流，避免异常期间每 2 秒重复发送 `--fan-auto`
- `setFanAuto()` 的控制循环调用改为异步：
  - 避免在主线程同步等待 `sudo kentsmc --fan-auto`
  - 菜单栏交互不会再因为兜底动作被卡住
- 手动模式高温保护：
  - 如果仍处于手动模式且温度达到 critical threshold（95C），立即交还系统控制
- 紧急温度保护：
  - 如果任意模式下温度达到 emergency threshold（100C），立即交还系统控制
- 风扇命令失败保护：
  - 如果 `setFanRPM` 下发失败，触发 fail-safe，把控制权交还系统
- `handleScreenOrDisplayChange()` 不再只重建菜单栏图标，也会重新探测硬件并触发一次后台刷新
  - 后续又收窄为：只有当前 fan/sensor profile 缺失时才重探测，避免显示器事件导致主线程重负载

## 验证与发布

- `swift build` 通过
- `swift build -c release` 通过
- 已将修复后的 build 40 二进制替换到：
  - `/Users/puremilk/Documents/mac fancontrol/macfan-control-v2/iFanControl.app`
  - `/Applications/iFanControl.app`
- 已重新签名并重新启动 `/Applications/iFanControl.app`
- **已完成灰度发布**：v2.9.5 / build 40 已上传到 GitHub Release 和官网
