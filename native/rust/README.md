# Rust 计算内核

当前 workspace 由项目自有 `text_core`、`ebook_core`、`ranking_core` 和 C ABI 汇总库 `hsda_core` 组成。榜单解析使用固定版本 `regex` 与 `json`，许可证见应用资源 `rawfile/third_party/rust-ranking/LICENSES.txt`。

## 构建

本机工具链为 Rust 1.100.0，目录 `D:/soft/rust-1.100.0`。安装目标标准库：`aarch64-unknown-linux-ohos` 和 `x86_64-unknown-linux-ohos`。

应用构建通过 `entry/src/main/cpp/rust_bridge/CMakeLists.txt` 自动运行 Cargo，输出进入当前 CMake 构建目录。设置 `HSDA_RUST_HOME` 可指定工具链；常规 Cargo 安装使用用户目录下的 `.cargo/bin`。

单独构建两个目标：

```powershell
./scripts/build-rust.ps1 -ToolchainHome D:/soft/rust-1.100.0
```

静态库进入 `entry/build/rust-native`。应用原生桥链接 Rust 静态库与现有 N-API，最终模块为 `libhsda_core.so`。

## 接入

| 功能 | 业务入口 | 执行位置 |
| --- | --- | --- |
| HTML 编解码 | `LocalRuleQuickJsRuntime.ets` / `RustTextWorker.ets` | 当前有界 QuickJS 后台线程的固定回调 |
| 正文清洗 | `LocalBookHtmlText.ets` / `LocalBookHtmlWorker.ets` | 沿用调用方和现有批量 taskpool |
| 全文扫描 | `ReaderFullTextSearch.ets` | 每章一个 taskpool 任务 |
| 白边检测 | `ComicWhiteBorderWorker.ets` | 原有 taskpool |
| MOBI 解压 | `MobiBookParser.ets` / `MobiHuffDecoder.ets` | N-API 异步任务，每批最多 16 条记录 |
| KF8 重建 | `Kf8BookText.ets` | N-API 异步任务，扫描 INDX/TAGX 后统一组装正文 |
| EPUB XML | `EpubXml.ets` / `EpubParserService.ets` | taskpool 扫描，节点共享文本及 UTF-16 区间 |
| EPUB 图片正文 | `LocalBookImportService.ets` / `LocalBookHtmlWorker.ets` | taskpool 内一次原生调用完成正文清洗和图片标记组装 |
| TXT 分章 | `LocalBookImportService.ets` | 每次导入独立的 Rust 流式解析器，按读取批次执行 N-API 后台任务 |
| 阅读预处理 | `OnlineTextPaginator.ets` | 原调用线程中的 Rust 正文规范化、段落缩进和位置映射 |
| 朗读分句 | `SpeechTextSegmenter.ets` / `TextToSpeechService.ets` | Rust 字符扫描与符号清理，同章导航复用分句结果 |
| 字幕后处理 | `AudioSubtitle.ets` | 原 Worker 中匹配重叠文字和标点，发布时由 Rust 生成展示时间线 |
| 书源批量解析 | `LightNativePureParser.ts` | 原 taskpool 中按批次提取字段，Rust 配对 HTML 同名标签 |
| 全网榜单解析 | `RankingParser.ets` / `RankingService.ets` | N-API 异步任务解析 HTML、JSON 和原始缓存记录，直接返回书籍字段 |

文本使用 UTF-16；全文命中继续返回 UTF-16 代码单元偏移。C ABI 输出通过桥层转换后由配套函数释放。HUFF 字典由单次导入拥有，导入结束释放；原生最终释放器承接对象生命周期。

HTML 编解码已接入本地 QuickJS HAR 的固定字符串回调，Rust 在当前后台线程执行，HTML 请求直接返回当前脚本调用栈。TextDecoder 字符集解码继续使用既有重放。回调使用 JSON 字符串协议保留 UTF-16 内容，输入额度沿用 4 MiB 代码单元，转换耗时计入当前脚本期限，Rust 扫描每隔约 2048 个代码单元检查期限。编码输出按实际长度预分配。

CSS/XPath/JSONPath 的语法解释、原生表达式和漫画翻译生成流程继续使用原有实现。纯 HTML 字段按最多 16 项一批提取，每项的字段共用标签跨度索引，各字段仍独立持有解析上下文；Rust 扫描沿用原引擎的同名标签匹配规则。搜索、发现、详情和目录已接入，JSON 对象与表达式字段继续使用现有分流。宿主适配通过 `scripts/light-native-selector-batch.cjs` 和 `scripts/sync-light-source.cjs` 生成。

阅读规范化保留原有 HTML 检测、分阶段清洗、实体处理顺序和空行规则。`indentReaderText` 返回展示文本与源起点、正文起点、展示起点三元组，系统排版继续使用 `graphicsText`。

