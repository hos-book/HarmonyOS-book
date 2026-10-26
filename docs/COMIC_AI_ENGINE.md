# 漫画本地着色子包

主工程通过 `entry/oh-package.json5` 引用 `entry/libs/aiengine.har`（`@legado/aiengine`），不复制引擎源码、不注册额外 App 模块。当前固定提交为 `0d152ab20962c3171054cb852578960c21b647d5`（2026-10-26），包声明版本仍为 1.0.0；上游仓库、提交和集成版本见 `scripts/comic-ai-package.json`。该版本已吸收 Worker 复用、原生像素处理与 FP32 复核补丁，并新增模型下载宿主接口。

首次拉取项目或升级子包时，在已登录且能访问该仓库的 GitHub CLI 环境执行：

```text
python scripts/prepare-comic-ai.py
ohpm install --all
```

需要 Python 3.11+、Git / GitHub CLI，以及指向正式版 DevEco Studio 的 `DEVECO_HOME`。脚本在项目外临时目录下载固定提交，先用 IDE 内置 Node（需 22.18+）执行上游 `scripts/check.mjs`，再执行本项目 `scripts/test-comic-ai-package.mjs`。新版已包含旧性能和校准补丁，不再重复应用；集成标记记录使用上游实现。脚本补充 `Index.ets` / `Worker.ets` 导出和经过 SHA-256 验证的离线模型资产，再构建并检查 API 20/26、Release SDK、release 模式、双架构原生库和标记。结束清除临时源码，仅保留 HAR、校验记录与许可证。大模型 HAR 和本机记录不加入 Git；匹配固定版本与文件散列时直接复用，强制重建使用 `--force`。旧补丁脚本仅供旧固定版本构建使用。

当前子包携带三个约 59 MiB 模型，HAR 约 164 MiB。模型随应用安装，首次着色时由引擎校验并提取，不需用户填 API 或下载模型。第三方许可证随应用保存在 `rawfile/comic_ai_engine`，模型及字典声明由 HAR 自带。

`ComicAiHost` 仅为有效会员授权着色能力，提供缓存预算通知及 Worker 创建；禁止引擎直接下载图片。新版下载接口在本 App 中只复制随包模型：模型从固定旧提交提取并校验 SHA-256 后打入 HAR，宿主按 1 MiB 分块提取至 `.part`，由引擎校验后改名，复制中途也检查会员和取消状态。无需轻页账号、OBS 下载票据或额外云服务。`ComicColorizationService` 将已有公共图片加载链的本地缓存原图交给子包，并保留翻译会员权限检查、队列上限、协作取消和原图回退。推理、模型选择、像素合成及内容哈希缓存由子包负责。NNRT 允许不支持的算子回到 CPU，不能等同于所有算子都在 NPU 执行。

所有机型使用同一套 HAR，通过系统 NNRT 设备枚举发现加速能力，并按设备 ID、类型、名称和画布尺寸记录后端选择；不按芯片型号分包或强制启用 NPU。首次校验时，先保留上游 CPU FP16 画质对照和耗时比较；仅原画质对照失败才增加 CPU FP32 复核。模型文件、CPU 的 4 线程 / `preferred_fp16`、NNRT 的 `PERFORMANCE_HIGH`、整图和底部 20% 的 MAE 阈值 0.03，以及 NNRT 至少快 10% 的门槛均不变。速度始终与原 CPU FP16 对比，回退也使用原 CPU FP16 输出；复核异常或仍不合格时保留原保护逻辑。首次校验失败的设备会增加一次 FP32 推理，原校验通过的设备不增加此开销；已验证后端直接推理。FP32 只用于复核，不作为所有机型的新推理精度。本项目尚未实测 Kirin 9030，保留上游默认参数；上游的 9030 Pro 测量不能视为本 App 已完成验证。

