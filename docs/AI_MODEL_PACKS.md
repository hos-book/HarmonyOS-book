# 可选 AI 模型包

普通阅读与播放不要求安装可选模型。“我的 → 模型管理”提供漫画着色、AI 字幕、多角色朗读卡片和本地 TTS 分组。漫画选择配套 `.jtmodel` 加密模型包，字幕选择 ZIP，均无需解压；多角色朗读直接导入 GGUF。本地 TTS 分组下的 Piper 超文、小雅和 Kokoro 各自展示状态、大小及导入/删除入口，直接选择各自官方下载的 INT8 `.tar.bz2`；Kokoro 也兼容旧配套 ZIP。已有模型和角色绑定保留。小雅与由其微调的固定超文包均在来源说明中披露 BZNSYP 数据的非商业使用限制，详见 [OFFLINE_TTS.md](OFFLINE_TTS.md)。支持替换、取消和确认删除，说明收进标题旁的感叹号，不新增底部固定栏。会员权益校验保留。

| 资源包 | 文件 | 权重原始大小 |
| --- | --- | --- |
| 漫画着色 | `artifacts/model-packs/v1/Jianting-comic-color-v1.jtmodel` | 176.25 MiB |
| AI 字幕 | `artifacts/model-packs/v1/Jianting-audio-subtitle-v1.zip` | 422.10 MiB |

漫画包含通用 CPU 与横竖屏 NNRT 模型，字幕包含语音、词表和标点模型；这些权重均不随主包安装。漫画翻译语言包仍沿用原有首次使用时按需下载，运行资源暂保留在主包。普通超分、书源、阅读和播放不依赖可选模型。

## 漫画加密包

`.jtmodel` 内部是有界 ZIP 容器，只有清单和许可证为明文；模型以 4 MiB 明文块分别使用 AES-256-GCM 加密，条目为 `12 字节随机 nonce + 密文 + 16 字节认证标签`。清单格式 2 包含 `id`、`chunkBytes`、`cipher` 和发行 `keyId`；AAD 为 `JiantingModelPack/v2/{id}/{asset.name}/{index}`，绑定模型与块序号，拒绝篡改和跨文件替换。字幕继续使用格式 1 的普通 ZIP。

用户无需密码，只在简听中导入即可使用。此方案防止直接解压获得可运行模型，不是不可破解的 DRM：离线应用需要解密，逆向、注入或读取已安装模型仍可能提取权重。不增加账号、在线授权或模型下载服务。

发行密钥在本机 `signing/model-pack.key`，不进入 Git、清单、公开源码或日志。首次生成漫画包时创建，后续打包与构建复用；请安全备份并在换机后恢复，不能随意重新生成。密钥遗失时，已有包无法继续用同一密钥构建。CMake 通过 `scripts/model_pack_key.py` 将掩码数据生成到本机原生构建目录，编译成双架构 `libmodel_pack_crypto.so`；ArkTS 用系统 CryptoFramework 解密，结束/失败清除系统密钥和临时密钥缓冲区。GCM 与密钥清理接口在安装 SDK 中为 API 9，满足最低 API 20。

## 安装与兼容

沿用 `filesDir/comic_colorizer` 和 `filesDir/subtitle_models/824c678e9b80f301110e3ea8cee9819a7994c049`。旧版完整模型可直接复用，缺失文件显示未完整安装。漫画不再从内置资源展开，也不提供远程下载回退；删除后需重新导入。旧版 `.disabled` 不再决定外置模型可用性。

导入只接受 `AiModelPack.ets` 固定版本、尺寸与 SHA256 白名单。复用 `EpubArchive` 有界目录/CRC 读取，逐块认证解密、处理短写并累计 SHA256，不整体展开至内存，不用条目名作为输出路径。导入前预留完整新模型加 64 MiB。选中文件后阻止新推理，取消并等待对应功能释放在途任务。

