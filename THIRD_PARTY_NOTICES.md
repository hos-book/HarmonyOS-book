# 第三方软件声明

## Petrel 删除消散效果

- 上游：https://github.com/miramira8295/Petrel ，固定提交 `ed218f4559cf083b51b08c5bf0bb27ea6215cbb9`，作者 miramira8295 与 Petrel contributors，Apache-2.0。
- `RecordDissolveEffect.ets` 与 `entry/src/main/cpp/record_dissolve/` 改编上游 `ShatterCanvasFallback.ets`、`shatter_renderer.cpp/.h`、`shatter_geometry.h`、`shatter_shaders.h`。保留随机切块、波前、运动和淡出算法，使用 ArkUI V2 单行截图、后台像素准备、NativeVSync 与 OpenGL ES 3 实例化绘制。修改包括独立 NAPI 模块、颗粒预算、截图/渲染超时、轻量淡出回退、自动高度书卡、屏内批量删除、窗口变化/离页清理及每次完成时的绘制耗时汇总。
- 完整许可证随 HAP 保存在 `rawfile/third_party/petrel/LICENSE.txt`，来源与修改说明见同目录 `NOTICE.txt`。

## CBA / ACE 漫画解码

- 算法来源：https://github.com/droe/acefile ，固定提交 `11ed076ae19e8228148731cfbc05f019a395b3b9`。
- Copyright (c) 2017-2026, Daniel Roethlisberger and contributors，BSD-2-Clause。
- `entry/src/main/cpp/ace/` 为 BitStream、Huffman、LZ77、DELTA、EXE、SOUND、PIC 算法的有界 C++ 移植，增加应用容器校验、固定输出路径及容量/时限控制；应用不含 Python 运行时。
- 完整许可证保留于该目录 `LICENSE`，同时随 HAP 保存在 `rawfile/third_party/acefile/LICENSE.txt`。

## 有声书端侧字幕

