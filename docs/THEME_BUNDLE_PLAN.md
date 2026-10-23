# 主题套装开发指南

当前内置 `default`（默认套装）、`paper-study`（纸感书房）、`mist-blue`（雾蓝）和 `ink-wash`（墨山）。套装定义随应用发布；没有外部主题包加载、商城或远程资源依赖。

## 分层与数据流

`ThemeBundleComponent → PreferenceService → AppAppearance → AppTheme / AppColor / HomeTheme / AppMaterial → 页面与组件`。

- `model/AppThemeVisual.ets`：强类型视觉契约，包含语义颜色、背景、图标角色和封面呈现。
- `model/AppThemeBundle.ets`：名称、描述、推荐强调色、材质与视觉定义。定义创建后按只读配置使用，不修改共享定义实现用户自定义。
- `theme/bundles/`：各套装工厂。默认定义保留系统语义色和原资源，纸感定义保留暖纸及书脊，雾蓝使用冷灰蓝纯色背景、线性图标和细边框。
- `theme/ThemeBundles.ets`：唯一注册表；列表、ID 校验、未知 ID 回退共用同一数组。
- `theme/Theme.ets`：保留现有语义入口，读取当前 V2 状态。页面禁止判断具体主题 ID。
- `ThemeBackgroundComponent / ThemeIconComponent / CoverTheme / CoverDecoration`：按能力呈现，不绑定套装名称。

显式 `themeBundleId` 供局部预览使用；空字符串表示跟随当前全局选择。预览与正式页面共用同一资源解析，浏览预览不会发布状态或写 Preferences。未知图标角色回退调用方提供的系统符号。

## 新增一套主题

1. 在 `theme/bundles/` 新建工厂，可参考 `MistTheme.ets`。创建 `AppThemeVisual`，显式填写差异资源，返回 `AppThemeBundle`。保留强类型字段、静态 `$r` 引用，避免字符串拼接资源名和动态对象属性访问。
2. 在 `base/element/color.json` 与 `dark/element/color.json` 添加同名语义颜色。强调色至少包含正常、按下、悬停、弱背景、禁用与 `onBrand`；颜色由系统资源机制随深浅模式解析。
3. 在 `base/media` 添加图标和普通、本地封面；需要深色变体的图片放入 `dark/media` 同名资源。图标用可染色单色填充 SVG，统一 24×24 viewBox。
4. 在 `base/element/string.json` 添加名称和介绍。
5. 在 `ThemeBundles` 导入工厂，并向 `bundles` 数组加入一次调用。列表与 ID 校验自动识别，不需要修改预览、偏好服务或业务页面。
6. 执行主题回归、完整构建和设备验收。增加套装数量时同步测试中的预期数量。

已有能力：

| 配置 | 语义 |
| --- | --- |
| `colors` | 通用背景、表面、三级文字、图标、分隔线、强调色、首页遮罩、详情渐变和设置底色 |
| `background.kind` | `Gradient / Solid / Image` |
| `background.image` | 图片背景资源；Image 模式应提供有效资源 |
| `background.imageOpacity` | 图片叠加透明度，默认 1；配合语义背景色控制笔触对比度 |
| `background.showCoverBackdrop` | 首页、榜单及详情是否使用书封氛围背景；关闭时首页使用套装背景 |
| `icons` | `ThemeIconRole → Resource` 映射；缺少角色时保留系统符号 |
| `cover.decoration` | `None / Border / Spine`；紧凑封面不显示书脊 |
| `cover.illustratedPlaceholder` | 首页、搜索和下载无图项是否统一使用带书名的封面 |
| `cover.playerPlaceholder` | 播放器无封面时的资源 |
| `cover.authorBackground` | 本地书封作者底色，默认透明；作者为空时不绘制底色 |
| `brandedProfileIcons` | 我的页面功能入口是否统一使用当前强调色 |

若确实需要新呈现能力，先扩充对应强类型契约与公共组件，再由定义选择；不要新增 `isMist` 或 `id === 'xxx'` 业务分支。圆角、字号、间距和动效保持原全局设计规范。

墨山是第二个通过该基座接入的新增套装：`InkTheme.ets` 使用 Image 背景、Border 装饰和 10 个图标角色，并启用可选背景透明度和作者底色。公共字段默认保持原主题效果，业务页面没有新增主题条件。设计、生成记录与验收见 [墨山主题](themes/ink-wash.md)。

## 保存、覆盖与边界

沿用 `app_theme_preferences` 单条记录和 `schemaVersion = 1`：

| 字段 | 含义 |
| --- | --- |
| `themeBundleId` | 当前套装 ID |
| `accentColor` | 当前实际强调色；默认套装空值表示默认玫瑰红 |
| `materialStyle` | 当前实际材质，推荐为 3 |

应用套装使用其推荐色和材质；用户可继续在设置中修改并恢复推荐值。当前只保存一组实际选择，**不分别记忆各套装的用户覆盖值**。推荐色与保存值一致时采用该套装的深浅色资源；自定义 HEX 仍沿用原计算逻辑。

偏好写入串行执行，flush 成功后才发布 V2 状态，失败回滚。旧颜色/材质偏好及备份迁移沿用原路径，未知套装回退默认并保留合法覆盖值。新增主题不需要更改存储版本。

- 阅读正文配色、阅读图片、字体和翻页设置独立保存。
- 桌面应用图标由系统及 AppIconService 管理，套装不替换。
- 真实书封与用户自选封面保留原图片；装饰不接收触摸、不写入缓存或书籍字段。
- 阅读与播放弹层继续采用中性色和固定厚材质。
- 沉浸材质当前通过 PlatformCompat 检查 API 26，较低版本走原磨砂路径。
- 桌面卡片没有新增同步链路；wearable 需独立验收。

## 验证

在 PowerShell 中设置本机 Release IDE：

```powershell
$env:DEVECO_HOME = 'C:/Program Files/Huawei/DevEco Studio'
node scripts/test-theme-definitions.cjs
node scripts/test-theme-preferences.cjs
```

`test-theme-definitions` 验证现有语义角色、局部预览隔离、未知主题与图标回退、材质缓存失效、固定弹层材质、资源完整性及雾蓝/墨山文字对比度与墨山深浅图片资源。`test-theme-preferences` 验证所有注册主题的保存、恢复推荐值、重启和备份，同时覆盖旧设置迁移、并发队列与失败回滚。两者是模拟平台的逻辑测试，不替代设备渲染。

本次基座与雾蓝接入：API 26 Release SDK 完整 debug HAP 构建通过（未签名），主题逻辑回归通过。工程原路径含中文，Hvigor 拒绝该路径，因此使用英文临时副本及公共构建模板验证；未修改原工程签名配置。此前纸感首版的真机记录不能作为本次重构或雾蓝主题的真机验收结论。

设备待验收：三套主题来回切换、返回栈中的页面刷新、浅色/深色/跟随系统、首次启动与重启、设置自定义后恢复推荐、真实/本地/失败封面、无障碍点击、窄窗及大屏、API 20–25 降级、阅读与播放进度保持。

## 编码参考

本次读取并使用了在线 [ArkTS 检索指南](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-knowledge-retriever/SKILL.md) 的语言约束资料，以及 [ArkUI 开发指南](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-develop-skill/SKILL.md) 的 V2 状态、组件参数和资源 API 参考。实现保持项目现有 Service 与 V2 分层。