新文件写入 `.importing`，全部通过校验并同步落盘后才交换目录；原目录先改名 `.previous`。失败、取消或校验错误保留旧模型；重启恢复未完成交换并清理残留。删除只处理对应模型和交换目录，保留用户书籍、原图、音频、进度与字幕缓存。

## 准备和构建

```cmd
python scripts\prepare-comic-ai.py --externalize
python scripts\prepare-comic-ai.py
python scripts\prepare-subtitle-assets.py
```

第一次从旧 HAR 切换时，`--externalize` 先生成并完整验证漫画加密包，再原子移除 HAR 模型权重、保留其他文件并更新散列记录；旧明文漫画 ZIP 在加密包验证后移除。后续引擎重建同样导出加密包再移除权重，不会重新内置。`assetDelivery` 为 `encrypted-comic-model-pack-v2`。已有匹配 HAR 直接复用，无需重复拉取引擎。

也可运行 `python scripts\ai_model_packs.py --comic` 单独准备/校验加密包。Python 需要 `cryptography`。许可证随包 `LICENSE.txt` 与应用保留，校验清单在同目录 `SHA256SUMS.txt`，对外分发加密包即可，不能分发发行密钥。发布检查拒绝主包中的 `.ms`、`.onnx`、`.gguf` 权重，并要求双架构解密桥、Release SDK、最低 API 20 / 目标 API 26。

## 验证

```cmd
node scripts\test-ai-model-packs.cjs
node scripts\test-ai-model-packs.cjs --release-pack
node scripts\test-comic-colorization.cjs
```

主机回归使用实际 ArkTS 导入服务、解密辅助类与 ZIP 解析器，模拟系统文件与 CryptoFramework，覆盖普通 ZIP、加密导入、短写、篡改、错误密钥、跨模型替换、明文漫画包拒绝、取消、空间不足、回滚、中断恢复和删除隔离。`--release-pack` 额外用本机发行密钥验证 Python 生成的真实三份模型包，临时明文结束后删除。2026-11-11 共 13 项通过，漫画宿主回归通过。主机验证不等于系统 CryptoFramework、系统选择器及真机推理验证。

此前 VYG-AL00 已完成的字幕 ZIP 导入/取消、覆盖更新和 GGUF 保留仍为独立既有验证，本轮漫画加密包尚未做真机导入和推理。未验证平板、折叠屏、PC 或手表。

2026-11-11 本轮版本已以相同调试签名、`product=default` / `buildMode=debug` 覆盖安装并启动至 VYG-AL00。实机模型管理页可正常显示三张卡片，漫画显示已安装 176 MiB、重新导入和删除入口，字幕显示已安装 422 MiB，原有 GGUF 保留。未执行漫画加密包重新导入和推理。UI 自动验证工具缺少服务环境配置，改用 HDC UI 树确认页面状态，未更改设备持久化测试参数。

本轮 Release SDK 26.0.0.105 构建与发布检查通过：1.1.2 / 1012001，最低 API 20、目标 API 26，双架构解密桥、零模型权重、45 张桌面图标图层及混淆协议检查通过。主包由 226,142,132 字节（215.67 MiB）降至 55,280,803 字节（52.72 MiB），减少 162.95 MiB / 75.55%；漫画包为 184,828,478 字节（176.27 MiB）。字幕 48 项回归通过。ETS 检查工具返回 LSP 未初始化，未记为独立静态检查通过；MCP 构建已有批处理递归失败记录，本轮使用相同 Release IDE 的 Node/ohpm/Hvigor CLI（`--no-daemon`），未更改本机签名配置。

发布检查还核对双架构库的发行密钥标识，并拒绝编译器把密钥掩码 XOR 折叠成原始密钥常量；原生生成头使用 volatile 读取避免该优化。此检查不改变离线应用仍可能被逆向提取的保护边界。

实现参考在线 [ArkTS 语法约束](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[ArkUI 检索指导](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md)和[构建指导](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-studio-hvigor/SKILL.md)。接口版本以安装 Release SDK 声明复核。