- 成语边界保护词库使用 [pwxcoo/chinese-xinhua](https://github.com/pwxcoo/chinese-xinhua) 的成语词条，MIT 许可，固定提交 `fe6d6c2e8baa82187f4c96bbe042e43f96c05666`；仅提取并去重 30,345 条中文成语，不含释义。来源、转换方式、SHA256 和许可全文随应用保存在 `rawfile/audio_subtitles/IDIOMS-NOTICE.txt`、`LICENSE.idioms.txt`。

- CT-Transformer 中英文标点恢复 int8 模型（FunASR / sherpa-onnx，Apache-2.0），随包内置约 72 MiB；官方发布版本 `2024-04-12-int8`。来源、模型 SHA256 与许可全文见 `rawfile/audio_subtitles/PUNCTUATION-NOTICE.txt`、`LICENSE.punctuation.txt`。

- sherpa-onnx 官方 HarmonyOS HAR 1.13.3：Apache-2.0，来源 https://github.com/k2-fsa/sherpa-onnx/tree/v1.13.3/harmony-os 。HAR 内 ONNX Runtime 库版本字符串为 1.16.3，许可证 MIT。
- 中文 Zipformer CTC int8 模型由 csukuangfj 发布，Apache-2.0；固定版本 `824c678e9b80f301110e3ea8cee9819a7994c049`，来源 https://huggingface.co/csukuangfj/sherpa-onnx-zipformer-ctc-zh-int8-2025-07-03 。模型按需下载且校验 SHA256，不随 HAP 打包。
- 下载使用作者的[魔搭同款模型](https://modelscope.cn/models/csukuangfj/sherpa-onnx-zipformer-ctc-zh-int8-2025-07-03)，固定版本 `ec0ba42ddef79fe0bd20c3563f14368f48e69a2c`，权重及词表 SHA256 与上述版本一致。许可全文、ONNX Runtime 第三方声明、模型卡和来源随 HAP 保存在 `rawfile/audio_subtitles/`。

## 简听一语古诗词数据

- 内置 1365 条古诗词摘句，其中新增 1000 条选自 [chinese-poetry](https://github.com/chinese-poetry/chinese-poetry) 的 `宋词/宋词三百首.json`，按原文去重并保留作者、词牌，以首句补充标题；不包含现代译文或赏析。
- 数据集许可证：MIT，Copyright (c) 2016 JackeyGao。
- 来源、源文件 SHA256 与许可全文随应用保存在 `rawfile/poetry/NOTICE.txt` 和 `LICENSE.chinese-poetry.txt`。运行时纯本地展示。

## Harmony Book AI Engine

- 上游：https://github.com/wip3l/harmony-book-ai-engine ，固定提交 `e4592264e70402fa6396fd7860b1cb90fd349802`，包名 `@legado/aiengine`，版本 1.0.0。
- 许可证：GPL-3.0。通过独立 HAR 子包提供漫画本地着色，主工程不复制引擎源码。包构建补充公开 Worker 入口的导出声明，并在项目外应用可复现补丁 `scripts/comic_ai_calibration_patch.py`：仅原 CPU FP16 画质校验失败时增加 FP32 复核，速度比较和回退仍使用原 CPU FP16 路径，模型、推理参数及误差阈值不变。持久化校验标识包含补丁版本，以便规则更新后重新校验。补丁版本见 `scripts/comic-ai-package.json`。
- AlacGAN / Manga-Colorizer 模型沿用上游 MIT 声明；HAR 内的 OpenCC 字典使用 Apache-2.0。完整资源来源、散列及许可证随 HAR 保留。
- 引擎 LICENSE、NOTICE、THIRD_PARTY_NOTICES 随应用保存在 `rawfile/comic_ai_engine/`；准备脚本与版本清单见 `scripts/prepare-comic-ai.py` 和 `scripts/comic-ai-package.json`。

## 漫画端侧翻译

- 基础模型：Helsinki-NLP 的 `opus-mt-zh-en`、`opus-mt-en-zh`、`opus-mt-ja-en`、`opus-mt-ko-en`，作者为 University of Helsinki Language Technology Research Group。各模型许可证及来源见随包的 `comic_offline/NOTICE.txt`。
- ONNX 转换与量化来自 Xenova 对应模型，固定 ModelScope 镜像版本和 SHA256 见 `scripts/comic-offline-assets.json`；应用未再训练权重，日/韩译中文使用英文中转。
- Transformers.js 2.17.2（Apache-2.0）、ONNX Runtime Web 1.14.0（MIT）。

声明与许可证随 HAP 保存在 `entry/src/main/resources/rawfile/comic_offline/NOTICE.txt`、`LICENSE`、`onnxruntime-LICENSE`、`onnxruntime-ThirdPartyNotices.txt`。模型和运行时大文件不加入 Git，由 `scripts/prepare-comic-offline.py` 按固定版本和散列校验下载。

## @devzeng/quickjs / ohos_quickjs

- 上游项目：https://github.com/hhtczengjing/ohos_quickjs
- 版本：0.1.0（包含本项目使用的受限执行与 HarmonyOS API 26 双 ABI 修改）
- 许可证：MIT
- 版权所有：Copyright (c) 2026 zengjing

许可全文见 `third_party/quickjs/quickjs/LICENSE`。本项目保留原模块的版权、许可和免责声明。

## QuickJS JavaScript Engine

- 上游项目：https://bellard.org/quickjs/
- 许可证：MIT
- 版权所有：Copyright (c) 2017-2021 Fabrice Bellard；Copyright (c) 2017-2021 Charlie Gordon

许可全文见 `third_party/quickjs/LICENSE-QUICKJS`。

## OpenHarmony / Huawei N-API 封装代码

QuickJS 模块中带有 Huawei Device Co., Ltd. 版权头的 N-API 封装文件依据 Apache License 2.0 使用；修改后的文件继续保留原版权和许可头。

Apache License 2.0 全文见 `third_party/quickjs/LICENSE-APACHE-2.0`。

## 许可边界

本页所列 QuickJS、CryptoJS、仓颉运行时和 LLVM libc++ 保留各自许可证。本应用已迁入轻页 GPL-3.0 书源引擎，组合应用分发需遵循相应 GPL 条款并提供对应源码；不能将包含该引擎的应用整体声明为 MIT。页面没有从轻页迁入。

## 独立书源内核与轻页应用辅助代码

- 内核上游：https://github.com/wip3l/harmony-book-source-engine
- 内核固定提交：`1eb86df3e38189fee400ca5982f07e3dc4501d51`
- 应用辅助代码上游：https://github.com/wip3l/legado-harmony
- 组织 Fork：https://github.com/hos-book/legado-harmony
- 应用辅助代码固定提交：`67e5f2dc99b4fb62fe714b45d7d6acc56e7afad2`（共同维护分支 `codex/sourceengine-host`，末次修复尚未推送；保留搜索/发现/阅读调度及导入、音频后处理）
- 许可证：GPL-3.0，全文见 `third_party/light-source/LICENSE`

迁入位置：`entry/src/main/ets/service/rulesource/light/upstream/`。原版权头保留；修改和适配由 `scripts/sync-light-source.cjs` 记录，双来源版本、逐文件归属和校验值见 `third_party/light-source/upstream.json`，维护流程见 `docs/LIGHT_SOURCE_SYNC.md`。独立仓库的 NOTICE 同时保留在 `third_party/light-source/NOTICE` 和应用资源中。内核首版未包含的网页等待修复由可校验补丁保留。没有引入独立仓库附带的第二套 QuickJS HAR。

## CryptoJS

- 上游项目：https://github.com/brix/crypto-js
- 版本：4.2.0，仅包含 core、cipher-core、tripledes、mode-ecb 和 pad-nopadding
- 许可证：MIT
- 版权所有：Copyright (c) 2009-2013 Jeff Mott；Copyright (c) 2013-2016 Evan Vosberg

许可全文与固定版本信息见 `third_party/crypto-js/LICENSE` 和 `third_party/crypto-js/README.md`。仅在受限 QuickJS 中兼容用户导入书源的旧 DES／3DES 协议，不用于应用数据库、账号、Cookie 或传输加密。

运行时子集位于 `entry/src/main/ets/service/rulesource/LocalRuleLegacyCrypto.ets`，提供 DES/TripleDES 的 CBC/ECB 和显式密钥处理，继续遵循 QuickJS 的时间、内存和输出预算；不暴露模块加载、基于密码的密钥派生或原生随机数提供者。

## Cangjie runtime / standard library

- 官方项目：https://cangjie-lang.cn/ ，源码：https://gitcode.com/Cangjie/cangjie_runtime
- 版本：Cangjie 1.2.0 STS，Windows OHOS SDK 官方包，2026-09-22 发布
- 许可证：Apache-2.0 with Runtime Library Exception
- 版权所有：Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.

`entry/libs/arm64-v8a` 与 `entry/libs/x86_64` 中的核心标准库及 `libboundscheck.so` 来自上述官方 SDK。`libcangjie-runtime.so` 由同版本 v1.2.0 官方源码 commit `52f9e08f985ba42e23581e725e1b11f956f941d6` 使用 HarmonyOS Release 应用 NDK 重编，以匹配应用的 `libc++_shared.so` ABI。构建使用的 securec 头/源码依赖固定于 OpenHarmony-v6.0-Release commit `2ae82839ecaaa7d031e66ccbd2076d671acfd615`。实际打包清单、版本和 SHA256 记录在 `entry/libs/rulecore-build.json`。

运行时唯一代码适配为 `RULECORE_APP_RUNTIME` 下跳过系统 ROM namespace 探测；应用仍使用公开 `dlopen/dlsym`，未引入私有 namespace API。工具链路径、C++ 链接及该适配由 `third_party/rulecore/tools/prepare_app_runtime.py` 可重复生成，构建入口为 `scripts/build-cangjie-app-runtime.ps1`。

许可全文见 `third_party/rulecore/licenses/CANGJIE-LICENSE`，官方随 SDK 提供的第三方软件声明原件见 `third_party/rulecore/licenses/CANGJIE-Open_Source_Software_Notice.docx`。运行时公共头文件 `third_party/rulecore/include/Cangjie.h` 保留上游版权和许可头。仓颉源码、薄层绑定和复现说明位于 `third_party/rulecore/`。

## LLVM libc++ runtime

仓颉 NAPI 薄层及同版本源码重编的运行时共同使用 HarmonyOS Release SDK 26.0.0.105 提供的 `libc++_shared.so`，遵循 Apache License 2.0 with LLVM Exceptions。SDK 原始声明见 `third_party/rulecore/licenses/LLVM-NOTICE`；仓颉与 LLVM 许可材料同时保存在 `entry/src/main/resources/rawfile/third_party/cangjie/` 随 HAP 打包。

漫画翻译 OPUS-MT 权重采用固定版本按需下载，不随 HAP 打包；许可声明仍随应用提供。下载清单及 SHA256 见 `scripts/comic-offline-assets.json`，运行时只允许读取已校验的本地资源。
