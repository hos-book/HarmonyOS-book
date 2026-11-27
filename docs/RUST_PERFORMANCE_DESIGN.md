# Rust 性能优化详细设计

日期：2026-11-27  
状态：已按授权实施首批计算内核，后续模块按下方进度推进。  
依据：两轮源码分析及当前工作树中的实际调用链。

## 1. 目标与设计结论

本设计将搜索解析、电子书导入和漫画离线翻译中的高成本计算划分为明确的 Rust 候选模块。目标包括缩短计算等待、减少重复扫描和中间数据分配、改善高负载场景的交互流畅度，并通过设备数据确认内存与能耗变化。

推荐分成三条业务线：

1. **共享文本内核**：覆盖搜索纯规则解析、HTML 编解码、正文清洗，后续按收益扩展至全文扫描。
2. **电子书解码内核**：覆盖 PalmDOC、HUFF/CDIC 解码及现有 KF8 片段重建计算。
3. **漫画翻译原生执行层**：使用 Rust 组织分词、生成和原生推理调用，沿用现有模型与语言路线。

首期建议在搜索纯解析与 HTML 编解码中选择一个明确范围；追求纯计算收益确定性时，可优先选择 MOBI 解码。漫画翻译单独立项，原因是模型输入输出、分词器和生成流程需要完整承接。

收益判断分为三类：

| 标记 | 含义 |
| --- | --- |
| 已确认事实 | 当前源码可直接证明的调用、数据结构或循环行为 |
| 收益推断 | 基于执行方式推导的优化机会 |
| 待实测 | CPU 占比、峰值内存、端到端耗时和能耗变化 |

当前成果包含源码分析、详细设计与第 15 节所列计算内核。加速倍数、帧率、温度和耗电收益均属于待实测项。

## 2. 范围与项目约束

### 2.1 职责分配

| 层级 | 保留或新增职责 |
| --- | --- |
| ArkUI V2 页面 | 用户交互、列表展示、阅读位置、刷新与取消入口 |
| ArkTS 服务 | 网络、源会话、Cookie、数据库、文件授权、业务调度与错误展示 |
| 现有 QuickJS 门面 | 用户脚本执行、任务隔离、执行预算和宿主能力调用 |
| C++ N-API 薄桥 | ArkTS 数据读取、C ABI 调用、结果转换和原生内存释放 |
| Rust 计算模块 | 经确认的纯计算、格式解码与翻译生成流程 |
| 系统与既有原生库 | 排版、图片编解码、音频解码、压缩与模型算子执行 |

业务范围继续保持用户导入书源、现有本地格式、当前翻译语言和现有模型。搜索翻页数量、并发设置、封面补全时机、全文索引和模型替换均列为单独产品决策。

### 2.2 平台与构建

- 最低 HarmonyOS 6.0 / API 20，目标 API 26。
- 复用 `PlatformCompat` 管理新接口；API 20 以上引入的接口按项目约定保留版本判断和旧版本实现。
- 原生输出覆盖当前使用的 `arm64-v8a` 与 `x86_64`。
- 使用经核实的 Release SDK 与匹配 IDE 工具。
- phone、tablet、2in1、wearable 分别按实际能力接入；本设计将手表硬件表现保留为待验证项。
- Rust 工具链版本、目标标准库、链接器和第三方库版本在实现准备阶段确定。
- 签名配置继续由现有机器环境管理。

### 2.3 业务语义

既有源定义、加密存储、登录与 Cookie 隔离、有界脚本执行、阅读字符位置、正文图片标记及章节顺序继续作为接口契约。解析输入输出额度、并发额度和执行期限沿用各调用方已有约定。

用户已于 2026-11-27 授权按本设计开发。当前实现范围、构建结果和后续模块见第 15 节。

## 3. 当前实现与成本来源

本节记录迁移前的调用链和成本分析，已完成的替换范围见第 15 节。

### 3.1 搜索链路

```text
SearchPage.searchSources
  → searchSourceQueue / searchOneSource
  → BookSourceService.searchBooks
  → LocalRuleDispatcher
  → LightSourceBridge.search
  → LightSourceCore.search
  → SearchCoordinator.search
  → 兼容规则或 NativeSourceService
  → 网络 / 规则解析 / QuickJS
  → SearchResult → Book → 分组 → 列表发布
```

当前事实：

- `SearchPage` 从偏好读取搜索并发数，以共享队列执行各书源。
- 同一源返回新结果后，下一页进入队尾；出现零条新结果时结束该源翻页。
- 去重使用 `sourceUrl + bookUrl`；随后执行匹配、类型过滤与分组。
- 列表结果采用约 120ms 的合并发布，滚动期间已有延后处理。
- 详情补封面有独立队列，当前最大活动数为 3，单批最多加入 12 项，待处理队列上限为 96。
- `LightSourceCore` 为当前源创建 `SearchCoordinator(1)`；全局并发来自页面层。
- 规则路径涉及定义序列化、结果 JSON 编解码、纯解析任务和脚本任务。

因此，搜索总耗时同时包含网络、翻页、排队、计算和 UI 提交。并发会让若干阶段重叠，阶段耗时应结合时间线解释。

### 3.2 纯规则解析

`LightNativeParserService` 已把解析提交到 taskpool，同时通过静态 Promise 链串行处理任务。当前排队数限制为 16，输入限制为 `8 * 1024 * 1024` 个字符串代码单元；该额度由现有代码的 `string.length` 判断。

`LightNativePureParser` 提供 `items`、`select`、`expression` 三类任务，内部使用 `AnalyzeRule`、`JsonPathEvaluator` 和 `NativeExpr`。输出同样受现有字符串长度额度约束。

