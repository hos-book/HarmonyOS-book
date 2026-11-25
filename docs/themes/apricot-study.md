# 杏笺书斋

`apricot-study` 是浅杏暖米色书斋主题，沿用现有主题套装、V2 状态、局部预览与偏好保存入口。

## 视觉设计

| 角色 | 浅色 | 深色 |
| --- | --- | --- |
| 页面 | 浅杏宣纸 `#F5F0E6` | 暖炭灰 `#242321` |
| 卡片 | 暖米白 `#FAF7EF` | 灰茶 `#2E2D29` |
| 主文字 | 灰茶褐 `#514B41` | 暖米灰 `#E3DED3` |
| 辅助文字 | 灰褐 `#7B7264` | 米褐 `#B8AE9D` |
| 强调色 | 柔金 `#857050` | 浅暖金 `#C4B08B` |
| 印章 | 淡朱砂 `#A67867` | 暗朱砂 `#9C7768` |

首页以边角杏枝、淡日与低位远山构图；书架保留轻窗影；记录采用平缓淡山；个人卡片以杏枝和细金线收边。纸纹降低密度与对比度，中央内容区保持干净留白，页面背景自然延伸至底部。

默认封面包含线装书脊、竖式“杏笺书斋”题签与“藏书”小印。本地封面为现有书名与作者槽位留出空间，文字仍由 `LocalBookCover` 实时排版。真实书封与用户自选图片沿用既有优先级。

图标复用纸感书房的十个单色矢量角色，通过主题强调色呈现。圆角、字号、间距、沉浸材质、记录胶囊裁剪和点击行为沿用现有组件。阅读纸张、桌面图标、自选背景与自选 Tab 图标继续独立管理。

应用任意套装、恢复默认套装和恢复推荐主题色均保留用户当前材质档位。材质仅由设置页的材质选项管理，套装自定义标记只依据强调色。

## 资源与接入

- 工厂：`entry/src/main/ets/theme/bundles/ApricotTheme.ets`。
- 注册：`entry/src/main/ets/theme/ThemeBundles.ets`。
- 深浅色：`entry/src/main/resources/{base,dark}/element/color.json` 的 `theme_apricot_*`。
- 名称和介绍：`base/element/string.json` 的 `theme_bundle_apricot_*`。
- 图像：`base/media` 与 `dark/media` 各包含背景、书架、记录、个人卡片、普通封面、本地封面六个同名静态 WebP。

素材源程序为 `scripts/build-apricot-theme-assets.py`。矢量构图与宋体题签在构建素材时由 resvg 离线栅格化，再由 Pillow 编码为 WebP；应用直接加载静态像素图片。页面图片为 900×1600，个人卡片为 900×420，书封为 360×504。重绘命令：

```powershell
python scripts/build-apricot-theme-assets.py
```

生成环境需要 `fontTools`、`Pillow`、`resvg-py` 和 Windows 宋体，其他字体路径可通过 `--font` 指定。

## 完成情况

2026-11-25：十二份深浅色素材已替换为静态 WebP，并完成浅色记录背景、普通书封和深色背景的本机查看。主题定义、应用逻辑与自定义提示已完成 ArkTS 检查；PreferenceService 存在原有异常处理提示。Release SDK 26.0.0.105 的 Debug 构建成功，签名 HAP 已安装至 HUAWEI Mate 80 并启动。持续流畅度仍待实机反馈。

## 实现依据

本次读取在线 ArkUI 开发技能、ArkTS 语法资料和深浅色适配技能。主题以显式类型和静态资源引用接入；浅色与深色使用同名资源，继续通过现有组件解析。

- https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-develop-skill/SKILL.md
- https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-develop-skill/references/quick-rules/00-arkts-syntax.md
- https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-dark-light-adaptation/SKILL.md
- https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-dark-light-adaptation/references/adaptation.md
