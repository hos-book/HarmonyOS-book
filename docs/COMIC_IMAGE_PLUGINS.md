# 漫画图片插件

“我的 → 模型管理”统一展示两个漫画插件与漫画着色、AI 字幕、三个本地 TTS 模型。每项复用 `ModelManagementRow`，紧接标题栏下方从上到下单行排列，滚动内容显式顶部对齐；行内提供名称、感叹号说明及文件夹导入、卸载图标。两个插件保留 32 × 20 vp 启用开关，分别导入、开启、关闭、替换和卸载。感叹号弹窗展示描述、安装状态、版本与使用说明；文件夹导入图标兼作替换入口。

| 插件 ID | 名称 | 用途 |
| --- | --- | --- |
| `comic-watermarks` | 漫画水印清理 | 识别已收录角落水印，填充留白或恢复局部像素 |
| `edge-banners` | 包子漫画横幅去除 | 识别页首及页尾横幅，确认边界后裁切 |

## 使用

准备环境为 Python 3 和 curl。运行 `python scripts/prepare-comic-image-plugins.py` 从上游公开发行资源准备两个独立导入文件，默认输出至 `artifacts/plugins/`；`--release-base` 可指定上游发行地址的代理前缀。将 `.jtplugin` 文件传到设备，在对应插件卡片中导入，再开启开关。算法资源由用户单独导入，应用包仅包含宿主。上游资源条款以原作者声明为准，公开分发算法包前取得作者明确授权。

## 包格式

`.jtplugin` 是 UTF-8 JSON，`format` 为 `1`，包含 `id`、整数 `version`、`abi`、`parameters` 和 `wasm`。ABI 为 `koma-image-v1`，`parameters` 保存算法参数的 JSON 字符串，`wasm` 保存算法的 Base64 字节。每个文件只包含一个插件，导入时按对应卡片匹配 ID。

## 处理链路

正文原图 → 漫画水印清理 → 包子漫画横幅去除 → 着色／翻译或超分 → 显示。只运行已安装且开启的插件。原始下载、章节目录及原图尺寸记录继续保留，派生 PNG 进入现有阅读图片缓存。横幅裁切后的显示使用输出图片的实际比例，白边识别基于处理结果。

宿主复用 ArkWeb，在本地隔离页面中通过 Web Worker 运行 WASM。固定宿主提供 `koma_image` 的尺寸、配置、RGBA 区域读取、输出创建与逐行写入接口。算法导入仅包含这些函数，宿主资源请求仅映射当前原图、已启用插件和打包脚本。离开阅读视口时终止当前任务，处理错误时显示原图。

## 来源

- 插件接口：https://github.com/honjow/Koma/blob/master/docs/image-processing-plugin-abi.md
- 上游插件：https://github.com/honjow/koma-sources/tree/master/image-rules/plugins
- 水印算法：https://github.com/honjow/koma-sources/tree/master/image-rules/plugins/watermark
- 横幅算法：https://github.com/honjow/koma-sources/tree/master/image-rules/plugins/banner
- ArkTS 指导：https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-knowledge-retriever/SKILL.md
- ArkUI 指导：https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-develop-skill/SKILL.md

## 当前交付

2026-11-26 已生成漫画水印清理 v5 与包子漫画横幅去除 v10 的独立导入包。Release SDK 26.0.0.105 的 Debug HAP 构建通过，最低 API 20、目标 API 26；旧 SLBR 原生库和专属声明已移除。ArkTS 静态检查及宿主 JavaScript 语法检查已执行，实机导入、独立开关及真实漫画处理效果待确认。
