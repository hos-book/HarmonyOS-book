# 本地多角色朗读

入口：阅读器菜单 → 角色配音，或“我的 → 阅听设置 → 多角色朗读”。模型在“我的 → 模型管理”统一导入。启用状态全局保存，旁白、默认对白和人物音色按书籍保存，继续复用现有音色选择、试听、播放和阅读进度。

## 通用模型与自动调度

只需导入一份 `csi-v1-generic.ms`。同一模型供手机、平板和电脑使用，调度依据系统公开的 NNRT 加速器能力，独立于厂商和芯片型号。

`RoleModelService` 通过 `librole_nnrt.so` 串行调用系统 MindSpore Lite C API。运行上下文先添加 `OH_AI_NNRTDEVICE_ACCELERATOR`，再添加 CPU。MindSpore Lite 将适配算子优先调度到 NNRT，其余算子在 CPU 上执行；设备仅提供 CPU 时直接使用 CPU。加速模型加载或推理失败时，重新建立 CPU 上下文并执行同一份模型与输入。

模型管理卡显示文件名、大小和运行方式：“NPU 优先，CPU 协同”表示已配置加速器参与调度；具体算子分配由系统完成。“CPU”表示 CPU 上下文。界面状态表达调度方式，实际加速占比以设备运行结果为准。

原生推理在异步工作线程执行，使用 2 个 CPU 线程，空闲 30 秒释放模型。导入支持复制进度、取消、模型加载和样例推理；更新模型继续保留人物音色设置。

角色识别与语音合成分别调度。Piper、Kokoro 本地语音继续通过 sherpa-onnx CPU 合成；HTTP 音色沿用现有服务。音色与模型许可见 `OFFLINE_TTS.md`。

## 角色识别流程

1. `ReaderDialogueHighlighter` 确定对白的原文 UTF-16 范围。
2. `RoleSpeechPlanner` 将最多三段相邻对白组成窗口，传递完整原文片段及对白起止位置。
3. `RoleBertTokenizer` 每个窗口分词一次，各对白复用 token 和原文映射。按 512 token 预算围绕目标对白选取上下文，长对白保留首尾及两侧叙述，原文与阅读位置保持完整。
4. CSI 提供姓名起止分数；候选评分时应用现有姓名长度、代词与文本规则，压缩位置两侧独立选择姓名。
5. `RoleSpeechService` 保存角色与音色关联，按原文范围交给既有朗读链路；待确认角色使用默认对白音色。

暂停和换书沿用现有取消机制，每段对白推理前后检查当前会话。章节缓存版本为 3；模型变更与既有章节身份一起参与缓存选择。每书角色设置、缓存数量和播放位置沿用现有存储约定。

## 模型转换

源模型为 `Warma10032/chinese-roberta-wwm-ext-large-csi-v1` 的 `csi-v1.pth`；配置使用 `hfl/chinese-roberta-wwm-ext-large`。导出采用 `BertForQuestionAnswering`、`layer_norm_eps=1e-5`、eager attention。应用包含配套中文词表。

转换环境使用 Python、PyTorch 2.5.1、Transformers 4.46.3、ONNX 1.17.0 和官方 MindSpore Lite 2.7.0 `converter_lite`。脚本先导出 opset 13 ONNX，再按 `--saveType=MINDIR_LITE --fp16=on --optimize=general` 转换为便携式模型；转换仅使用通用图优化，设备在运行时选择计算后端。

```bash
export LD_LIBRARY_PATH=/path/to/mindspore-lite/tools/converter/lib
python scripts/convert-role-speaker-model.py \
  --model-dir /path/to/config \
  --checkpoint /path/to/csi-v1.pth \
  --converter /path/to/mindspore-lite/tools/converter/converter/converter_lite \
  --output artifacts/models/csi-v1-generic.ms
```

三个输入均为 `(1,512)` INT32：`input_ids`、`token_type_ids`、`attention_mask`。输出为 `start_logits`、`end_logits` 两组 512 项浮点分数。原生桥统一输出 FP32 给 ArkTS。

CSI 原始项目对语料标注非商业研究用途；权重许可与语料来源条件分别审阅。模型独立交付，HAP 包含推理桥接、词表及许可，MindSpore Lite 使用系统运行时。

## 依据与验证记录

- 官方 NNRT/CPU 协同指南：https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/ai/mindspore/mindspore-lite-guidelines.md
- 官方模型转换指南：https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/ai/mindspore/mindspore-lite-converter-guidelines.md
- 模型转换工具：https://www.mindspore.cn/lite/docs/en/r2.7.0/use/downloads.html
- CSI 模型：https://huggingface.co/Warma10032/chinese-roberta-wwm-ext-large-csi-v1
- CSI 训练项目：https://github.com/yudiandoris/csi
- ArkTS 语法指南技能：https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-knowledge-retriever/SKILL.md
- ArkUI 开发技能：https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-develop-skill/SKILL.md
- 编译修复技能：https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-syntax-checker/SKILL.md

2026-11-23：通用 `.ms` 转换成功，文件大小 649,147,872 字节。Release SDK 26.0.0.105 的 Debug HAP 构建通过。独立 LSP 检查仍引用旧版双参数原生声明，报告参数数量提示；当前声明为单参数，完整构建已按当前声明编译通过。运行时 API 以本机 Release SDK 26 声明为依据，所用 MindSpore 接口均在 API 20 及以前提供。在线目录索引已获取，根目录 API 返回 HTTP 429；技能应用沿用索引定位和已读取的参考正文。实际耗时、识别质量与 NPU/CPU 分配效果仍待真机确认。
