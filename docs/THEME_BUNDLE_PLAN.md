# 主题套装与制作器

主题套装统一包含配色、页面背景、底部 Tab、功能图标、默认书封和装饰及播放器背景。App、网页、Windows 共用字段表与主题包。自制主题沿用 App 当前的材质强度与底栏样式；阅读器和桌面应用图标继续由原有设置管理。

面向主题作者的操作步骤见 [主题制作说明书](THEME_EDITOR_GUIDE.md)。

交给 AI 生成主题使用 [主题 AI 制作规范](THEME_AI_GUIDE.md)，其中包含完整字段表、浅深默认值、素材要求和 `.jttheme` 打包示例。

## 用户入口

“我的 → 主题与背景 → 套装”展示内置与用户主题。右上角“导入主题”选择文件后进入制作器预览；系统文件管理器打开 `.jttheme` 并选择简听阅读时，App 自动读取该文件并进入同一制作器。导入生成编辑草稿，点击“保存并应用”后保存主题并切换外观，会员权益沿用现有规则。制作主题以当前套装为起点，已保存的自制主题可继续编辑，也可在预览面板删除；删除当前启用主题时先切回默认主题，再清理文件与注册项。制作器提供主题信息、配色、页面背景、底部 Tab、顶部按钮、功能图标、书封装饰、播放器八组。导出在制作器的主题信息内完成。

原生页面使用 ArkUI V2，窄窗上下排列，宽窗左右排列。网页与 Windows 共用 Vite 页面和 Electron 宿主，支持浅深并列预览与点击预览定位编辑项。

## 主题包

扩展名为 `.jttheme`，内容为 ZIP：

```text
manifest.json
theme.json
assets/
```

`manifest.json`：

```json
{ "format": "jianting.theme", "schemaVersion": 1, "theme": "theme.json" }
```

`theme.json`：

```json
{
  "format": "jianting.theme",
  "schemaVersion": 1,
  "id": "custom-example",
  "name": "我的主题",
  "description": "浅色暖纸，深色暖灰",
  "baseThemeId": "default",
  "light": [{ "key": "color.brand", "value": "#C4475B" }],
  "dark": [{ "key": "color.brand", "value": "#EF8DA0" }]
}
```

颜色采用 `#RRGGBB` 或 `#AARRGGBB`，图片值使用 `assets/文件名`。主题字段用有类型的键值数组承载，ArkTS 通过显式赋值映射到现有语义入口。对外 JSON 属性在混淆配置中保留。

## 钩子

| 主题键 | 含义 |
| --- | --- |
| `color.*` | 页面、表面、文字、图标、品牌、控件、首页和详情颜色 |
| `background.common.*` | 通用背景 |
| `background.home/shelf/record/profile.*` | 四个主页面背景，支持跟随通用 |
| `background.player.*` | 播放器背景：cover、solid、image |
| `background.*.image/color/veil/blur/positionX/positionY/scale` | 素材、底色、蒙层、模糊与图片裁剪 |
| `background.profileCard` | 我的账号卡图片 |
| `background.coverBackdrop` | 首页与详情书封氛围开关 |
| `tab.home/shelf/record/profile.normal/selected` | 四个 Tab 的常态及选中图片 |
| `tab.normalColor/selectedColor` | Tab 状态配色 |
| `icon.Search/Filter/Grid/List/ChevronRight` | 已接入的功能图标 |
| `button.shelf.*` | 书架顶部及书房分组面板的整按钮图片与切换状态 |
| `button.record.*` | 记录页返回、筛选、摘录、历史、编辑／完成／锁定的整按钮图片 |
| `cover.placeholder/localPlaceholder/playerPlaceholder` | 三种默认封面 |
| `cover.title/localTitle/author/authorBackground/label/edge` | 默认封面文字与装饰颜色 |
| `cover.decoration/illustratedPlaceholder` | 边框、书脊与书名排版 |

完整字段与默认值位于 `entry/src/main/resources/rawfile/theme_editor_schema.json`。文案位于 `entry/src/main/resources/base/element/theme_editor.json`，三端直接读取。

字段表共 135 项：配色 36、页面背景 42、Tab 10、顶部按钮 23、功能图标 5、书封装饰 11、播放器 8。主题名称、说明、材质和底栏布局在主题信息中设置。背景编辑项按当前模式展示；书封模式提供底色、模糊与蒙层，图片模式另提供图片焦点与缩放。

