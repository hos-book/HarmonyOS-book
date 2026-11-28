# 预览图标资源

HMSymbol 字体与状态栏 PNG 来自 HarmonyOS Agent Skills 的移动端视觉资源，授权见 `public/HARMONY-RESOURCES-LICENSE.txt`，构建时随网页和 Windows 页面一起分发。

- 技能：https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/01-design/mobile/hmos-design-visual-mobile/SKILL.md
- 字体映射：https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/01-design/mobile/hmos-design-visual-mobile/references/0.governance/hmsymbol-map.json
- 状态栏结构：https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/01-design/mobile/hmos-design-visual-mobile/references/4.template/statusbar-tem.html

`src/symbols.json` 保留本页面使用的符号名称与码点。书架和筛选图形使用 App 现有 SVG；默认书封、本地书封和应用图标直接引用 App 资源。

页面结构和尺寸以项目 HomePage、FavoritePage、ReadingStatsPage、ProfilePage、PlayerPage、MainPage 及其组件为依据。网页使用 CSS 表达光感材质，设备渲染效果以 App 为准。
