# 主题套装首版实施记录

日期：2026-10-23。状态：首版代码与素材已接入，主题偏好回归及 Release 工具链 debug HAP 构建通过；最新修复包已在 HUAWEI Mate80 / API 26 完成安装、重启恢复、套装来回切换及首页和预览深色显示验证，其余专项与跨设备验收见下文。

## 已实现范围

沿用“我的 → 主题 → 主题套装”，内置 `default`（默认套装）和 `paper-study`（纸感书房）。首版复用现有 `AppAppearance`、`Theme`、`PreferenceService` 和封面组件，没有新增后端接口、数据库表或 ViewModel 层。

用户确认的封面范围为“默认封面＋所有书封的边框、书脊等样式”。真实书封和用户自选图片保留原地址，主题占位仅用于无图或图片加载失败；框内装饰不写入书籍图片、缓存或自定义封面记录。

| 范围 | 首版实现 |
| --- | --- |
| 选择入口 | `MembershipPage` 的主题套装 Tab 使用 `ThemeBundleComponent`，提供卡片局部预览、应用、当前选中标记、恢复推荐外观与默认套装 |
| 共享状态 | `AppAppearance.themeBundleId/accent/material` 使用 V2 响应式状态，保存后更新既有界面 |
| 默认封面与装饰 | `CoverTheme`、`CoverDecoration` 统一占位、文字、边框和书脊；通用、本地及播放封面沿用原加载链路 |
| 主体背景 | `AppTheme`、动态 `HomeTheme` 和 `ThemeBackgroundComponent` 接入背景、表面、文字、分隔线和底栏遮罩 |
| 首页图标 | `ThemeIcons` / `ThemeIconRole` / `ThemeIconComponent` 解析搜索、筛选、网格/列表、箭头、分类及四个主 Tab 图标 |
| 保存和备份 | Preferences 单条版本化记录保存完整选择；兼容旧偏好，备份增加 `themeSelection` |

## 页面 → 接口 → 存储

每张卡片包含名称、说明和局部预览。预览读取候选套装，不修改全局状态；只有点击“应用套装”才保存。卡片按容器宽度布局：小于 600vp 为单列，其余双列。应用期间禁用重复提交，保存失败显示提示。

当前套装实际颜色或材质与推荐值不同时，显示“已自定义”，可以恢复当前套装推荐值；恢复默认套装同时恢复默认推荐颜色和材质。桌面应用图标仍由相邻 Tab 和 `AppIconService` 管理。

| 接口 | 职责 |
| --- | --- |
| `ThemeBundles.list()` / `resolve(id)` | 返回内置套装和推荐值，未知 ID 解析为默认套装 |
| `PreferenceService.applyThemeBundle(id)` | 校验可用套装，保存推荐颜色和材质，再更新共享状态 |
| `PreferenceService.resetThemeBundleOverrides()` | 将当前实际颜色和材质恢复为所选套装推荐值 |
| `PreferenceService.setAccentColor()` / `setMaterialStyle()` | 保留套装选择，在同一记录内更新实际颜色或材质 |
| `AppTheme` / `CoverTheme` / `ThemeIcons` | 分别解析页面颜色与背景、默认封面与装饰、功能图标 |

Preferences 的 `app_theme_preferences` 保存序列化的 `AppThemeSelection`：

| 字段 | 含义 |
| --- | --- |
| `schemaVersion` | 当前为 1 |
| `themeBundleId` | 当前套装 ID，默认 `default` |
| `accentColor` | 用户当前实际颜色；默认套装的空字符串表示默认玫瑰红 |
| `materialStyle` | 用户当前实际材质档位，推荐值为 3（均衡） |

首版保存实际值，没有额外的 `accentOverride/materialOverride` 字段。新记录缺失或无效时读取原 `accent_color/material_style`，保留升级前外观；未知套装 ID 回退默认，并规范化合法颜色和材质。写入操作串行执行，保存成功后才发布 V2 状态；失败恢复 Preferences 中的原记录。

系统设置备份通过 `themeSelection` 包含完整选择。旧备份没有该字段时，使用默认套装及其原有颜色、材质字段恢复。现有 `color_mode` 继续独立管理浅色、深色和跟随系统。

## 纸感书房与公共钩子

纸感书房采用暖纸背景、墨绿强调色、植物细线默认书封和本地藏书封面；深色资源使用深炭纸与更明亮的绿调前景。背景和两种默认封面各提供 base/dark 两份，10 个功能图标使用可染色 SVG；16 个 SVG 合计约 9.9 KB，不依赖外部下载、动画或滤镜。

封面通过 `CoverImage`、`LocalBookCover`、`PlayerCoverImage`、`EnhancedPlayerCover` 及相关显示分支接入。常规封面使用框内书脊和边框，紧凑封面只保留细边框；沿用原展示尺寸、圆角和场景布局。图片加载、缓存、AI 超分、原始比例回调和用户自选封面的优先级仍由原组件负责。

主体背景覆盖书源首页、全网榜单、主 Tab 容器及书架、记录、我的、搜索、详情、设置和主题页等主要页面。纸感首页关闭书封氛围叠层，使用统一静态背景和相应前景颜色。播放器的封面氛围、阅读页纸张配色与本次 App 背景分别管理。