新版仅持久化真实图片校验成功的 NNRT 选择，最多 32 条、有效 7 天；模型散列、系统版本和校验规则变化会失效，CPU 失败选择不跨进程恢复。校验规则契约使用上游 `ComicColorProfilePolicy.CONTRACT`，更新后旧契约决定不会误用。用户主动开启着色后预先准备 CPU 模型资源和 Worker，不做空白图推理；实际图片按方向准备 NPU 模型。Worker 空闲最多保留 120 秒，关闭或离页沿用宿主释放逻辑。`EntryAbility` 经 `ComicAiHost` 转发前后台和内存等级：后台取消并释放；前台 `MEMORY_LEVEL_MODERATE` 释放一次，后续请求可重建并复用；低内存、严重不足、后台及未知等级仍释放并暂停预热和保留 60 秒。两条路径均不强杀在途原生推理，使用释放 epoch 等待安全完成；中等级通知也不会取消已经生效的低内存冷却期。尚未用过引擎的启动/前后台通知不会初始化 HAR，手表分支不接入。等级按系统通知判断，不写死芯片或可用内存阈值；常量和释放接口均在最低 API 20 可用。

`worker-reuse-native-io-v1` 性能补丁将图片离屏的正常取消与 Worker 释放分开：只在 Worker 返回终止确认后复用，取消结果仍被丢弃；显式释放、后台、会员失效、内存压力、超时及异常仍释放。模型加载成功即记录单个 NNRT 模型缓存，避免加载期间取消导致下一张重载；方向/模型路径变化仍重新加载，不增加多模型常驻。RGBA 灰度输入、透明度合白和五通道补白改由原生完成；输出的有限值/范围校验与 NCHW 转换或 NHWC 复制合并遍历，返回独立缓冲区，保留 ArkTS 回退。模型文件、推理参数、分辨率、JPEG 95、合成算法及校验阈值不变；性能补丁不改变原校验契约。

阅读工具栏在翻译旁增加“着色”按钮，与设置内开关同步。启用时主题色高亮，关闭显示原图；每次进入阅读默认关闭。“着色中”和“正在翻译”显示在对应图片左上角，随图片滚动，不拦截图片手势；连续、左右翻页和渐隐共用图片组件。着色与端侧翻译可同时开启，先着色再在彩色图上绘制译文；两个开关独立，组合结果与纯翻译结果按输入图片隔离缓存。已有日/韩/英/中翻译实现与语言缓存保持不变。旧在线图片编辑服务、配置界面及数据模型已移除，旧 `comic_ai.db` 不再读取。

回归：`node scripts/test-comic-colorization.cjs`、`node scripts/test-comic-translation.cjs`，使用 Release IDE 内置 Node 和 `DEVECO_HOME`。脚本验证宿主边界、会员失效、任务取消、失败重试和翻译兼容性；真实模型推理效果及耗时须以设备结果为准。

着色结果按返回路径调用 `ReaderCacheService.record` 增量登记，HAR 的无路径写入通知不再使全缓存索引失效；结果已经写出但刚好离屏时仍完成登记，引擎异常或取消未返回路径时才重新扫描可能遗留的文件。缓存识别 `comic_images/color_alac-fp16-v<版本>_<64位SHA256>.jpg`，与原图共用预算、可见保护和清理流程，排除 `.part` 及其他目录中的同名文件。`scripts/test-reader-cache-budget.cjs` 用实际缓存管理器和宿主验证连续写入不遍历目录、重启发现、容量登记及释放保护。

2026-10-24 完整等待定位：增加宿主队列 `[ComicAiTiming]`、缓存登记 `[ComicAiCache]`、图片结果及加载完成 `[ComicAiView]` 计时，不记录图片地址。23:21 的正常复用请求中，HAR 处理约 1.6–2.1 秒，但宿主结果返回前额外等待约 1.7–2.2 秒；根因为 `noteComicWrite → reconcile → record → ensureIndex` 每张重新扫描全部阅读缓存。前图未结束又让后图排队，单张可见等待达到 4.2–7.2 秒，首次冷加载时更长；图片加载完成回调只增加约 26–61ms。回调计时不等于精确 GPU 呈现时间，也不包含“着色中”出现前的原图加载。