收益推断：大型响应、复杂选择器和多源集中返回时，单项解析计算可能延长队列等待。Rust 内核优先缩短单项执行；并发调整独立评估内存与总吞吐。

### 3.3 HTML 编解码与脚本重放

`LightSourceHtmlCodec` 使用 WebView DOM 完成实体编码和解码。`LightSourceSandbox.evaluate` 收集待处理的编解码请求、补充结果，再次执行脚本。

现有循环同时受 64 次迭代和约 10 秒总期限限制；单次 QuickJS 执行继续受原有门面预算约束。

收益分为两层：

- 将 HTML 编解码移入 Rust：减少对应 WebView 调用和就绪等待。
- 在有界 QuickJS 内提供固定原生编解码函数：进一步减少该类请求引起的脚本重放。

第二层涉及 QuickJS 原生绑定，已按授权独立实施，结果见第 15 节。

### 3.4 本地文本与电子书

- `LocalBookHtmlText` 通过若干次替换完成正文抽取、实体处理、换行和空白整理。
- `LocalImport` 的 EPUB 图片路径会先生成占位符，再逐项替换为正式图片标记。
- `EpubXml` 将文本追加到当前栈中各级祖先节点，深层结构会放大文本累计工作。
- `MobiBookParser` 的 PalmDOC 解码包含逐字节判断与回溯复制。
- `MobiHuffDecoder` 包含位读取、码表查询、词典展开与输出复制。
- 当前源码已存在 HUFF/CDIC 和 KF8 调用路径；本设计以这些实际路径为分析依据，具体格式交付范围在实现时与有效产品约定对齐。

### 3.5 漫画翻译

`comic_offline/engine.js` 当前配置 WASM 单线程，并按区域、短段顺序调用翻译模型。日译中和韩译中分别经过英语中转；英语与中文之间采用单段模型。

ArkTS 通过 WebView 启动任务，并每隔约 100ms 查询结果。系统 OCR 与译文回填由 `ComicTranslationService` 负责，已有 `ocrMs`、`modelMs`、`renderMs` 分段日志。

收益推断：切换原生推理后端、减少 Web 调用和整合生成过程，可能改善高耗翻译场景。实际结果取决于模型算子、线程策略和设备能力。

## 4. 总体架构

```text
现有页面 / Service
        │
        ├─ 搜索与正文处理 → 现有后台任务 → 文本原生桥 → Rust text_core
        ├─ MOBI 导入      → 现有导入任务 → 解码原生桥 → Rust ebook_core
        └─ 漫画翻译      → 翻译工作线程 → 翻译原生桥 → Rust translation_core
                                                           │
                                                     原生推理库

用户脚本 → LocalRuleQuickJsRuntime → 有界 QuickJS
网络 / Cookie / 文件授权 / 数据库 → 现有宿主服务
```

建议的代码归属如下，均为拟新增位置：

| 位置 | 内容 |
| --- | --- |
| `native/rust/Cargo.toml` | 项目自有 Rust workspace |
| `native/rust/text_core/` | 编解码、正文处理、选定规则解析与全文扫描 |
| `native/rust/ebook_core/` | PalmDOC、HUFF/CDIC 和选定片段重建算法 |
| `native/rust/translation_core/` | 分词、生成与原生推理调用 |
| `entry/src/main/cpp/rust_bridge/` | C ABI 与 N-API 适配 |
| `entry/src/main/cpp/types/` | 对应模块的 ArkTS 类型声明 |
| `scripts/build-rust.ps1` | 经确认后增加的目标平台编译入口 |

各 Rust 模块按选定阶段逐项建立。翻译模型依赖只归属于翻译模块；文本与电子书模块保持各自的轻量依赖范围。

Rust 以静态库供 C++ 桥链接，应用继续通过既有 N-API 形式加载 `.so`。首次链接时需要核实 Release SDK、最低 API、CPU 架构与运行时依赖的组合。

## 5. 跨语言接口契约

### 5.1 接口粒度

采用“一个业务计算批次一次调用”的方式：

- 搜索解析：一份响应正文和一组字段规则。
- 正文清理：一组章节片段。
- MOBI：同一解码任务中的一批记录。
- 全文搜索：一章正文及该章剩余结果额度。
- 白边识别：一张已缩放图片。
- 音频转换：一段 PCM。

Rust 返回最终数据或紧凑结果；源会话、页面对象和框架状态继续留在 ArkTS。

### 5.2 文本与字符位置

ArkTS 可见的位置统一使用 UTF-16 代码单元偏移，包括搜索命中、图片标记和正文位置。

- 文本接口由 N-API 接收 UTF-16 文本或文本数组。
- 位置敏感的算法保留 UTF-16 输入与返回位置的对应关系。
- 某个第三方算法使用 UTF-8 时，转换层负责把结果位置映射回 UTF-16。
- 现有正文清洗、实体转换和简繁处理的顺序按调用配置保留。
- 字符串长度额度继续使用原调用方的计量单位；二进制长度明确使用字节数。

清洗接口与全文扫描接口分别返回各自业务所需的位置。只有现有功能依赖源位置时，接口才附带源文本到结果文本的映射。

### 5.3 二进制数据与所有权

拟采用以下 C ABI 数据约定：

| 数据 | 传递方式 | 生命周期 |
| --- | --- | --- |
| 输入字节 | 指针与长度 | 当前调用期间借用 |
| 输入文本 | UTF-16 指针与长度 | 当前调用期间借用 |
| Rust 输出 | 明确类型的结果结构与长度 | 桥层转换完成后调用对应释放函数 |
| 字典、生成器等任务对象 | 当前任务拥有的原生对象 | 任务结束时释放 |
| 失败结果 | 状态及原有业务错误映射 | 返回到现有调用链处理 |