朗读分句保留图片等长空白、UTF-16 代理对、词间边界、尾部标点和自然段坐标。Unicode 字母/数字判定沿用 ArkTS 正则；合成替换、起读策略和提供方批次额度沿用现有逻辑。当前章的导航分句按需生成并复用，换章或清空正文时释放；句子定位使用二分查找。

字幕重叠匹配在 Rust 中预先规范化词元并复用连续匹配长度，保留 2 秒上下文、600 毫秒对齐阈值及原选择顺序。标点回填、保护词修复、长句拆分与时间线整理接入同一内核；识别推理、token 时间对齐、缓存读取和发布时间保持现有职责。保护词字典由原生对象持有，N-API 最终释放器管理生命周期。

KF8 使用跨度列表表示骨架及插入片段，完成所有插入后统一复制各段正文；原有字符编码、章节顺序、32 MiB 正文额度和错误类型继续保留。EPUB 使用 Rust 顺序扫描，输出共享文本及节点的属性、父级和文本区间，ArkTS 继续提供现有 `attr`、`child`、`all` 与 `text` 读取方式。元数据输入、节点数和深度沿用原有额度。

EPUB 图片由宿主读取和保存。`cleanEpubHtml` 在一次原生调用内完成正文清洗，再根据当前章节的占位前缀扫描文本并填入正式图片标记，保持每个占位的首次替换语义及图片顺序。中间正文直接留在 Rust 缓冲中，最终结果统一转换为 ArkTS 字符串。

TXT 沿用 64 KiB 文件读取与现有字符编码检测。`createTxtImporter` 创建当前导入专属的解析器，`feedTxtImporter` 在原生后台任务中处理解码后的 UTF-16 文本，保留跨块残行和当前章节，完成的章节直接返回标题、正文及整章保存标记。Rust 沿用中文数字章节、英文 Chapter 和序章等标题规则、CR 清理、标题行正文、32000 字符普通分段与 8 MiB 标题章节额度；末批输入完成余文输出。ArkTS 继续通过 `appendText` 与当前写入队列保存章节，导入结束释放解析器。

EPUB ZIP 读取通过同一原生模块的 `readEpubEntries` 执行：每批条目在一个 N-API 后台任务中使用 `pread` 和系统 zlib 完成读取与解压，任务独立持有文件描述符。正文按四章/512 KiB 分批，超大单章独占一批；导入器处理当前批次时提前读取下一批。字符集解码、目录装配及原版资源保存继续由原服务负责。

条目描述符采用 `number[]`，每四项依次为文件偏移、压缩长度、展开长度、压缩方式，桥层通过 N-API 逐项提取整数。此路径替代 `Float64Array` 底层内存复制，修复实机读取到异常资源偏移而导致 EPUB 识别失败的问题。

Rust UTF-16 输出经桥层复制到带零结束符的存储，再按原始长度创建 ArkTS 字符串；空正文同样提供有效的字符串存储。

## HTML 实体数据

`text_core/src/entities.rs` 由 `scripts/generate-rust-html-entities.py` 从 WHATWG HTML 命名字符引用数据生成，包含 2231 项。原始来源为 `https://html.spec.whatwg.org/entities.json`，协议与署名见应用内 `rawfile/third_party/whatwg/NOTICE.txt`。

## 当前验证

2026-11-27 榜单优化：`ranking_core` arm64 编译检查通过，包含榜单后台解析、首页局部滚动状态与货架窗口更新的 `entry@default` Debug 完整构建通过。使用 Release SDK 26.0.0.105，最终构建耗时 1 分 3.012 秒。独立 ArkTS 检查服务超时；完整构建完成 ArkTS、原生库、资源和签名。真实榜单兼容性、双向滑动和帧耗时待设备验证。

2026-11-27 本轮扩展：阅读预处理、朗读分句与导航复用、字幕后处理、书源批量字段与 Rust 标签配对已通过 `entry@default` Debug HAP 完整构建，耗时 1 分 46.695 秒，使用 Release SDK 26.0.0.105。首轮编译提示四处 `implements` 的契约声明需要使用接口，修正后完整构建通过。编译保留项目现有的平台能力、异常处理与 AI HAR sourceMapsPath 告警。验证范围为源码审阅和编译，实机功能、耗时与内存收益待测。

2026-11-27 本轮：EPUB 单次原生调用与 TXT 流式分章已通过 `entry@default` Debug 完整构建，构建使用 Release SDK 26.0.0.105，耗时 1 分 12 秒。独立 ArkTS 检查返回 LSP 初始化提示，完整构建完成 ArkTS、C++ 和 Rust 编译。两项改动的实机导入结果、耗时和内存收益待验证。

2026-11-27：QuickJS HAR Release 构建通过；包含 HTML 直调、KF8、EPUB XML 和图片标记组装的应用 Debug 完整构建通过。使用 Release SDK 26.0.0.105，覆盖 arm64-v8a 与 x86_64 原生模块。设备功能、真实书源兼容性、速度与能耗为待执行项。ArkTS 独立检查曾返回 LSP 初始化提示及旧导出信息，完整构建已完成最终源码的编译诊断。
