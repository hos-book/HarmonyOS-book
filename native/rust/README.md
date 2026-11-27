# Rust 计算内核

当前 workspace 由项目自有 `text_core`、`ebook_core` 和 C ABI 汇总库 `hsda_core` 组成。Rust 侧依赖均为本 workspace 的路径依赖。

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
| EPUB 图片正文 | `LocalBookImportService.ets` / `LocalBookHtmlWorker.ets` | taskpool 清洗正文及一次扫描组装图片标记 |

文本使用 UTF-16；全文命中继续返回 UTF-16 代码单元偏移。C ABI 输出通过桥层转换后由配套函数释放。HUFF 字典由单次导入拥有，导入结束释放；原生最终释放器承接对象生命周期。

HTML 编解码已接入本地 QuickJS HAR 的固定字符串回调，Rust 在当前后台线程执行，HTML 请求直接返回当前脚本调用栈。TextDecoder 字符集解码继续使用既有重放。回调使用 JSON 字符串协议保留 UTF-16 内容，输入额度沿用 4 MiB 代码单元，转换耗时计入当前脚本期限，Rust 扫描每隔约 2048 个代码单元检查期限。编码输出按实际长度预分配。

CSS/XPath/JSONPath、原生表达式和漫画翻译生成流程继续使用原有实现。

KF8 使用跨度列表表示骨架及插入片段，完成所有插入后统一复制各段正文；原有字符编码、章节顺序、32 MiB 正文额度和错误类型继续保留。EPUB 使用 Rust 顺序扫描，输出共享文本及节点的属性、父级和文本区间，ArkTS 继续提供现有 `attr`、`child`、`all` 与 `text` 读取方式。元数据输入、节点数和深度沿用原有额度。

EPUB 图片仍由宿主读取和保存。正文清洗后，Rust 根据当前章节的占位前缀一次扫描文本并填入正式图片标记，保持每个占位的首次替换语义及图片顺序。

EPUB ZIP 读取通过同一原生模块的 `readEpubEntries` 执行：每批条目在一个 N-API 后台任务中使用 `pread` 和系统 zlib 完成读取与解压，任务独立持有文件描述符。正文按四章/512 KiB 分批，超大单章独占一批；导入器处理当前批次时提前读取下一批。字符集解码、目录装配及原版资源保存继续由原服务负责。

条目描述符采用 `number[]`，每四项依次为文件偏移、压缩长度、展开长度、压缩方式，桥层通过 N-API 逐项提取整数。此路径替代 `Float64Array` 底层内存复制，修复实机读取到异常资源偏移而导致 EPUB 识别失败的问题。

Rust UTF-16 输出经桥层复制到带零结束符的存储，再按原始长度创建 ArkTS 字符串；空正文同样提供有效的字符串存储。

## HTML 实体数据

`text_core/src/entities.rs` 由 `scripts/generate-rust-html-entities.py` 从 WHATWG HTML 命名字符引用数据生成，包含 2231 项。原始来源为 `https://html.spec.whatwg.org/entities.json`，协议与署名见应用内 `rawfile/third_party/whatwg/NOTICE.txt`。

## 当前验证

2026-11-27：QuickJS HAR Release 构建通过；包含 HTML 直调、KF8、EPUB XML 和图片标记组装的应用 Debug 完整构建通过。使用 Release SDK 26.0.0.105，覆盖 arm64-v8a 与 x86_64 原生模块。设备功能、真实书源兼容性、速度与能耗为待执行项。ArkTS 独立检查曾返回 LSP 初始化提示及旧导出信息，完整构建已完成最终源码的编译诊断。