C ABI 使用固定宽度数值和显式长度字段。Rust 内部对象通过配套构造、调用和释放入口管理；C++ 桥负责在所有既有完成路径释放资源。

输入缓冲在本次原生调用结束前保持有效。首期输出通过桥层转换为 ArkTS 对象或缓冲，实际复制次数作为性能分析项；直接共享输出缓冲列为测量后的后续选择。

### 5.4 后台执行与取消

- 文本解析沿用 taskpool 入口。
- MOBI 沿用导入任务的业务串行顺序。
- 翻译由独立工作线程承接原生同步推理。
- 当前取消信号在提交批次前、批次结束后和结果发布前继续生效。
- 仅有任务边界取消的接口，明确其在途计算完成后响应取消的特征。
- QuickJS 中的编解码内核沿用现有执行预算；长循环需要接入已有取消或期限检查，才能维持当前门面语义。

首期保持既有队列并发配置，分别记录任务等待和实际计算时间。线程数调整作为单独参数决策，兼顾峰值内存、吞吐和能耗。

## 6. 搜索与共享文本内核

### 6.1 纯规则解析

拟定接口：

| 接口 | 输入 | 输出 |
| --- | --- | --- |
| `selectBatch` | 正文、基础 URL、已支持的规则类型、字段规则数组 | 按字段顺序返回字符串或列表 |
| `extractItems` | 正文、基础 URL、列表规则 | 与现有元素提取语义对应的列表 |
| `cleanTextBatch` | 正文片段数组、调用配置 | 同序正文数组及现有业务所需信息 |
| `htmlCodec` | encode/decode 操作与文本 | 编解码结果 |

接入顺序：

1. 在 `LightNativeParserService → LightNativeParserWorker` 的后台边界增加 Rust 适配。
2. 依据 `NativePureRule` 和实际使用情况，列出本阶段支持的规则语法。
3. 将已确认语法交给 Rust；其他规则继续由现有解析器负责。
4. 保持字段类型、列表顺序、相对 URL 处理、变量语义及空值行为。
5. 完成纯解析后，再决定兼容源的列表提取与字段批次接入范围。

初期 `expression` 继续使用现有 `NativeExpr`。CSS、XPath、JSONPath 与正则分别形成支持清单，具体库选型在语法兼容性评估后确定。

规则求值失败继续返回该次业务失败。解析器选择在执行前依据已确认能力完成。

现有上游托管文件通过 `scripts/sync-light-source.cjs` 和项目适配层更新；Rust 调用优先接在宿主接口。上游同步后，宿主接口继续作为维护边界。

### 6.2 HTML 编解码分两步实施

**第一步：替换计算位置。**

`LightSourceSandbox` 继续使用现有请求重放流程，`html-encode` / `html-decode` 的处理器改为调用后台 Rust 编解码。其他字符集解码继续使用现有 TextDecoder。

该步骤主要减少 HTML 编解码的 WebView 往返与就绪等待，重放次数保持原机制。

**第二步：在有界 QuickJS 中直接调用固定函数。**

通过现有 QuickJS HAR 的原生绑定提供固定 HTML 字符串函数。调用仍由 `LocalRuleQuickJsRuntime.execute()` 进入，固定回调由当前后台线程调用 Rust，结果直接回到当前脚本调用栈。

该步骤可以减少对应 HTML 请求引起的重放。网络、存储、Cookie 和平台服务继续通过现有宿主入口执行。

当前两步均已完成，正式实现使用第二步。QuickJS 与应用回调之间通过 JSON 字符串协议保留 UTF-16 内容；4 MiB 代码单元输入额度继续生效，Rust 每隔约 2048 个代码单元检查当前剩余期限。字符集 TextDecoder 请求继续采用原有重放流程。

兼容重点：命名实体、数字实体、转义顺序、文本编码、`div.textContent → innerHTML` 与 `textarea.innerHTML → value` 的既有语义。原生函数按这些语义定义实现范围。

### 6.3 正文清理

为调用点定义明确配置：

| 配置 | 原入口 | 保留语义 |
| --- | --- | --- |
| 本地 HTML 正文 | `LocalBookHtmlText.clean` | body 提取、块换行、表格间隔、实体处理顺序和空白归并 |
| 在线章节正文 | `OnlineTextPaginator` 文本准备 | 当前换行、清理与阅读字符位置约定 |
| EPUB 元数据 | `EpubXml` | 元素、属性、导航文本与当前消费字段 |
| EPUB 图片正文 | `LocalBookImportService.epubBody` | 图片标记顺序、正文位置与章节关联 |

实现方式：在一次遍历中累计正文片段、块级分隔和图片占位结果，结束时统一生成目标文本。图片文件获取仍由宿主完成，Rust 只使用已经确定的标记数据。

XML 路径先梳理 `EpubParserService` 的实际字段消费，再选择事件式提取或精简节点树。祖先文本按业务需要生成，以减少重复保存。

### 6.4 搜索页面继续保持的行为

- 并发值来自现有设置。
- 下一页进入现有队列。
- 去重、搜索模式、类型过滤和分组语义保持当前实现。
- 列表继续按现有合并发布与滚动策略刷新。
- 封面预取与详情补全维持现有范围。

搜索排序、分组迁移留作第二优先候选。它们需要以结果规模和实际 CPU 占比证明收益。

## 7. MOBI 解码内核

### 7.1 职责

ArkTS 保留文件 URI 授权、记录读取、封面与图片持久化、导入进度及章节写入。Rust 承接已确认格式的字节解码、字典展开和片段重建。

当前代码限制为单文件 128 MiB、展开正文 32 MiB；HUFF 字典另有 32 MiB 额度。接口继续传递现有任务所需额度与记录容量，沿用既有业务错误。

