# 声桥语音插件

“我的 → 模型管理”底部提供声桥折叠卡片，标题行复用模型管理组件。说明图标紧跟名称，右侧依次为展开箭头、启用开关、导入与卸载。展开区域展示版本与音色数量，账号登录、音色管理、语音调试采用整行入口，最近结果与测试位于卡片底部。登录与调试使用二级页面，页面背景随滚动内容延伸到底部安全区。

## 使用

1. 在已登录 GitHub CLI 的开发环境运行 `python scripts/prepare-shengqiao-plugin.py`。
2. 将正式输出 `artifacts/plugins/shengqiao.jtplugin` 传到设备，在声桥卡片选择导入，再开启声桥。
3. 音色自动进入既有音色管理，按“声桥 · 小艺”“声桥 · 华为”“声桥 · 微软”分组。当前插件包基于上游 1.1.92，包含 15 个小艺内置音色、14 个华为阅读音色和 16 个微软音色，共 45 个；卡片总数取实际导入目录长度。
4. 从卡片进入“账号登录”二级页面，使用自己的华为账号授权；华为阅读音色按该账号权益合成，会员音色保留权益标识。小艺内置与微软音色可直接试听。
5. 从卡片进入“语音调试”二级页面，选择音色、填写最多 300 字试听文字、调整播放器语速并试听。页面展示合成结果、耗时、音频大小及可复制摘要。卡片中的“测试”使用首个微软音色合成固定短句，仅更新结果。
6. 在普通朗读和多角色配音中选择声桥音色。关闭插件后音色退出可选目录，书籍角色绑定继续保留；重新开启后可继续使用。卸载同时移除插件包与本机声桥账号凭据。

## 接入

- `ShengqiaoPackage` 定义 `shengqiao-tts-v1` 数据包：格式、插件 ID、版本、上游配置和音色目录。包格式沿用 `.jtplugin` 扩展名，按卡片匹配插件类型。
- 目录生成同时读取 `BUILTIN_TIMBRES`、`HUAWEI_VOICES` 和 `EDGE_VOICES`。小艺内置使用上游 `cl_<person>` 稳定标识，归入独立 `celia` 通道；本次接入固定预置目录。新版包在原五项配置后追加小艺应用授权配置，旧五项包继续支持华为阅读与微软；升级应用后重新导入新版包即可获得完整 45 个音色。
- `ShengqiaoPluginService` 管理包导入、启停和音色生成。包配置保存在独立 Preferences，华为刷新凭据保存在 Asset Store Kit；登录状态与简听会员账号分别管理。
- `ShengqiaoAccountPage` 使用 ArkUI V2 隐私 Web 容器与既有 `LocalRuleWebSession` 租约，授权完成后保存刷新凭据并回到账号状态界面。凭据续期由共用服务执行。
- `CustomTtsConfig.provider = shengqiao`，`modelId` 为上游音色 key，稳定 ID 为 `shengqiao:<key>`。已安装音色与现有目录合并，顺序、单项启停、移除、角色配音复用现有机制。
- `HttpTtsPlayer` 将声桥提供方路由到 `ShengqiaoSynthesis`，使用上游小艺、华为 PCM 容器及微软合成协议。小艺通过应用令牌调用 `startTTS`，按 multipart 响应提取 16 kHz 单声道 PCM，分段拼接后封装 WAV；请求复用现有取消与错误展示。音频输出、暂停、预取、字符进度、音频焦点及倍速由现有播放链处理。
- `RoleVoiceMetadata` 补齐小艺 15 个预置音色的性别、上游已标注的年龄和声线特征，AI 多角色配音沿用当前候选目录与选声流程。
- 华为令牌续期响应省略刷新令牌时沿用已保存凭据；服务返回新刷新令牌时更新系统密钥库。华为合成请求的 `x-traceId` 使用去除 `uuid#` 前缀的设备标识。登录、网络、插件启用与音频解析错误分别展示，HTTP 401/403 保留授权错误分类。
- `ShengqiaoDebugPage` 复用 `VoicePreviewService`；试听采用独立选择，正式朗读的音色偏好继续保留。

2026-11-27 布局调整：三个本地 TTS 模型及专属接入已移除，标题行与展开区按当前方案调整，八个改动文件 ArkTS 检查通过。

2026-11-27 华为调用修正：令牌续期、请求头和错误分类已调整，三个改动 ETS 文件静态检查通过，音频解析依赖同步检查通过，保留现有建议项。Release SDK 26.0.0.105 的 Debug HAP 构建成功，包元数据确认 Release SDK 渠道，并已覆盖安装和启动到 Mate 80。实机声桥调试页显示书馆先生“合成成功”，耗时 4720 ms、音频 363 KB；用户反馈晓晓和 MAI 已可用。其余音色逐项合成、实际听感和连续朗读待进一步验证。

## 来源

- 上游仓库：https://github.com/zyt174/shengqiao-hap
- 已读取的上游实现：`MAINTAIN.md`、`COLLAB.md`、`entry/src/main/ets/pages/LoginPage.ets`、`entry/src/main/ets/services/HuaweiTts.ets`、`EdgeTts.ets`、`CeliaApi.ets`、`TtsServer.ets`、`model/voices.ets`。
- 已读取 ArkUI 指导：https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-develop-skill/SKILL.md
- 已读取编译指导：https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-syntax-checker/SKILL.md
- 已读取 API 迁移指导：https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-deprecated-interface-checker/SKILL.md
- 已读取 ArkTS 检索指导：https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-knowledge-retriever/SKILL.md
- 已读取错误分类与传递指导：https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-knowledge-retriever/docs/ArkTS-Language-Guide/02-Basic-Syntax/error-handling.md

上游代码归原作者所有，授权信息见 `THIRD_PARTY_NOTICES.md`。