仅缓存修复安装后的同机实测：登记降为 0–2ms，无排队新图从开始到加载完成为 1806ms；连续翻页样本含约 0.86–1.15 秒排队，总计 2.68–2.98 秒。随后 23:31:08 的 `level=0 foreground=true` 通知触发原来统一的 60 秒冷却，连续约 15 张出现 `retained=false reused=false`，模型每张重载约 1.5–1.6 秒，单张处理又升至约 3.5 秒，含排队约 6 秒；23:32:10 后复用恢复，处理回到约 1.6–1.8 秒。这是第二个独立瓶颈，不能把缓存修复描述成已消除所有 3–4 秒等待。现按上述内存等级区分一次释放与持续冷却，保留低内存保护。

两项修复的最终 HAP 使用 Release SDK 26.0.0.105 构建并安装，缓存预算及宿主回归通过，包括前台中等级、低/严重、后台和未知等级分支。23:36:56 用设备 `aa send-memory-level -p <应用PID> -l 0` 定向发送中等级通知，日志为 `action=release-once`；在途 Worker 安全完成后释放，下一张重载 1760ms、处理 3890ms，随后的多张立即恢复 `reused=true load=0ms`，处理为 1687 / 1739 / 1815ms，不再等待一分钟。普通连续翻页样本从开始到图片加载完成约 2.4–2.9 秒，无排队样本 1731ms；释放后的首张及排在它后面的图片仍可能更慢。本轮未制造真实低内存或严重内存不足，不能将定向通知验证描述成低内存压力测试。LSP 仍报旧 HAR 声明缺少已有方法，实际 Release 编译器通过。内存等级含义核对了安装 SDK 的 `@ohos.app.ability.AbilityConstant.d.ts`；沿用在线 [日志定位](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-studio-hilog/SKILL.md) 与 [ArkTS 语法](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md) 指导，未执行整套低端机内存分档工作流。

2026-10-24 初次验证：修改的 ETS 静态检查无错误；Release SDK 26.0.0.105 构建 HAR 和调试 HAP 成功，HAP 已安装启动到连接的手机。真机可见翻译旁的着色入口与新的设置卡片，无模型配置入口。上游原版在 Kirin 9020 上报 `matches=false` 后选择 CPU，多张 1443×2048 输出成功，单张总耗时约 4.8–5.8 秒。

同日定位：原版将 CPU `preferred_fp16` 输出当作画质基准，CPU 半精度推理本身在此模型上存在明显数值偏差，导致更接近 FP32 的 NNRT 输出被误拒。用同一份 512×768 五通道输入、同一组模型权重在同一真机直接对照：

| 固定测试图 | 动态模型与 NPU 专用模型都在 CPU FP16 执行时的 MAE | CPU FP16 对 CPU FP32 的 MAE | NNRT 对 CPU FP32 的 MAE | NNRT 底部 MAE |
| --- | ---: | ---: | ---: | ---: |
| 线框与平坦灰阶 | 0 | 0.074920 | 0.010207 | 0.004757 |
| 线框、渐变与纹理 | 0 | 0.043776 | 0.001240 | 0.000985 |

两种图都复现原判定失败，并通过原有 0.03 阈值的 FP32 校验。模型公共层的权重和参数一致；固定模型在 CPU FP16 上与动态模型逐元素相同，排除了本次输入中的固定尺寸转换和输出通道排列问题。该证据定位到校验基准，不等于已定位 MindSpore CPU 内部具体哪个算子造成精度累积误差。

测试入口 `entry/src/ohosTest/ets/test/ComicColorBackend.test.ets` 的 `ComicColorBackendDevice` 执行上述四路推理对照，是需要真机 NPU 的专项诊断，不作为普通设备必须通过的测试。测试使用生成的固定灰阶图，不读取用户漫画或修改会员状态。全量历史 ohosTest 仍有旧书源接口移除造成的既有编译错误；本次采用独立测试入口，不能据此声称全量设备测试通过。实际 HAR/Worker 通过主应用临时诊断入口验证，验证后删除该入口。