### 7.2 接口

| 操作 | 输入 | 输出 |
| --- | --- | --- |
| 创建解码任务 | 压缩类型、记录容量、所需字典记录 | 本任务解码对象 |
| 解码记录批次 | 按文件顺序排列的压缩记录 | 同序解码数据和记录边界 |
| 重建 KF8 片段 | 已读取的索引、骨架和片段数据 | 按现有规则排列的正文片段 |
| 结束任务 | 本任务解码对象 | 释放字典与缓冲 |

PalmDOC 和 HUFF 分项接入，KF8 根据确认的产品范围衔接。字典在同一次导入任务内复用，任务结束时释放。

### 7.3 数据流

```text
现有文件读取 → 记录批次 → Rust 解码 → 现有文本编码处理
             → 正文清理 → 章节组装 → 现有持久化
```

分批大小以当前记录容量和现有任务内存额度确定。正文逐批交给现有 `consume` 回调，导入进度继续使用原有记录进度。

### 7.4 收益与观察

主要观察解码 CPU 时间、导入总时间、临时缓冲峰值及字典展开成本。图片处理和章节写入单独计时，明确它们在总耗时中的占比。

该模块算法边界清楚，是首个 Rust 模块的备选优先方案。

## 8. 漫画翻译原生执行层

### 8.1 原有业务契约

- 使用已安装的本地模型。
- 沿用 `ja-zh`、`ko-zh`、`en-zh`、`zh-en` 四种方向。
- 日语、韩语先转英语，再转中文。
- 输入保持区域 ID 与文本，输出保持相同区域 ID 和顺序。
- 现有区域数、文本长度、生成长度与会员任务有效性继续由当前业务约定控制。
- OCR 和译文回填继续由现有服务执行。

### 8.2 Rust 与原生推理库分工

Rust 负责：

1. 加载当前模型所需分词配置和词表。
2. 按现有短段规则拆分文本。
3. 生成模型要求的输入张量。
4. 调用原生 encoder/decoder 等实际模型组件。
5. 按现有生成参数进行 token 生成与终止判断。
6. 解码文本并还原区域结果。

原生推理库负责模型算子。优先评估现有 ONNX Runtime 依赖的可复用程度；实际导出接口、模型格式和目标平台能力在实施前核实。

当前模型生成参数包括 `max_new_tokens=256`、`num_beams=1`、`do_sample=false`。移植时同步核对 tokenizer 特殊 token、模型配置中的生成起止规则及输出处理。

### 8.3 调用契约

`translateRegions` 输入方向、区域数组及当前任务需要的模型位置，输出同序区域译文。ArkTS 继续检查会员任务有效性并使用现有取消流程。

原生工作线程执行完整翻译任务，完成后通过工作线程消息返回结果。现有页面只接收业务状态与译文。

模型对象按现有工作线程寿命和当前模型保留策略管理。首期保持逐段生成，优先建立原生链路；批量推理与线程参数在实际模型表现确认后单独选择。

### 8.4 待确认事项

| 项目 | 实施前需要明确的内容 |
| --- | --- |
| 模型结构 | 文件组成、输入输出名称、动态维度和缓存张量 |
| 分词器 | 词表、归一化、特殊 token 与解码规则 |
| 原生运行库 | 当前包的可用接口、许可证与 ABI |
| 设备能力 | API 20、API 26 和两种架构的实际运行情况 |
| 中途取消 | 所选后端的执行中断能力及现有任务取消语义 |
| 数值差异 | 原生后端产生的 token 选择与实际译文表现 |

模型直译路线、量化版本及 GPU/NPU 后端均作为单独选择项。首期使用现有模型与 CPU 路线完成收益归因。

## 9. 后续计算候选

### 9.1 全文扫描

保留 `ReaderFullTextSearch` 的逐章读取、500 条结果上限、进度回调和取消行为。Rust 按章接收正文、关键词、章节索引和剩余结果数，返回命中偏移及摘要。

当前搜索保留重叠命中，Rust 沿用该语义。摘要仍按现有前后文范围和空白归并方式生成，偏移使用 UTF-16。

正文读取留在现有服务。全文索引与全文常驻内存属于独立产品方案。

### 9.2 漫画白边检测

继续由 ImageKit 读取图片，并按当前最长边 768 的规则缩放。Rust 接收 RGBA 缓冲、宽高，返回归一化裁剪框。

保留当前颜色阈值、透明像素处理、每边最多 25% 裁剪和两像素余量。调用放在现有后台任务中。

观察时分别记录解码、像素读取、扫描时间。图片解码占比决定整页收益空间。

### 9.3 PCM 转 WAV

Rust 内核保留 float PCM 限幅、量化与 WAV 封装函数；本地 TTS Worker 随三个本地模型接入一并移除。

保留采样率、单声道、16-bit PCM、现有舍入方式及输出大小约定。音频后处理函数由 Rust 内核维护。

## 10. 保留现有原生能力的模块

| 模块 | 当前执行方式 | 重点分析方向 |
| --- | --- | --- |
| 音频字幕 | sherpa-onnx 与原生音频解码 | 模型初始化、推理和音频传递 |
| EPUB ZIP 解压 | 系统 zlib | 条目读取、正文解析和缓冲分配 |
| CBA | 现有原生 ACE 解码器 | 业务批次与输入输出路径 |
| 阅读排版 | 系统 graphicsText | 排版次数、构建与字符映射 |
| 漫画着色与超分 | aiengine HAR，含原生像素库 | 取得内部执行分段后选择计算点 |
| 用户脚本 | 有界原生 QuickJS | 脚本准备、桥接与重放次数 |

阅读器在 API 26 的缩进校正中最多执行 8 轮候选排版。针对该路径的优先方案是评估重复排版次数，继续保留系统字体、换行和字符位置语义。

