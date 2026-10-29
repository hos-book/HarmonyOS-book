# 性能分析与调优

本文件维护阅读链路的性能约束、采集方式和已验证结果。首次分析日期：2026-10-29。按华为 Performance Analysis Kit 的 HiTrace、HiLog 与设备诊断方法，先确认业务路径，再用定向回归和真机检查验证改动。

## 业务路径与已落地改动

本轮关注“进入阅读 → 缓存索引就绪”和“连续阅读 → 跨章预载及淘汰”。调用链仍为现有页面、阅读组件和 Service，没有新增接口、数据表或后台遥测服务。

| 路径 | 原问题 | 当前实现 |
| --- | --- | --- |
| `ReaderCacheService.initialize → scan` | 对每个缓存文件串行等待 `stat`，同一队列中的缓存记录操作也要等待扫描完成 | 最多 4 个工作循环并发读取文件元数据；不创建全量 Promise；扫描完成后一次发布完整索引 |
| `ReaderContinuousComponent → OnlineTextScrollDataSource.insert/remove` | 逐行 `splice` 和通知；章节头部插入、淘汰反复搬移现有数组 | 一次批量插入或删除，通过一次 `onDatasetChange` 提交准确的 `index/count` |
| 上述操作的耗时定位 | 缺少业务区间，难以从框架 Trace 中识别缓存扫描和行数据增删 | `PerformanceTrace` 添加固定名称的按需 HiTrace 标记 |

主要代码：

- [ReaderCacheService.ts](../entry/src/main/ets/service/ReaderCacheService.ts)
- [OnlineTextScrollDataSource.ets](../entry/src/main/ets/service/text/OnlineTextScrollDataSource.ets)
- [PerformanceTrace.ts](../entry/src/main/ets/utils/PerformanceTrace.ts)

缓存扫描继续遵守路径白名单、并发删除容错、文件类型检查、空间统计、使用中保护与队列顺序。扫描期间排队的缓存记录在完整索引发布后执行，不会被扫描结果覆盖。

连续阅读继续使用 `LazyForEach` 和稳定的行键，保留未删除行的对象身份与字符偏移。`reset/insert/remove` 全部采用批量通知 API，避免将 `onDatasetChange` 与旧的 `onDataAdd/onDataDelete/onDataReloaded` 混用。该通知 API 从 API 12 起支持。

`PerformanceTrace` 使用 API 19 起支持的 `isTraceEnabled/startAsyncTrace/finishAsyncTrace`，满足最低 API 20。采集未开启时不生成事件；开始和结束使用相同任务 ID，并在异常路径上配对。名称固定，不写入正文、书名、URL 或账号；采集失败不改变业务结果。

## 验证结果与口径

### 主机定向对照

使用 Release IDE 内置 TypeScript 转译真实业务源码，在 Node 环境运行。下表是本机本次结果，不能解释为真机启动时间、帧率或整体提速比例。

| 场景 | 修改前 | 修改后 | 说明 |
| --- | ---: | ---: | --- |
| 已有 6000 行，头部插入再删除 2000 行 | 54.029 ms | 0.021 ms | 预热 3 次，测量 20 次的中位数；监听器仅计数，不含 ArkUI 实际布局和绘制 |
| 上述操作的数据通知次数 | 4000 | 2 | 插入、删除分别通知一次 |
| 扫描 256 个缓存文件 | 3933.52 ms | 975.36 ms | 每次 `stat` 模拟 2 ms 等待，实际绝对耗时受 Windows 定时器粒度影响 |
| 扫描的最大在途 `stat` 数 | 1 | 4 | 并发上限验证通过 |

定向回归已通过：

- `scripts/test-reader-performance.cjs`：批量通知后的数据完整性、顺序、行身份、字符定位、空操作、监听器注销，以及异常路径 Trace 配对；缓存扫描的并发上限、文件消失、非文件过滤与排队记录。
- `scripts/test-reader-cache-budget.cjs`：缓存预算、保留保护和清理回归。
- `scripts/test-reader-progress.cjs`：阅读位置、连续阅读和相关设置回归。

`OnlineTextScrollDataSource.ets` 的 `check_ets_files` 无诊断。本轮代码已成功构建、安装并启动到手机。MCP 构建入口遇到 ohpm 批处理递归栈溢出，随后使用已安装 Release IDE 的 Node/Hvigor CLI（`--no-daemon`）完成构建。

SDK 的 `sdk/default/sdk-pkg.json` 已确认 `releaseType: Release`；当次 HAP 元数据为 `compileSdkVersion=26.0.0.105`、`apiReleaseType=Release`、`minAPIVersion=60000020`、`targetAPIVersion=260000026`。本次安装的是 debug 包，不是发布性能基准。

### 手机检查与 Trace

设备为 VYG-AL00、API 26，包名 `com.huan.listenbook`。