升级前（`a1eaedd` + 条件复核 v2）在 Kirin 9020 主应用 Worker 验证通过：竖图及同尺寸再次处理均为 `cached=false backend=nnrt`，合成图总耗时 2.055 / 1.948 秒；横图首次校验日志为 `cold=3886ms nnrt=3886ms cpu=4706ms validation=fp32-recheck validationMs=8815ms matches=true selected=nnrt`，总耗时 19.709 秒。横图首次耗时包含模型初始化、CPU 对照、FP32 复核和合成，不能作为后续每张图片的耗时。另以固定上游与补丁后的真实校验方法进行模拟推理对照，原 FP16 校验通过的路径保持调用顺序、推理配置和输出一致，并覆盖复核通过、误差/速度不达标、复核异常、预热和取消路径。该检查不代替 9030 硬件验证。

`e459226` 升级已运行上游完整检查、补丁分支对照、宿主预热/权限/生命周期及原翻译回归；跨进程 NPU 记录复用和新版耗时仍需本 App 真机测量。在线技能根目录已更新；README 索引请求返回 HTTP 429，继续使用同轮已读的 ArkTS / 构建技能与本机 Release SDK。

2026-10-24 性能补丁验证：原版上游检查、补丁后的取消/生命周期/缓冲区回退专项检查及宿主着色回归通过；Release SDK 26.0.0.105 构建 HAR 和 HAP 成功。麒麟 9020 的临时 Worker 用 511×723 RGBA、非零缓冲区偏移、行跨度、透明度和 512×736 补白进行对照：输入与 NCHW/NHWC 输出逐元素一致，输出独立拥有内存，NaN / Infinity / 越界值被拒绝。相同固定数据在同一 Worker 中，输入由 261ms 降为 11ms，NCHW 输出校验与转换由 201ms 降为 3ms；这是该设备的一次对照，不能作为所有机型保证。

真实 HAR 端到端固定图测试：首图冷加载后，连续处理、中途取消、再继续只创建一个着色 Worker；取消日志为 `retained=true cancelled=true`，随后 `reused=true load=0ms`。1280×1808 固定图两次复用的请求总耗时为 2159ms / 1724ms，另一次与正常阅读请求排队重叠，不能纳入单图性能比较。正常阅读日志中的复用处理约 1.4–1.6 秒，图片内容及负载不同，不能直接计算相对旧版的整图加速百分比。后台/压力/退出等正常释放仍会产生下一次冷加载。临时诊断入口在测试结束后删除，最终 HAP 的字节码确认不含测试入口或测试授权宿主，已重新安装并启动到手机。

本轮已刷新在线目录，并读取 [ArkTS 语法](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[非 UI ArkTS 检索](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-knowledge-retriever/SKILL.md) 和 [构建修复](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/harmony-build-fix/SKILL.md) 指导。外部临时源码的 LSP 检查超时，主工程 LSP 仍缓存旧 HAR 声明；实际 Release 编译器已通过新的原生接口与调用方，未把 LSP 超时或旧缓存诊断描述为静态检查通过。

图片左上角提示已通过 ArkTS 静态检查和应用构建；临时诊断入口已删除，最终调试 HAP 已使用 Release SDK 构建并安装启动。尚未完成三种阅读模式下两种提示的逐项实机目视确认。已读取在线 [ArkUI 指导](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md) 并浏览其实时布局目录，但进一步请求位置 / Stack 布局参考正文时返回 HTTP 403，布局接口以本机 SDK 检查为准。

参考：上游 [校验实现](https://github.com/wip3l/harmony-book-ai-engine/blob/a1eaedd712b00d8e56a85d576e050df69e646bde/aiengine/src/main/ets/core/reader/ComicColorInference.ets)、[MindSpore CPU FP16 配置说明](https://github.com/mindspore-ai/docs/blob/master/docs/lite/cloud_docs/source_en/infer/runtime_cpp.md)，以及在线 [ArkTS 语法指导](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md) / [构建修复指导](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/harmony-build-fix/SKILL.md)。已查询在线 SDK 技能目录，但其 25 Kit 集合不包含 MindSporeLite；具体接口以安装的 Release SDK 声明和真机结果核对。未验证平板、PC、手表或最低 API 20 设备。