## 11. 实施顺序与阶段交付

### 阶段 A：明确首个业务切片

结合现有诊断数据，选择搜索 HTML 编解码、某一类纯规则解析或 MOBI 解码。交付包括实际调用点、支持语义、接口与对应收益目标。

首期范围由用户确认后实施。该阶段复用已有日志和源码，设备测量按确认范围开展。

### 阶段 B：原生构建与首个模块

建立选定 Rust crate、C ABI、N-API 桥与后台调用，完成 API 20 / API 26 及目标 ABI 的构建接入。交付只包含当前业务切片需要的代码和依赖。

### 阶段 C：共享文本扩展

在首个模块获得实际收益后，扩展正文清洗和选定规则解析。上游适配通过同步脚本维护。全文扫描按实际需要接入。

### 阶段 D：电子书解码

逐项接入 PalmDOC、HUFF/CDIC 和已确认的 KF8 重建范围，保持导入回调、章节写入和图片处理职责。

### 阶段 E：漫画翻译专项

完成分词与生成流程移植、原生推理接入及真实译文检查。其进度独立于文本和电子书模块。

白边检测和 PCM 转 WAV 按测量结果安排，优先级低于主要业务切片。

## 12. 收益确认与验证方式

### 12.1 指标

| 场景 | 主要指标 | 需要拆分的成本 |
| --- | --- | --- |
| 搜索 | 首批有效结果、总搜索时间、滚动响应 | 网络、解析队列、计算、数据转换、列表发布 |
| 正文清洗 | 每批处理时间、峰值内存 | 输入转换、扫描、输出构造 |
| MOBI 导入 | 解码时间、总导入时间 | 读取、字典、解压、清理、图片与写入 |
| 漫画翻译 | 单页耗时、冷启动、连续页耗时 | OCR、模型加载、生成、回填 |
| 全文搜索 | 首批命中、完成时间 | 章节读取、扫描、结果发布 |
| 白边检测 | 单图检测时间 | 图片解码、像素读取、扫描 |
| PCM 转换 | 转换时间与缓冲占用 | 原生调用、量化、结果传递 |

设备、输入规模、书源集合、关键词、缓存状态与模型状态保持明确记录。冷启动与热运行分别观察，耗时与内存、能耗分别解释。

原生计算时间与桥接时间一起纳入评估。只有减少的计算时间大于新增传递成本，业务才获得实际收益。

### 12.2 复用现有诊断

- 搜索使用 `DiagnosticLogService`、`LightSourceTiming` 和现有 Worker 解析日志。
- `quickjs-roundtrip` 包含任务往返，`nativeMs` 表示原生执行器返回的耗时字段，两者分别解释。
- 若阶段日志共享同一个 `startedAt`，记录值表示累计时间，分析时按实际起点计算阶段差值。
- EPUB 使用现有 `cleanMs`、`assembleMs` 和图片处理耗时。
- 漫画翻译使用现有 OCR、模型、回填日志。
- 只有现有信息无法区分目标成本时，再提出具体补充测量点供确认。

### 12.3 功能检查

实现阶段按用户确认范围开展编译与实际业务检查：

- 修改 `.ets` 时使用现有 ArkTS 检查工具，再通过 `build_project` 构建。
- 搜索检查导入源搜索、列表、详情、目录和阅读或播放，以及现有取消与失败隔离行为。
- 阅读相关检查字符位置恢复、字号或窗口变化后的重排、正文图片及安全区。
- MOBI 检查实际导入章节、文字、图片与原有错误显示。
- 翻译检查四种语言路线、区域对应、译文回填与取消后的页面状态。
- 设备结果按手机、平板、2in1、wearable 分别记录。

当前实施已完成原生与应用编译。设备功能与性能测量、测试文件和自动化执行范围以用户明确要求为依据。

## 13. 决策项

| 决策 | 推荐方向 | 原因 |
| --- | --- | --- |
| 首个切片 | 搜索编解码或纯解析；MOBI 解码作为确定性优先备选 | 边界明确，容易观察实际成本 |
| 原生接入 | C++ N-API 薄桥链接 Rust 静态库 | 复用现有原生构建结构 |
| 调度策略 | 首期沿用现有队列与并发 | 便于区分算法与调度收益 |
| 规则覆盖 | 分语法族推进 | 保持导入源实际语义 |
| 翻译模型 | 首期沿用现有模型和路线 | 聚焦执行后端收益 |
| 结果位置 | 统一 UTF-16 偏移 | 对齐现有阅读与搜索行为 |

用户已授权按本设计开发。首批选择 HTML 编解码、正文清洗与 MOBI 解码，同时接入独立的全文扫描、白边检测和 WAV 封装。各阶段的已实施范围见第 15 节。

## 14. 代码与资料依据

### 14.1 本地源码

