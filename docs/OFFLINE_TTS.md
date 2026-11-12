# 本地 TTS 与多角色朗读

本地 TTS 负责把正文变成声音，多角色模型负责判断“这句话是谁说的”。两者独立导入，通过每书角色与音色绑定组合使用；只导入多角色 GGUF 不会生成声音，只导入 TTS 模型则可以使用单音色离线朗读。

## 当前可导入模型

本地合成复用 **sherpa-onnx**，支持独立导入 Piper 超文、Piper 小雅与 Kokoro v1.1-zh INT8。Piper 两个模型各提供 1 个中文声音、采样率 22,050 Hz；Kokoro 为 82M 参数，提供 100 个中文声音（55 女声、45 男声，原包另含 3 个英文女声）。不同音色的自然度、数字、多音字和长篇小说韵律须试听判断，不能把参数、音色数量或其他平台跑分当作手机验收。

| 模型 | 本地音色 | 官方原包 |
| --- | ---: | --- |
| Piper 超文 | 1 | `vits-piper-zh_CN-chaowen-medium-int8.tar.bz2` |
| Piper 小雅 | 1 | `vits-piper-zh_CN-xiao_ya-medium-int8.tar.bz2` |
| Kokoro v1.1-zh INT8 | 100 | `kokoro-int8-multi-lang-v1_1.tar.bz2` |

模型在“我的 → 模型管理 → 本地 TTS”分组分别管理，可同时保留。新增模型不替换已导入 Kokoro，也不重置已有角色绑定。这里支持的是 sherpa-onnx 发布的对应原包，不支持直接导入任意 Piper ONNX 或把其他模型改名为这些文件。

| 候选 | 官方资料及取舍 |
| --- | --- |
| Piper 超文 / 小雅 | 已有 sherpa-onnx VITS 中文发布包，作为可独立导入的单音色选择；已完成少量手机试听测速及超文约 2 分 25 秒的现场连续播放事件测量，长时效果和听感仍待验收 |
| Kokoro v1.1-zh | 已有 HarmonyOS 原生 sherpa-onnx 接口，可在同一模型按 `sid` 切换人物声音；保留 INT8 支持 |
| MeloTTS 中文/英文 | 官方支持 CPU 推理与中英文混读，适合单音色朗读；官方中文包的角色音色选择少于 Kokoro v1.1-zh |
| Qwen3-TTS | 官方提供 0.6B / 1.7B 模型、语音克隆与声音控制；模型及推理链更大，官方 Python/CUDA 示例不能证明已适配本项目 HarmonyOS 端侧 |
| CosyVoice 3 | 官方 0.5B 模型提供克隆、方言与指令控制；本项目尚未接入其原生移动端推理，不作为首版可导入格式 |

实际读取的官方来源：