- 连续阅读第 6 → 7 章、反向回滑，正文和章节提示衔接正常。
- 退出阅读后再次进入，恢复到第 6 章约 82% 的同一段落。
- 在第 8 章约 61% 处将字号 18 调为 19，正文重新排版后保持同一字符段落；实际查看了顶部状态区和底部信息区，没有正文与系统栏重叠。
- 启动采样捕获 `reader.cache.scan`，本次约 249.519 ms。这是包含异步 I/O 等待的操作总时长，不是主线程连续阻塞时长。
- 跨章采样捕获一次 `reader.scroll.remove`，本次约 0.669 ms。这是数据删除及通知提交区间，不是整帧渲染耗时；该采样未捕获 `reader.scroll.insert`，不报告其真机耗时。

前后启动采样期间存在其他任务改动和页面切换，页面、缓存及进程状态不一致。初始化日志的 902/878 ms、PSS 的 205145/260162 KiB 均不具备净收益对照条件；`app_startup` 表也没有有效系统首帧结果。因此不据此宣称启动、帧率或内存改善。阅读后静止时采集的 CPU/PSS 同样不能替代滑动 CPU 分析或内存泄漏验证。采样中的可访问性查询也带有 UI 自动化开销。

用户确认可独占设备后继续了功能检查，但字号验证后的重新入页阶段仍出现额外页面切换，后续操作不纳入性能对照。当前仅完成这台手机的上述验证，未完成平板、折叠窗口、PC 或手表实测；未执行全量内存审计、长时间泄漏测试或发布包 FPS 基准。

## 复现与后续使用

### 定向回归

Windows `cmd.exe` 示例，IDE 路径按本机安装调整：

```bat
set "DEVECO_HOME=D:\soft\DevEcoStudio-26.0.0-Release"
"%DEVECO_HOME%\tools\node\node.exe" scripts\test-reader-performance.cjs
"%DEVECO_HOME%\tools\node\node.exe" scripts\test-reader-cache-budget.cjs
"%DEVECO_HOME%\tools\node\node.exe" scripts\test-reader-progress.cjs
```

性能脚本可额外传入修改前源码根目录，目录需包含同路径的 `ReaderCacheService.ts` 与 `OnlineTextScrollDataSource.ets`：

```bat
"%DEVECO_HOME%\tools\node\node.exe" scripts\test-reader-performance.cjs C:\path\to\baseline
```

保留同一 Node、相同输入和测试顺序；主机数值仅用于定位算法及调度开销。

### 按需设备采集

可在 DevEco Profiler 中采集相同场景并搜索下列业务标记，也可用 SDK 自带 `hdc`。将 `DEVICE_ID` 替换为实际设备号，在专用采集窗口内执行：

```bat
hdc -t DEVICE_ID shell hitrace --trace_begin -b 65536 app ace graphic sched ability
```

完成一次进入阅读、连续跨章与返回操作后及时结束采集：

```bat
hdc -t DEVICE_ID shell hitrace --trace_finish -o /data/local/tmp/reader-performance.ftrace
hdc -t DEVICE_ID file recv /data/local/tmp/reader-performance.ftrace C:\path\to\reader-performance.ftrace
```

| 标记 | 定位范围 |
| --- | --- |
| `reader.cache.scan` | 缓存索引扫描，包括异步等待 |
| `reader.scroll.insert` | 连续阅读批量增行及通知提交 |
| `reader.scroll.remove` | 连续阅读批量删行及通知提交 |

解析器可能为名称添加 `H:` 前缀。用主线程调度和框架布局/绘制区间交叉判断，不能把异步操作总时长直接当作卡顿时长。比较前后版本时固定包配置、书籍、章节、字号、缓存、后台任务及采集动作；内存趋势需重复进入退出同一页面并使用一致的稳定等待条件。

本轮原始 Trace、SQLite 解析结果、摘要、构建日志和截图保存在本机任务目录 `C:\Users\ylwang112\AppData\Local\Temp\hsda-perf-20261029`。这些是临时分析产物，不加入源码仓库；本文中的结论和复现方法不依赖它们长期保留。

## 实际参考的资料

- [华为 Performance Analysis Kit 能力目录](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/performance-analysis-kit)
- [Performance Analysis Kit 概述](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/performance-analysis-kit-overview)
- [性能异常检测](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/perf-detection)
- [性能跟踪导航](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/hitracemeter)
- [在线技能：ArkUI 性能分析](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/arkui-performance-analysis/SKILL.md)，并读取其 `references/component/frequent-work.md`、`references/startup/lifecycle-work.md`、`references/scroll/lazy-loading.md` 和 `references/trace-guidance.md`，用于选择热路径及采集方法。
- [在线技能：ArkUI 内存分析](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/arkui-memory-analysis/SKILL.md?ref=main)，仅采用相关语义检查参考，未执行其全量自动扫描或 HTML 报告流程。
- [在线技能：ArkTS 语法](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)和 [ArkUI 知识检索](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md)。
- [OpenHarmony LazyForEach 指南](https://raw.gitcode.com/openharmony/docs/raw/master/zh-cn/application-dev/ui/rendering-control/arkts-rendering-control-lazyforeach.md)，并用本机 SDK 的 `ets/component/lazy_for_each.d.ts` 核对批量通知协议，用 `ets/api/@ohos.hiTraceMeter.d.ts` 核对 API 版本。

本轮已刷新在线技能仓库索引和相关目录，并读取上述技能及所需参考；在线目录只在内存中使用，没有克隆或安装到项目。