- [搜索页面](../entry/src/main/ets/pages/SearchPage.ets)
- [书源服务](../entry/src/main/ets/service/BookSourceService.ets)
- [LightSourceBridge](../entry/src/main/ets/service/rulesource/light/LightSourceBridge.ets)
- [LightSourceCore](../entry/src/main/ets/service/rulesource/light/LightSourceCore.ts)
- [SearchCoordinator](../entry/src/main/ets/service/rulesource/light/upstream/core/book/SearchCoordinator.ts)
- [后台解析服务](../entry/src/main/ets/service/rulesource/light/LightNativeParserService.ets)
- [纯解析实现](../entry/src/main/ets/service/rulesource/light/LightNativePureParser.ts)
- [HTML 编解码后台回调](../entry/src/main/ets/service/text/RustTextWorker.ets)
- [脚本宿主](../entry/src/main/ets/service/rulesource/light/LightSourceSandbox.ets)
- [QuickJS 门面](../entry/src/main/ets/service/rulesource/LocalRuleQuickJsRuntime.ets)
- [本地导入](../entry/src/main/ets/service/LocalBookImportService.ets)
- [正文清洗](../entry/src/main/ets/service/text/LocalBookHtmlText.ets)
- [EPUB XML](../entry/src/main/ets/service/text/EpubXml.ets)
- [EPUB 压缩包](../entry/src/main/ets/service/text/EpubArchive.ets)
- [MOBI 解析](../entry/src/main/ets/service/text/MobiBookParser.ets)
- [HUFF 解码](../entry/src/main/ets/service/text/MobiHuffDecoder.ets)
- [KF8 重建](../entry/src/main/ets/service/text/Kf8BookText.ets)
- [全文搜索](../entry/src/main/ets/service/text/ReaderFullTextSearch.ets)
- [分页](../entry/src/main/ets/service/text/OnlineTextPaginator.ets)
- [漫画翻译服务](../entry/src/main/ets/service/ComicTranslationService.ets)
- [离线翻译宿主](../entry/src/main/ets/service/ComicOfflineTranslationService.ets)
- [离线翻译引擎](../entry/src/main/resources/rawfile/comic_offline/engine.js)
- [白边检测](../entry/src/main/ets/utils/ComicWhiteBorderGeometry.ts)
- [字幕 Worker](../entry/src/main/ets/workers/AudioSubtitleWorker.ets)
- [原生构建](../entry/src/main/cpp/CMakeLists.txt)
- [性能说明](PERFORMANCE.md)
- [上游同步约定](LIGHT_SOURCE_SYNC.md)

### 14.2 已读取的在线资料