顶部按钮使用 `ThemeButtonRole` 与 `AppThemeVisual.buttons` 映射，由 `ImmersiveCircleButton` 在已有点击区域显示完整透明图片，包含图标和底板。图片按原色、方形画布显示，页面保留原有事件及长按逻辑。字段为空时使用原有按钮，各状态分别读取对应字段。App、网页和 Windows 的“顶部按钮”编辑组支持按页面编辑和状态预览。复杂背景及插画使用 PNG／WebP，简洁图标可使用 SVG。

材质强度与底栏样式归 App 当前偏好管理，应用自制主题时继续沿用。三端制作器只编辑主题内容，导入旧包时忽略 `materialStyle` 和 `verticalBottomTabs`，再次导出只保留当前契约字段。网页预览表达布局关系，原生材质以设备显示为准。

Tab 的 SVG 素材在导入、创建草稿及加载已安装主题时解码为 112×112 PNG，原生底栏继续显示原色图片，并保留浅深色与常态／选中状态。转换依据 [ArkUI 背景图片接口](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-arkui/arkui-ts/ts-universal-attributes-background.md)的格式范围，沿用原生 HDS 标签及收展行为。

## App 接入

- `ThemeDocument`：三端文档、键值项、编辑草稿和背景模型。
- `ThemePackageService`：图片选择、主题包读写、草稿、保存及自定义主题删除。App 内文件选择与外部授权 URI 共用主题解包入口；启动时从 `filesDir/themes/<id>/` 加载已保存主题。
- `ThemeBundles`：内置工厂和动态主题共同注册，分别建立浅深外观。
- `ThemeDocumentResolver`：语义颜色、图片与背景的明确映射。
- `AppAppearance`：V2 外观状态，发布系统模式和套装更新。
- `ThemeEditorPage / ThemeEditorPreview`：原生编辑及预览，通过 `ThemeEditorRoute` 接收已导入草稿。外部主题文件复用 `FileOpenRouting → EntryAbility → Index` 的冷启动待处理路由与热启动事件，保留原始授权 URI。
- `ThemeBackdropComponent`：页面与播放器图片裁剪、模糊、蒙层。
- `MainPage`：常态／选中图标及底部连续背景。

内置套装使用原有工厂，用户从内置套装创建时将浅深颜色和图片写入草稿，以便完整导出。

旧 `app_backgrounds` 与 `bottom_tab_icons` 数据继续用于旧选择；当前主题制作为新套装时带入已有图片，纸色与雾色预设分别转为浅深渐变素材。新应用记录的 `schemaVersion=2` 表示按套装统一呈现，旧选择记录版本 1 继续使用旧覆盖项。设置页中，自制套装的主题色入口直接打开制作器。

导出时组装主题文档和实际引用的素材，编辑中替换过的素材留在草稿目录，随草稿结束清理。

播放器的章节、进度、封面加载和控制逻辑沿用现有服务。播放器自选背景单独进入背景层。真实书籍封面沿原有链路展示；默认封面及书封装饰由套装控制。

## 网页与 Windows

源码位于 `tools/theme-editor`：

```powershell
npm install
npm run dev
npm run build
npm run setup:desktop
npm run desktop
npm run package:win
```

网页产物位于 `dist/`，Windows 便携版位于 `release/`。GitHub Pages 工作流构建并发布到 `https://hos-book.github.io/HarmonyOS-book/theme-editor/`。主题文件可在三端导入并继续编辑。

网页与 Windows 预览由 `src/preview.js`、`src/preview.css` 分别绘制五个页面，结构参照当前 App 页面和组件。窗口预设使用实际 vp 尺寸后整体缩放，背景图片沿用 `ThemeBackdropComponent` 的裁剪、缩放及焦点算法；支持书架三种视图和迷你播放器、底栏排列预览，布局选择仅用于查看效果。

## 实施依据

使用在线 ArkUI 开发、深浅色适配、ArkTS 语法检查和接口迁移资料，并结合本机 Release SDK 26.0.0.105 声明。最低 API 20，现有高版本材质继续经 `PlatformCompat` 选择。

- [ArkUI 开发](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-develop-skill/SKILL.md)
- [深浅色适配](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-dark-light-adaptation/SKILL.md)
- [V2 颜色模式更新](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-dark-light-adaptation/references/compatibility.md)
- [ArkTS 语法检查](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-syntax-checker/SKILL.md)
- [接口迁移](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-deprecated-interface-checker/SKILL.md)

本轮已完成最终接入文件的 ArkTS 静态检查、Release SDK 26.0.0.105 下的 App Debug 完整构建、网页生产构建及 Windows x64 便携版打包。App 已安装并启动于 HUAWEI Mate 80。本机网页通过端口 5173 提供访问。静态诊断保留平台适配提示及现有警告；设备视觉与三端文件交互尚待实际运行确认。