- [Kokoro v1.1-zh 模型卡与听感样例](https://huggingface.co/hexgrad/Kokoro-82M-v1.1-zh/blob/main/README.md)
- [sherpa-onnx HarmonyOS 原生示例](https://github.com/k2-fsa/sherpa-onnx/tree/master/harmony-os/SherpaOnnxTts)
- [sherpa-onnx 模型发布包](https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models)
- [Piper 超文模型卡](https://huggingface.co/rhasspy/piper-voices/blob/main/zh/zh_CN/chaowen/medium/MODEL_CARD)（本次通过 [HF 镜像](https://hf-mirror.com/rhasspy/piper-voices/raw/main/zh/zh_CN/chaowen/medium/MODEL_CARD)读取）
- [Piper 小雅模型卡](https://huggingface.co/rhasspy/piper-voices/blob/main/zh/zh_CN/xiao_ya/medium/MODEL_CARD)（本次通过 [HF 镜像](https://hf-mirror.com/rhasspy/piper-voices/raw/main/zh/zh_CN/xiao_ya/medium/MODEL_CARD)读取）
- [超文官方试听](https://k2-fsa.github.io/sherpa/onnx/tts/all/Chinese/vits-piper-zh_CN-chaowen-medium.html) / [小雅官方试听](https://k2-fsa.github.io/sherpa/onnx/tts/all/Chinese/vits-piper-zh_CN-xiao_ya-medium.html)
- [MeloTTS](https://github.com/myshell-ai/MeloTTS)
- [Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS)
- [CosyVoice](https://github.com/FunAudioLLM/CosyVoice)

## 导入与搭配

1. 在“我的 → 模型管理 → 本地 TTS”打开所选模型的来源说明，复制官方下载地址。下载完整 `.tar.bz2` 后，在对应卡片直接导入，无需解压或转换；Kokoro 已有配套 ZIP 也可继续导入。
2. 如需自动分角色，在同页另行导入多角色 GGUF 模型。
3. 在朗读音色中选择已导入的 Piper 或 Kokoro 中文声音，即可本机合成。
4. 打开“多角色朗读”，为旁白、默认对白及人物绑定本地音色。例如旁白用超文、对白用小雅，也可给更多人物选择 Kokoro 声音。一个 Kokoro 模型中的不同 `sid` 直接对应不同声音，不必为每个人物导入一份权重。

全局默认音色选择 Piper 后，新发现的人物仅从其他已启用的 Piper 声音分配；默认选择 Kokoro 时，仅从其他已启用的 Kokoro 声音分配。没有可用候选时沿用默认声音，不会因 HTTP 或其他模型的音色排在前面而自动切换。已有的手动绑定继续保留，可逐个人物混合选择 Piper 与 Kokoro。跨模型切换可能重新加载模型，更多音色不代表等待更短。

完全离线朗读还需要正文已在本机。若某个角色仍绑定 HTTP 音色，该角色的合成继续依赖对应网络服务。多角色识别也需要单独的 GGUF 权重；它与 TTS 权重不会互相替代。

## 官方原包与可选打包工具

直接导入下载后的对应官方原文件即可，保留原后缀，无需先解压或使用电脑转换。Piper 使用上表两个固定 INT8 包；Kokoro 下载约 140.2 MiB，同时兼容此前的配套 ZIP。

官方下载地址：

- [Piper 超文](https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-zh_CN-chaowen-medium-int8.tar.bz2)
- [Piper 小雅](https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-zh_CN-xiao_ya-medium-int8.tar.bz2)
- [Kokoro v1.1-zh INT8](https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-int8-multi-lang-v1_1.tar.bz2)

两个 Piper 包各包含 8 份固定资源，展开各约 20 MiB。各型号在独立私有目录安装、校验和删除，失败或取消只清理本次临时目录。删除某个模型不会删除其他 TTS 模型或每书角色绑定；重新导入相同型号后仍使用原有稳定音色 ID。导入成功只恢复该型号的音色，不重新显示用户在其他模型下隐藏的声音。

Kokoro 固定资产清单为 `scripts/offline-tts-assets.json`，记录发布者仓库、固定 revision、每个文件的字节数及 SHA256，以及完整 103 个说话人的稳定顺序。`scripts/generate-offline-tts-assets.py` 生成 `model/OfflineTtsAssets.ets`；运行 `--check` 可检查生成文件是否与清单一致。该清单只记录模型资源身份，不包含权重内容。

资源包含 `model.int8.onnx`、`voices.bin`、`tokens.txt`、中英文词典、日期/电话号码/数字规范化 FST、许可证，以及当前 sherpa-onnx 1.13.3 要求的完整 `espeak-ng-data`。`dict/` 自 sherpa-onnx 1.12.15 起不再用于此模型。首版保留完整 eSpeak 数据，避免只通过文件存在检查却缺少实际运行的语言依赖。

`scripts/pack-offline-tts.py` 仅作为开发者可选的兼容 ZIP 打包工具，日常导入不需要执行。脚本接收官方 tar.bz2 发布包，不接收解压目录：

```text
python scripts/pack-offline-tts.py C:/path/kokoro-int8-multi-lang-v1_1.tar.bz2 --output artifacts/models/offline-tts-kokoro-int8-v1_1.zip
```

可选的 ZIP 打包完全在本机执行，逐项验证固定清单，模型权重与大音色文件拆成最多 4 MiB 的块。两种导入格式均按固定清单校验完整资源，再通过实际短句合成后启用；失败或取消保留旧模型。全部 364 份固定资源展开占用 194,288,036 字节（约 185.3 MiB），运行时还需模型内存和音频缓冲，安装及替换需要额外可用空间。

可选 ZIP 可保存为本机 `artifacts/models/offline-tts-kokoro-int8-v1_1.zip`，不随 HAP 打包、不推送 Git；验证结束删除临时下载和过程文件，保留仍需使用的正式模型包。完整参数见 `python scripts/pack-offline-tts.py --help`。

固定的核心文件身份：

| 文件 | 字节数 | SHA256 |
| --- | ---: | --- |
| model.int8.onnx | 114203914 | `05d793700b0b507f760c183c0e39bdd6a97b43d32fdc7bf7b54a5179f1b11222` |
| voices.bin | 53790720 | `e64a5a581d8c2a350d848f51c3121657cd83aa07ed6109172177345874a7244c` |
| lexicon-zh.txt | 2120131 | `fea060803db3e59193987f1a3436f56917bda09f3b3595b6588e46ae60cebf93` |

主权重和大文件散列来自官方 Hugging Face API 的 LFS SHA256，小文件散列由同一固定 revision 的原始文件计算。完整列表见项目 JSON。应用不接受以相同文件名替换的任意 ONNX，也不执行导入包中的代码。

## 运行与资源边界

合成在本机 Worker 调用 sherpa-onnx，通过原生 CPU 推理生成 PCM/WAV，复用现有朗读播放与进度链。角色识别沿用现有本地 GGUF 服务。合成与角色识别有各自的内存开销；模型文件大小不等于运行时内存峰值。

本地连续朗读按“当前段 + 后续三段”保留最多四个音频任务，原生合成仍由同一 Worker 串行执行。首段优先提交，600 ms 后或首段合成完成即补齐窗口；准备好的后续短段不再使合成器空等到其起播才处理更后面的长段。HTTP 音色继续遵守原有并发设置，扩展槽位只用于本地音色；未完成角色识别的对白不会提前用默认声音合成。暂停、跳读、变速、切音色或切书会使旧结果失效，排队但尚未开始的原生合成不会继续提交。下一章仍只预取正文，不提前生成本地音频。

用户主动朗读的 Worker 使用 API18 起提供的 `ThreadWorkerPriority.HIGH`（`QOS_USER_INITIATED`），从 `@kit.ArkTS` 顶层命名导入；最低 API20 可直接使用。优先级设置不保证覆盖 ONNX Runtime 的全部线程，也不能代替实际连续播放验证。

系统文件选择器使用 SDK 声明的 `SystemCapability.FileManagement.UserFileService`，由 UIAbilityContext 创建 DocumentViewPicker，无需另申请文件管理权限。Worker 协议独立放在不含 UI 装饰器的 `OfflineTtsWorkerProtocol.ets`；不能间接加载包含 `@ObservedV2/@Trace` 的 UI 状态模块。本次试合成曾在真机触发 `Trace is not defined`，以拆分协议文件修复，构建成功不能代替该场景的运行验证。

- [系统文件选择器 API](https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/reference/apis-core-file-kit/js-apis-file-picker.md)
- [用户文件选择与临时 URI 授权](https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/file-management/select-user-file.md)
- [并发 FAQ：Worker 与 UI 装饰器隔离](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-knowledge-retriever/docs/ArkTS-Language-Guide/04-Concurrency/concurrency-faq.md)
- [Worker API：串行消息队列与线程优先级](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-knowledge-retriever/docs/ArkTS-API-Reference/js-apis-worker.md)

音色顺序以官方 `generate_voices_bin.py` 和模型卡的 `voices/` 文件列表为准：`sid` 0–2 为英文女声，3–57 为中文女声，58–102 为中文男声。中文原始名称存在跳号，例如 `zf_017` 的 `sid` 为 11，不能把文件名数字直接当作 `sid`。应用使用固定名称映射，旧角色绑定保留稳定身份。

sherpa-onnx 1.13.3 的 Kokoro 仍要求 `dataDir` 指向已导入的 eSpeak 数据目录。`lang` 保持空值，并提供中英文词典；直接强设 `lang='zh'` 会改变前端路径并绕过词典，不能据此保证中文发音。未来升级 sherpa-onnx 2.x 时，应重新核对其移除 eSpeak 后的前端变化，不能照搬 1.13.3 参数含义。

依据：

- [1.13.3 Kokoro 配置校验](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.3/sherpa-onnx/csrc/offline-tts-kokoro-model-config.cc)
- [1.13.3 多语言前端](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.3/sherpa-onnx/csrc/kokoro-multi-lang-lexicon.cc)
- [官方音色排列生成脚本](https://github.com/k2-fsa/sherpa-onnx/blob/master/scripts/kokoro/v1.1-zh/generate_voices_bin.py)

## 许可与验证边界

Kokoro 模型权重与 sherpa-onnx 主项目采用 Apache-2.0。固定 Piper 小雅原包的模型卡将 BZNSYP 训练数据标注为非商业使用。固定超文原包的模型卡虽将其新增训练数据标注为 CC0，但同时明确由小雅模型微调；不能据此将整个超文权重视为 CC0 或已获商业使用许可。最新版超文网页模型卡已改为其他基础模型，不适用于本项目固定原包。应用保留原包模型卡与散列，两张 Piper 卡的来源说明均披露相关限制；模型、基础模型及数据集条款须分别遵守。

当前 1.13.3 的发音前端包括 MIT 许可的 piper-phonemize 和 GPL-3.0-or-later 的 eSpeak NG；模型根目录的 Apache LICENSE 不覆盖这两者。ONNX Runtime 沿用已有 MIT 许可及第三方声明。对应许可全文和固定来源随 HAP 保存在 `rawfile/third_party/offline_tts/`；原生库的其他许可继续沿用既有字幕依赖声明。主工程采用 GPL-3.0，组合分发需遵循相应条款并提供对应源码。GGUF 模型遵守各自发布者的许可。模型权重由用户独立导入。

2026-11-12 主机验证：83 项 `test-text-to-speech.cjs` 回归及 `test-custom-tts.cjs`、`test-http-tts-prefetch.cjs`、`test-voice-preview.cjs` 均通过。新增覆盖 Piper 模型/说话人透传、零 HTTP 分流、语速只应用一次、跨模型试听、同系列自动选声、旧手动绑定保留，以及仅刷新目标型号的隐藏音色。推理、文件系统和音频边界使用模拟平台，不能视为真机速度或听感结果。

本轮使用 Release SDK 26.0.0.105 完整构建成功并安装至手机；LSP 曾出现接口缓存诊断，完整构建已通过对应接口检查，不能将其缓存报错当作构建失败。

2026-11-12：已有 Kokoro 官方原包在手机上导入，界面显示 100 音色。本轮真机日志测得 31 字片段从 `local-synthesis` 到 `ready` 为 21.95 秒，之后播放约 6.8 秒；听感和等待未达到用户预期。后续 Kokoro 热态测量被手动切换音色中断，不作持续速度结论。

随后在同一手机成功导入 Piper 超文、小雅的两个官方 `.tar.bz2` 原包，各显示 1 个声音，原 Kokoro 100 音色保留。进程 `pid=32147` 对同一 31 字片段完成以下少量试听，五次均记录到 `played`：

| 模型 / 任务 | 合成准备 | 模型加载 | 生成耗时 | 音频时长 |
| --- | ---: | ---: | ---: | ---: |
| 超文 task 1，首次加载 | 4.365 s | 1.566 s | 2.750 s | 5.602 s |
| 超文 task 2，热态 | 2.353 s | 0 s | 2.323 s | 5.375 s |
| 小雅 task 3，首次加载 | 4.822 s | 1.612 s | 3.167 s | 6.140 s |
| 小雅 task 4，热态 | 2.825 s | 0 s | 2.792 s | 6.179 s |
| 切回超文 task 5 | 2.349 s | 0 s | 未单列 | 未单列 |

合成准备时间按 `local-synthesis → ready` 计算：task 1 为 18:47:38.597→18:47:42.962，task 2 为 18:48:00.762→18:48:03.115，task 3 为 18:48:32.453→18:48:37.275，task 4 为 18:48:45.818→18:48:48.643，task 5 为 18:49:18.717→18:49:21.066。模型加载、生成耗时和音频时长取对应运行日志；合成准备包括加载及调度等开销，音频时长是生成结果长度。

以上仅验证该手机上对应原包能导入、少量短句能合成并播放，以及这些片段的等待时间；不能据此认定持续朗读速度、跨设备速度或 Piper 听感优于 Kokoro。连续多角色朗读、GGUF 同时运行、断网长时播放和功耗仍待验收。

用户随后反馈连续朗读段间卡顿。旧队列仅准备下一段：例如 task 8 已在 18:52:35.047 准备好，task 9 仍等到 18:52:36.902 才开始生成；task 8 于 18:52:40.649 播完，task 9 到 18:52:42.724 才准备好，出现约两秒欠供。已改为上述四槽预缓冲，并加入真实 `playing` 日志用于核对媒体起播交接。此次修改通过 86 项朗读回归、变更文件 ArkTS 检查及 Release SDK 增量构建。手机重连后，四槽修正版已通过 `start_app` 成功覆盖安装并启动，随后取得下述现场连续播放样本。

此前 `pid=64440` 对同书 part 50 的尝试在出声前中断：首个 38 字片段于 19:15:44.990 提交，19:15:52.212 队列全部记录 `cancel`，没有 `playing` 或 `played`；原生任务于 19:15:55.865 完成（load 4965 ms、gen 5891 ms、audio 7152 ms）。19:17:26.739 系统记录 `UpgradeApp` 退出、exit 0，触发来源未定。这次中断不作为连续播放样本，也不据此推断为崩溃或归因于用户操作。

用户确认仍在播放后，本轮仅只读采集日志，未操作 UI 或重新安装。新进程 `pid=4577` 使用 Piper 超文，播放《青莲之巅》`chapterIndex=9`、自 part 50 开始。首个 38 字片段于 19:23:18.043 提交，19:23:26.634 为 `ready`，19:23:26.751 为 `playing`：合成准备 8.591 秒、首次起播等待 8.708 秒；对应 load 4731 ms、gen 3789 ms、audio 7316 ms。冷启动首句仍有明显等待。

19:23:26.751 至 19:25:52.050 的约 2 分 25 秒现场连续播放中，task 1–23 完整记录 `played`，task 24 已记录 `playing`，得到 23 次自然切段：

| 观测项 | 本轮结果 |
| --- | --- |
| 上段 `played` → 下段 `playing` | 最短 102 ms，中位数 133 ms，最长 194 ms |
| 超过 1 秒的交接 | 0 / 23 |
| 入队时音频准备情况 | 首段 `ready=false`，后续 23 次均为 `ready=true` |
| 取消与进程状态 | `cancel` 为 0；截至 19:25:52 快照仍为同一 `pid=4577` |

本轮 23 次自然交接均命中预取音频。另行只读检查的 19:23:15–19:25:26 HiLog 未见 kill、restart、JS 或 Native crash 标记。上述播放器事件与日志统计不等于录音听感验证，也不能认定所有听感卡顿已消除；未核实特定前台或后台持续时长，不推导长时、断网、GGUF 同时运行、跨章或其他设备效果。此前单句表仍只代表其各自的少量试听。

18:55:03.999 的退出有明确系统记录：`PROCESS_KILL, pid=32147, processName=com.huan.listenbook, reason=UpgradeApp, FOREGROUND=1`，紧随进程退出码 0，属覆盖安装结束运行进程。现有 HiLog 未发现此次退出对应的 JS/Native 崩溃标记；faultlogger 目录无读取权限，不能排除其他时间的独立崩溃，也不能将此次安装退出描述为已修复了 TTS 崩溃。

ArkTS 检查、构建、打包校验或模拟平台回归，只能说明对应代码和资源格式通过了这些检查。手机真机断网连续朗读、角色切换听感、首句等待、耗电/发热、峰值内存，以及与 GGUF 同时运行的稳定性，必须按实际执行结果单独记录；未执行时不得描述为已验证。平板或手机验证也不能替代手表验证。