- [HarmonyOS 技能索引](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/README.md)
- [ArkUI 性能分析技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-performance-analysis/SKILL.md)
- [性能分析交付约定](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-performance-analysis/references/report-contract.md)
- [性能验证指引](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-performance-analysis/references/verification.md)
- [高频工作分析](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-performance-analysis/references/component/frequent-work.md)
- [HarmonyOS SDK 技能路由](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/sdk/hmos-one-sdk-skill/SKILL.md)
- [Rust OpenHarmony 平台说明](https://doc.rust-lang.org/rustc/platform-support/openharmony.html)

在线资料用于技能路由、分析口径与平台方向确认；本机工具链与链接结果见第 15 节，设备性能继续保留为待测项。此前 Context7 查询连接失败，本轮查询返回月度额度提示，Rust 平台资料改用官方页面读取。

## 15. 实施进度（2026-11-27）

### 15.1 已接入业务的功能

| 功能 | 实现与接入 | 当前执行位置 |
| --- | --- | --- |
| HTML 编解码 | Rust 命名/数字实体处理，HTML 字符串编码；QuickJS 固定回调直接返回脚本调用栈 | 当前有界 QuickJS 后台线程 |
| 本地正文清洗 | Rust 标签扫描、段落整理、既有本地实体处理顺序 | 原有批量 taskpool 与调用入口 |
| 全文搜索 | Rust KMP 扫描，保留重叠命中、UTF-16 偏移与 500 条结果上限 | 每章 taskpool |
| 漫画白边 | Rust RGBA 扫描，沿用颜色阈值、裁剪比例和余量 | 原有检测 taskpool |
| TTS WAV 封装 | Rust float PCM 量化和 WAV 封装，沿用 JS 舍入语义 | 原有 TTS Worker |
| PalmDOC 解压 | Rust 字节解码；压缩记录按最多 16 条一批提交 | N-API 异步任务 |
| HUFF/CDIC 解压 | Rust 字典读取和展开，同次导入复用字典 | N-API 异步任务 |
| KF8 重建 | Rust INDX/TAGX 解析与片段跨度组装，章节正文统一复制 | N-API 异步任务 |
| EPUB XML | Rust 元素、属性和文本扫描；节点共用 UTF-16 文本区间 | taskpool |
| EPUB 图片标记 | 一次原生调用内清洗正文并扫描占位前缀，保留首个命中替换和图片顺序 | taskpool |
| TXT 分章 | Rust 跨块保留残行与当前章节，扫描标题并批量返回完整章节 | N-API 异步任务 |
| 阅读预处理 | Rust 正文规范化、段落缩进及 UTF-16 源/展示位置三元组 | 原调用线程，系统继续负责排版 |
| 朗读分句 | Rust 图片占位、符号清理和分句扫描；同章导航复用结果并二分定位 | 原调用线程 |
| 字幕后处理 | Rust 重叠匹配、标点回填、保护词修复、长句拆分与时间线整理 | 原字幕 Worker 与发布入口 |
| 书源批量解析 | 搜索/发现/详情/目录纯 HTML 字段批处理，Rust 同名标签配对与字段间跨度索引共享 | 原有串行 taskpool 队列 |
| 原生构建 | Cargo workspace → Rust 静态库 → C++ N-API → `libhsda_core.so` | CMake 自动执行 |

实际 Rust workspace 为 `text_core`、`ebook_core` 与 C ABI 汇总 crate `hsda_core`。当前 Rust 依赖均为本 workspace 的路径依赖，Cargo 构建使用离线模式。架构覆盖 `aarch64-unknown-linux-ohos` 与 `x86_64-unknown-linux-ohos`。

taskpool 文本任务结果沿用项目已有的字符串协议，以适配当前 ArkTS 编译器的任务池返回类型。全文扫描只传回最多 500 个命中位置，摘要继续由原服务按既有规则生成。TXT 使用 N-API 异步任务，完成后直接返回具有显式类型的章节数组。

HTML 编解码通过本地 QuickJS HAR 的固定函数调用 `RustTextWorker.runBoundedHtmlCodec`，再同步进入 Rust。原 WebView 编解码服务已移除；HTML 请求直接在当前调用栈内取得结果，转换耗时计入当前脚本期限。Rust 编码预先确定输出长度，并在扫描中定期检查期限；TextDecoder 继续沿用原重放。

KF8 接入保留文件记录加载、字符编码和章节消费入口，Rust 负责 INDX/TAGX、骨架和片段重建。片段插入只调整跨度列表，最终每章正文统一分配和复制，沿用原有 32 MiB 正文额度及错误映射。

EPUB 的 container、OPF、nav 和 NCX 解析均经 taskpool 调用 Rust。Rust 按顺序扫描并保存一份解码文本，各节点记录父级、属性和 UTF-16 文本区间；ArkTS 按原 `attr`、`child`、`all` 与 `text` 接口消费。祖先文本按需切片，原有 XML 输入额度、节点数和深度额度继续保留。

EPUB 图片文件获取和保存由宿主完成，后台任务通过 `cleanEpubHtml` 一次进入 Rust，顺序完成正文清洗与正式图片标记填入。中间正文保存在 Rust 缓冲中，省去中途生成 ArkTS 字符串及再次读取 UTF-16 输入的转换。图片占位继续采用一次扫描和首次替换语义。

TXT 沿用 64 KiB 文件读取和当前字符编码检测，解码后的文本按批次交给当前导入专属的 Rust 解析器。后台任务清理 CR、复用残行缓冲、识别既有标题规则并组装章节；只在章节完成时返回标题、正文和整章标记。中文标题字符集、英文 Chapter、序章等固定标题、70 个 UTF-16 单元的标题后缀、标题行保留、32000 字符普通分段及 8 MiB 标题章节额度均沿用现有语义。章节切分与写入继续通过 `appendText` 和当前写入队列执行，末批输入输出余文，导入结束释放解析器。

EPUB ZIP 读取已整合至 `libhsda_core.so` 的 `readEpubEntries`。ArkTS 保留中央目录与条目元数据，按批次向后台原生任务提交文件描述符、文件大小以及条目的偏移、压缩长度、展开长度和压缩方式。任务使用独立文件描述符完成 `pread` 与系统 zlib 解压，再按输入顺序返回条目。正文继续按四章/512 KiB 分批，超大单章独占一批；处理当前批次时预读下一批，原有字符编码、章节顺序、原版主题与样式职责继续保留。

条目参数使用 `number[]` 传递四元组，桥层通过 `napi_get_element` 与数值读取接口逐项提取，再存入原生整数数组。实机曾在 `Float64Array` 内存复制路径读取到 `18446744073709551615` 的异常偏移，导致 37,809,796 字节 EPUB 在预览阶段失败；该路径已替换为显式数值转换。读取范围错误同时包含偏移、长度和文件大小，便于从现有诊断日志定位。

2026-11-27 用户提供的成功导入记录包含 1611 章、37,809,796 字节 EPUB：总耗时 33,044 ms，读取及原版资源/样式阶段 28,383 ms，章节转换 4,605 ms，写入等待 11 ms。批量纯文本清洗统计为 7 ms，含图正文处理计入章节转换。该记录支持优先优化读取链路。

同日 12:05:10，Mate 80 实机完成《黎明之剑》1611 章导入：总耗时 26,415 ms，解析读取 26,403 ms，其中资源读取及原版资源/样式 22,758 ms，章节转换 3,605 ms，写入等待 7 ms，写入活跃 5,599 ms；图片 51 张、复用 2,565 次。相较此前用户记录，总耗时缩短 6,629 ms，约 20%。本次同时确认书名和封面识别恢复；两次记录来自用户先后操作，耗时会受设备运行状态影响。

本地导入闪退已定位至 UTF-16 输出桥接：Rust 空文本返回的指针值为 `0x2`，N-API 扫描结束符时触发非法地址访问。桥层现以带零结束符的 UTF-16 存储和原始文本长度调用 N-API。

### 15.2 构建结果

- 阅读预处理、朗读分句与导航复用、字幕后处理、书源批量字段和 Rust 标签配对已通过 `entry@default` Debug HAP 完整构建，耗时 1 分 46.695 秒，Release SDK 为 26.0.0.105。首轮 ArkTS 编译定位到原生返回值契约的接口声明，修正后整包编译通过。独立检查曾读取到旧原生导出信息，最终以完整构建结果为依据。四项扩展的实机功能、速度、内存和能耗为待测项。

- 本轮 EPUB 单次原生调用与 TXT 流式分章已通过 `entry@default` Debug 完整构建，Release SDK 为 26.0.0.105，耗时 1 分 12 秒。独立 ArkTS 检查返回 LSP 初始化提示，完整构建完成源码编译；这两项改动的实机导入结果、耗时与内存收益待验证。

- 本机独立 Rust 工具链：1.100.0，位于 `D:/soft/rust-1.100.0`。
- 可用目标标准库：arm64 与 x86_64 OHOS。
- 本地 QuickJS HAR Release 构建通过，包含固定 HTML 字符串回调。
- 包含 HTML 直调、KF8、EPUB XML 与图片标记最终修改的应用 `entry@default` Debug 完整构建通过，两个 ABI 的原生库均参与构建。
- SDK 元数据：26.0.0.105，`releaseType=Release`。
- 当前 HAP 元数据：`compileSdkVersion=26.0.0.105`、`apiReleaseType=Release`、`minAPIVersion=60000020`、`targetAPIVersion=260000026`。
- 独立 ArkTS 检查工具曾返回 LSP 初始化提示与旧导出信息；完整应用构建已完成最终源码编译诊断并通过。
- 设备功能、实际书源兼容性、导入结果、翻译表现和能耗尚待执行，当前性能收益仍为设计预期。

### 15.3 后续阶段

本轮四项扩展已接入业务调用。阅读规范化沿用原替换阶段顺序，展示缩进继续映射到原字符坐标。朗读的导航句子与合成批次分别维护，Unicode 字母/数字筛选继续使用现有 ArkTS 规则，替换词和提供方额度保持现有处理。

字幕重叠区先规范化各词元，再通过连续匹配长度复用减少重复扫描；原有时间阈值与候选优先顺序继续生效。保护词、长句拆分及历史缓存 cue 的时间展开统一在 Rust 中执行，识别推理与 token 时间对齐继续留在当前 Worker。

书源一次后台任务最多处理 16 个条目的纯 HTML 字段。各字段独立解析上下文，共享当前条目的元素跨度；结果和错误按原消费位置处理。JSON 对象路径、含表达式或脚本的字段继续沿用原路由。HTML 配对采用 Rust UTF-16 扫描，保持原正则的标签边界、自闭合与栈配对语义。同步补丁为 `host-native-selector-batch-v1`。

| 模块 | 当前状态 | 下一项具体工作 |
| --- | --- | --- |
| CSS/XPath/JSONPath 与表达式 | 已接入批量字段与 Rust 标签配对，语法解释沿用原解析器 | 按真实规则耗时推进下一语法族 |
| 漫画翻译原生执行层 | 继续使用现有 Web Worker 模型链路 | 完成 tokenizer、模型张量与生成 API 接入 |

漫画翻译当前包含可复用的 ONNX Runtime 动态库和 Web 推理资源；原生翻译的分词、张量与生成流程仍需独立实现。本轮交付包含首批计算内核，完整设计的后续阶段继续按此表推进。

### 15.4 阅读、字幕、下载与 EPUB 调度优化

阅读对白范围随现有布局缓存复用，引号配置变化时重新识别；分页以顺序游标分配相交范围，跨页对白继续裁剪为页内偏移。章节标题、图文混排和 UTF-16 原文位置仍由原有布局与坐标映射处理。

字幕沿用识别 Worker，分别持有当前章和下一章的正式块；初始化时装入已有缓存，后续按识别结果增量更新。保护词字典、Rust 时间线整理和 v6 缓存 JSON 生成均在 Worker 完成，主线程接收字幕及已序列化文本。预览只参与展示；正式缓存继续采用原有字符额度与 `.part` 路径，通过异步文件 API 顺序写入。

下载入队筛选和批量章节更新采用批次索引，按原目录位置保留首个匹配项，继续遵循双方 URL 优先、缺少 URL 时按章节 ID 匹配的规则。目录状态变化时生成总数与在途章节位置索引，字节进度更新复用已完成数量并只遍历活动下载；当前章节标题继续按原目录顺序选择。

EPUB 样式缓存保存已解析的选择器、优先级与背景/前景声明，每章仅匹配 body/html/标题元素并应用声明。原版依赖资源每批最多 16 项、512 KiB，大资源独占一批；CSS/SVG 的递归依赖、资源额度、去重及原写入队列继续生效。资源读取时暂存限额内的 CSS，样式读取后释放原字节，跨章复用解析结果。普通 HTML 导入沿用文件读取入口。

2026-11-27，上述四项通过 `entry@default` Debug 完整构建，使用 Release IDE 与 SDK 26.0.0.105，耗时 5 分 8.866 秒，完成 ArkTS 编译、HAP 打包和签名。构建接口于 5 分钟超时，最终结果由同次构建日志的 `BUILD SUCCESSFUL` 确认。独立检查已修正下载进度遍历中的解构语法；阅读及字幕的原生导出提示属于编辑器旧类型信息，完整源码编译已通过。实机功能、耗时和内存收益保留为待测项。

实施指引见 [Rust 内核说明](../native/rust/README.md)。本轮使用的在线编译指导为 [ArkTS 编译修复技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-syntax-checker/SKILL.md)及其 `references/error-fixing-examples.md`，语法与原生加载指导分别来自 [ArkTS 检索技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-knowledge-retriever/SKILL.md)及其 linter 规则摘要、[N-API 加载指导](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-napi-side-effect-fixer/SKILL.md)。指导已用于实现与编译修复，设备性能流程保留为待执行项。

### 15.5 全网榜单后台解析与滚动更新

`RankingParser.parse` 将平台 ID、榜单 ID 和响应原文提交到 `parseRanking` 原生异步任务。Rust `ranking_core` 处理起点、懒人听书、喜马拉雅、七猫、晋江、番茄、飞卢、腾讯漫画与哔哩哔哩漫画的既有解析规则；缓存输入连同时间字段在后台解码，沿用 2 MiB UTF-16 正文额度、30 天缓存有效窗口和原有平台条数限制。番茄字表由既有资源传入。N-API 一次返回书籍字段，ArkTS 创建可观察模型，网络、存储和版本匹配继续由原服务负责。

首页榜单字段以 V2 观察更新，列表条目标识使用榜单 ID。顶部连续滚动位置由三个局部组件消费，页面保留阈值状态。横向货架渲染窗口按跨卡片边界更新；封面、圆角和阴影作为静态绘制组，外层承担几何变换。惯性逐帧位置继续支持即时手指接管和焦点反馈。实际设备帧耗时、绘制开销与内存收益待测。

2026-11-27：Rust arm64 编译检查与 `entry@default` Debug 完整构建通过，构建使用 Release SDK 26.0.0.105，最终增量构建耗时 1 分 3.012 秒。独立 ArkTS 检查服务超时，完整构建完成 ArkTS、C++、Rust 与资源编译。设备交互和性能收益保留为待验证项。