首页图标按 `ThemeIconRole` 解析。默认套装保留系统 symbol，纸感套装使用内置单色 SVG；现有按钮事件、点击区和无障碍名称继续由原控件维护。底部导航保留 `MainPage.buildTabBar()` 和原导航结构，不通过重建页面应用皮肤。

新主题注册入口集中在 `ThemeBundles`；增加更多视觉方案时，同时扩展公共的背景、封面与图标解析器及对应资源。首版不是外部主题包格式或主题商城。

## 实施状态与验收

| 阶段 | 当前状态 |
| --- | --- |
| 定义、默认套装、持久化和旧偏好兼容 | 已接入代码 |
| 默认封面、书脊与边框公共钩子 | 已接入主要封面场景 |
| 主体背景、两种首页及功能图标 | 已接入代码和深浅资源 |
| 套装预览、应用、恢复及备份 | 已接入代码 |
| 主题偏好回归、ArkTS、构建与设备交互验收 | 已完成下表所列验证，其余场景待验收 |

本次验证记录：

| 验证项 | 实际结果与覆盖范围 |
| --- | --- |
| 主题偏好回归 | `test-theme-preferences` 全部通过 |
| ArkTS 静态检查 | 核心主题及修复文件无错误；批量页面检查在 300 秒超时，未取得全量静态检查通过结果 |
| 完整 debug HAP 构建 | Release IDE 26.0.0.105 构建成功；产物模块元数据 `apiReleaseType=Release`，最低 API 20、目标 API 26 |
| 构建工具回退 | `build_project` 因 OHPM bat 递归失败，改用 Release IDE 的 Node/Hvigor 和 `--no-daemon` 完成构建 |
| 最新修复包安装与恢复 | HUAWEI Mate80 / API 26 已重新安装启动，重启后保留纸感书房 |
| 套装切换与页面显示 | 默认套装 ↔ 纸感书房来回切换通过，背景、图标和当前使用状态即时刷新；首页、书架、我的和设置实际显示正常，原网络书封保留 |
| 封面装饰溢出修复 | `CoverImage` 装饰溢出修复后重新通过对应检查与构建；66×92 预览边界已在最新包真机复核 |
| 深色显示 | 深色首页以及套装内普通、本地两种默认封面预览均可读；验证后恢复原“跟随系统”模式，保留纸感书房便于体验 |
| 首页交互 | 实际执行下拉刷新和滚动，未发现主题装饰遮挡交互；双击回顶的自动手势未可靠确认，不计通过 |
| 手机模拟器 | 尝试启动失败，虽然工具返回 exit 0，但未取得可验证运行状态，不计设备验证结果 |

本机截图证据：[浅色首页](../.codex-tmp/theme-device/paper-home-final.png)、[深色首页](../.codex-tmp/theme-device/paper-home-dark.png)、[修复后的封面预览](../.codex-tmp/theme-device/paper-preview-fixed.png)、[深色封面预览](../.codex-tmp/theme-device/paper-preview-dark.png)。

其余待验收重点：

- 设置页自定义颜色和材质后恢复推荐值；浏览预览不影响当前主题。
- 本地图、rawfile、图片加载失败和自选图片的封面；状态标记与超分完成后的装饰表现。已验证的网络书封保留、默认封面预览和边界不替代这些场景。
- 首页不同来源模式、书架网格/列表切换及返回栈中的页面更新；筛选、导航、播放/朗读和阅读进度保留。双击回顶、编辑及长按操作仍待专项验证。
- 其他页面深浅模式的文字、图标和底栏对比度；窄窗口、横屏、折叠和桌面窗口改变时布局正常。
- 旧偏好、旧备份、未知套装 ID、连续保存及保存失败在设备上的兼容与回退；已通过的偏好回归不替代设备验证。
- API 20 兼容分支以及平板、折叠屏、2in1 等其他设备；与已完成的 HUAWEI Mate80 / API 26 验证分别记录。

桌面卡片没有新增套装同步链路；标准 wearable 和其他设备的视觉效果需要各自验证，手机验证不能替代。

## 在线依据

本次已读取在线目录与实际相关文档，代码遵循项目 ArkUI V2 和 API 20 兼容要求：

- [ArkTS 语法规则](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)：显式类型、静态字段访问与声明式 UI 约束；其中 V1 示例以项目 V2 规范覆盖。
- [ArkUI 知识检索](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md)：状态、主题资源与版本依据的路由入口。
- [@ObservedV2 与 @Trace](https://api.gitcode.com/api/v5/repos/HarmonyOS_Skills/harmonyos-agent-skills/git/blobs/1b2b4ea0ea53f1ec250d8b9a3fea7006804a2019)：在内存解码阅读，关联属性驱动现有组件刷新。
- [应用内主题换肤](https://api.gitcode.com/api/v5/repos/HarmonyOS_Skills/harmonyos-agent-skills/git/blobs/a907760b3e17b5361d4e24f82e6dabc35eb4033a)、[应用深浅色适配](https://api.gitcode.com/api/v5/repos/HarmonyOS_Skills/harmonyos-agent-skills/git/blobs/2d0a2f1a4d98cc80da8a172bd60380e94541fa23)：规划阶段已通过 Git Blob API 阅读，作为颜色与 base/dark 资源适配依据。

文档可用和代码已接入不表示对应工作流已完成设备验证。
