**简听主题 AI 制作规范**

把这份文件与主题风格要求一起交给 AI，即可按当前协议制作简听阅读主题。文档包含完整的 135 个主题字段、浅深默认值、素材规则、文件结构和打包方法，可独立使用。

适用范围：App、网页及 Windows 主题制作器。套装包含配色、主页面背景、底部 Tab、书架与记录页的顶部按钮、功能图标、默认书封与装饰、播放器背景。材质强度与底栏样式沿用 App 当前偏好。阅读器继续使用独立设置；桌面应用图标由应用资源管理。App 保存和应用自制主题沿用现有会员权益。

协议标识为 `jianting.theme`，主题包版本为 `schemaVersion: 1`。本文依据当前项目的字段表及包读写实现整理。

制作时按用途选择素材格式：复杂页面背景、播放器背景、插画和书封优先使用 PNG／WebP；简洁 Tab 与功能图标可使用 SVG。像素画风同样可以通过位图保留，素材性能同时取决于像素尺寸、图形复杂度和 App 渲染方式。

**直接复制给 AI 的提示词**

将下面的提示词连同本文件一起发送，方括号内填写自己的要求。

```text
请依据随附《简听主题 AI 制作规范》，为简听阅读制作一套可导入的 .jttheme 主题。

主题名称：[例如：林间微光]
主题标识：[例如：custom-forest-glow]
风格关键词：[例如：森林、晨雾、柔和、手绘]
浅色主色：[例如：苔绿搭配暖米白]
深色主色：[例如：松墨绿搭配柔金色]
背景素材：[例如：PNG／WebP 低对比植物插画，中部为文字和卡片留出空间]
Tab 图标：[例如：首页、书架、记录、我的，透明底简洁双态图标]
功能图标：[例如：与 Tab 使用统一线条和配色]
顶部按钮：[例如：书架与记录页分别绘制透明 PNG，图标和底板合成整按钮，切换状态单独绘制]
默认书封：[例如：PNG／WebP 暖纸与叶片插画，由 App 叠加书名]
播放器背景：[例如：PNG／WebP 独立夜林插画；也可选跟随书封或纯色]
材质强度与底栏样式：沿用 App 当前设置。

请完成以下交付：
1. 设计浅色和深色两套配置，分别写入 light、dark。
2. 使用 baseThemeId: "default"，依据完整字段表填写每组 135 个字段，每个 key 出现一次；图片字段按实际使用的素材填写，采用内置效果时填空字符串。
3. 所有主题字段的 value 使用字符串；顶层字段按下方协议填写。材质强度与底栏样式由 App 当前设置决定。
4. 复杂背景、播放器插画和默认书封优先交付 PNG／WebP。像素画、密集纹理及由大量图形组成的插画，在制作端合成为位图后入包；已有 SVG 创作源稿在导出阶段栅格化。
5. 四个 Tab 分别提供常态和选中图片，保持统一画布、视觉大小和对齐方式；图标保留原色。简洁图标可使用少量路径或基础图形组成的静态 SVG，细节丰富的图标使用透明 PNG／WebP。
6. 按目标显示区域、裁剪和缩放需求选择素材像素尺寸。纯色背景直接使用主题字段；固定装饰、纹理和插画阴影合入素材。
7. 图片路径统一使用 assets/文件名，素材直接放在 assets 目录中，浅深模式可共享素材或分别制作。theme.json 引用实际导出的图片格式。
8. 按本文协议生成 manifest.json、theme.json 和引用的所有素材，打包为 主题名称.jttheme。
9. 书架和记录页顶部按钮使用 button.shelf.*、button.record.* 独立字段。每张透明 PNG／WebP 包含完整图标和底板；浅深模式及搜索展开、已选分组、视图切换、编辑／完成／锁定等状态按字段表分别制作。相同外观的状态可引用同一素材。
10. 提供可下载的 .jttheme 文件、设计说明和手机导入步骤。

当前环境具备文件生成能力时，请直接生成并提供主题文件。
当前环境仅支持文本时，请给出完整 manifest.json、完整 theme.json、位图素材生成或栅格化脚本、简洁 SVG 图标源码和打包脚本，并列出依赖与执行命令。脚本应生成主题引用的全部 PNG／WebP 素材，再打包为 .jttheme；将尚待用户执行的步骤写清楚。
创作范围覆盖主页面、Tab、顶部按钮、功能图标、默认书封、材质与播放器背景；阅读器沿用自身设置。
```

**交付物与包结构**

`.jttheme` 是 ZIP 压缩文件，扩展名为 `.jttheme`。压缩包根层直接放置 `manifest.json`、`theme.json` 与 `assets/`。下面的素材名称仅展示命名方式，实际素材由设计方案决定。

```text
林间微光.jttheme
├── manifest.json
├── theme.json
└── assets/
    ├── background-light.png
    ├── background-dark.png
    ├── player-light.png
    ├── player-dark.png
    ├── tab-home-normal.svg
    ├── tab-home-selected.svg
    ├── tab-shelf-normal.svg
    ├── tab-shelf-selected.svg
    ├── tab-record-normal.svg
    ├── tab-record-selected.svg
    ├── tab-profile-normal.svg
    ├── tab-profile-selected.svg
    ├── icon-search.svg
    ├── icon-filter.svg
    ├── icon-grid.svg
    ├── icon-list.svg
    ├── icon-chevron-right.svg
    ├── button-shelf-search.png
    ├── button-shelf-search-active.png
    ├── button-record-filter.png
    ├── button-record-filter-active.png
    ├── cover-default.png
    ├── cover-local.png
    └── cover-player.png
```

`manifest.json` 内容固定为：

```json
{
  "format": "jianting.theme",
  "schemaVersion": 1,
  "theme": "theme.json"
}
```

两个 JSON 文件使用 UTF-8 编码和标准 JSON 语法。包结构是压缩内容的根目录；制作目录的名称留在包外。

**theme.json 顶层字段**

| 字段 | JSON 类型 | 取值与用途 |
| --- | --- | --- |
| `format` | 字符串 | 固定 `"jianting.theme"` |
| `schemaVersion` | 数字 | 固定 `1` |
| `id` | 字符串 | 主题标识，建议 `custom-英文短名`，如 `custom-forest-glow`；App 导入时生成本地标识 |
| `name` | 字符串 | 用户看到的主题名称 |
| `description` | 字符串 | 主题说明 |
| `baseThemeId` | 字符串 | AI 新主题使用 `"default"`，其上叠加本文件定义的字段 |
| `light` | 数组 | 浅色字段，元素为 `{"key":"字段名","value":"字段值"}` |
| `dark` | 数组 | 深色字段，格式与 `light` 相同 |

`light` 与 `dark` 分别读取各自的字段。生成完整主题时，按后文 135 项表格分别填写两组，使用表中浅色值与深色值作为创作起点。每组内每个键保留一条，图片可按实际设计填入路径或空字符串。

所有字段项的 `value` 都是字符串，例如 `"40"`、`"true"`、`"0"`。顶层的 `schemaVersion` 使用数字。材质强度与底栏样式由 App 当前偏好管理；旧包携带的 `materialStyle`、`verticalBottomTabs` 在导入时忽略，再次导出时移除。

主题包的版本为 `1`。App 内部外观选择记录的版本属于另一份存储协议。

**结构示例**

下面展示顶层结构与常用字段的写法。正式交付按完整字段表补齐浅深两组，并提供每个图片引用对应的素材。

```json
{
  "format": "jianting.theme",
  "schemaVersion": 1,
  "id": "custom-forest-glow",
  "name": "林间微光",
  "description": "暖纸苔绿的白昼，松墨柔金的夜色",
  "baseThemeId": "default",
  "light": [
    { "key": "color.brand", "value": "#50765B" },
    { "key": "color.textPrimary", "value": "#27372D" },
    { "key": "background.common.mode", "value": "image" },
    { "key": "background.common.image", "value": "assets/background-light.png" },
    { "key": "background.common.color", "value": "#F3F1E6" },
    { "key": "background.common.veil", "value": "20" },
    { "key": "background.home.mode", "value": "common" },
    { "key": "background.player.mode", "value": "cover" },
    { "key": "background.player.color", "value": "#253E30" },
    { "key": "background.player.blur", "value": "40" },
    { "key": "background.player.veil", "value": "70" },
    { "key": "tab.home.normal", "value": "assets/tab-home-normal.svg" },
    { "key": "tab.home.selected", "value": "assets/tab-home-selected.svg" },
    { "key": "tab.normalColor", "value": "#68766A" },
    { "key": "tab.selectedColor", "value": "#50765B" },
    { "key": "button.shelf.search", "value": "assets/button-shelf-search.png" },
    { "key": "button.shelf.searchActive", "value": "assets/button-shelf-search-active.png" },
    { "key": "button.record.filter", "value": "assets/button-record-filter.png" },
    { "key": "button.record.filterActive", "value": "assets/button-record-filter-active.png" },
    { "key": "cover.decoration", "value": "2" },
    { "key": "cover.illustratedPlaceholder", "value": "true" }
  ],
  "dark": [
    { "key": "color.brand", "value": "#B6C997" },
    { "key": "color.textPrimary", "value": "#E9EDDF" },
    { "key": "background.common.mode", "value": "image" },
    { "key": "background.common.image", "value": "assets/background-dark.png" },
    { "key": "background.common.color", "value": "#17231B" },
    { "key": "background.common.veil", "value": "25" },
    { "key": "background.home.mode", "value": "common" },
    { "key": "background.player.mode", "value": "cover" },
    { "key": "background.player.color", "value": "#18261D" },
    { "key": "background.player.blur", "value": "40" },
    { "key": "background.player.veil", "value": "70" },
    { "key": "tab.home.normal", "value": "assets/tab-home-normal.svg" },
    { "key": "tab.home.selected", "value": "assets/tab-home-selected.svg" },
    { "key": "tab.normalColor", "value": "#B0B8AA" },
    { "key": "tab.selectedColor", "value": "#B6C997" },
    { "key": "button.shelf.search", "value": "assets/button-shelf-search.png" },
    { "key": "button.shelf.searchActive", "value": "assets/button-shelf-search-active.png" },
    { "key": "button.record.filter", "value": "assets/button-record-filter.png" },
    { "key": "button.record.filterActive", "value": "assets/button-record-filter-active.png" },
    { "key": "cover.decoration", "value": "2" },
    { "key": "cover.illustratedPlaceholder", "value": "true" }
  ]
}
```

**颜色与素材约定**

- 颜色格式为 `#RRGGBB` 或 `#AARRGGBB`。八位写法的前两位是透明度，`00` 表示全透明，`FF` 表示完全实色；`#80FFFFFF` 表示约半透明白色。
- 图片字段填写包内相对路径，例如 `assets/tab-home-selected.svg`。路径使用正斜杠，大小写与实际文件名保持一致。
- 素材直接放在 `assets/` 这一层目录，文件名建议使用英文字母、数字与连字符。
- 协议支持 PNG、JPEG、WebP 和 SVG。制作时按下表选择格式：复杂画面使用位图，简洁图标可使用 SVG。
- 图片格式转换通过实际渲染或编码完成，再同步修改字段引用和文件名。例如将 SVG 插画栅格化为 PNG 后，字段填写 `assets/background-light.png`。
- 图片字段为空字符串时使用基础套装或对应控件原有表现。选择图片背景时，同时填写对应的 `.image` 素材路径。
- 浅深模式可引用同一个文件，也可使用两套素材。分享包内放入两组字段实际引用的全部文件。
- 素材尺寸属于设计选择：Tab 和功能图标建议方形透明画布；页面背景重点考虑窗口裁剪；在线及本地默认书封建议竖版，播放器默认书封建议方形。主体位置可通过背景参数调整。

**素材格式与绘制成本**

| 素材用途 | 推荐交付格式 | 制作方式 |
| --- | --- | --- |
| 主页面、播放器的复杂背景 | PNG／WebP | 将插画、像素块、纹理与固定装饰合成为一张位图 |
| 默认书封、账号卡插画 | PNG／WebP | 在制作端完成细节绘制，按展示比例导出 |
| 简洁 Tab、搜索、筛选等图标 | SVG 或透明 PNG／WebP | SVG 采用少量路径或基础图形，统一画布和视觉中心 |
| 细节丰富的图标 | 透明 PNG／WebP | 保留透明背景，将复杂图形合成为位图 |
| 书架与记录页顶部整按钮 | 透明 PNG／WebP | 将图标和底板合成一张方形画布，保留外围透明区域；每个按钮及状态分别引用 |
| 纯色背景 | 主题字段 | 使用 `mode: "solid"` 与对应 `color`，直接表达底色 |

主题包体积反映压缩后的存储大小。SVG 还包含待解析和绘制的图形；大量矩形、路径或装饰即使压缩得很小，仍会增加渲染工作。复杂插画优先在制作端完成栅格化，让 App 加载最终位图。SVG 创作源稿可单独保留，主题包放入字段实际引用的成品素材。

简洁 SVG 使用明确的 `viewBox`、颜色和自包含的静态路径。密集像素块、重复纹理、复杂滤镜及多层固定装饰统一在导出阶段合成为 PNG／WebP。像素画可先在目标像素网格绘制，再以整数倍、最近邻方式放大并导出 PNG 或无损 WebP，以保留清晰方块边缘。

位图像素尺寸依据目标显示区域、裁剪比例和缩放需求确定；更大的像素面积也会增加解码后的内存占用。固定的插画阴影与柔化效果可合入成品图片，主题中的实时 `blur` 按需要设置。主题包协议继续使用原有字段和参数范围，以上规则用于指导素材制作。

具备图片生成能力的 AI 直接输出位图素材。仅输出文本的 AI 应提供能生成这些位图的完整脚本；以 SVG 作为中间源稿时，脚本包含栅格化步骤、依赖和运行命令，再将生成的 PNG／WebP 与 JSON 一起打包。交付说明应区分已生成的文件和等待用户运行的脚本。

素材选择用于降低绘制开销；实际滑动流畅度还取决于 App 的布局、刷新与图片渲染实现，效果以设备呈现为准。

**字段的实际作用**

背景参数采用 `background.场景.参数`。通用场景为 `common`，四个主页面为 `home`、`shelf`、`record`、`profile`，播放器为 `player`。

| 场景 | 可用模式 | 作用 |
| --- | --- | --- |
| 通用 | `theme` / `solid` / `image` | 采用基础套装背景、纯色或图片 |
| 四个主页面 | `common` / `theme` / `solid` / `image` | 跟随通用，或单独采用基础套装、纯色、图片 |
| 播放器 | `cover` / `solid` / `image` | 跟随当前书封、纯色或自选图片 |

页面选择 `common` 时，整组背景参数取自 `background.common.*`。页面的独立参数在选择 `solid` 或 `image` 时使用。`theme` 使用基础套装背景，并由其已接入的 `color.*` 字段参与配色。

| 参数 | 数值范围 | 含义 |
| --- | --- | --- |
| `color` | 颜色字符串 | 背景底色 |
| `veil` | 0–90 | 蒙层强度；主页面浅色模式用白色蒙层、深色模式用暗色蒙层；播放器使用暗色蒙层 |
| `blur` | 0–60 | 图片或播放器书封背景的模糊强度 |
| `positionX` | 0–100 | 图片水平位置：0 左、50 中、100 右 |
| `positionY` | 0–100 | 图片垂直位置：0 上、50 中、100 下 |
| `scale` | 100–180 | 图片缩放百分比；100 为填满背景后的基础大小 |

播放器 `cover` 模式读取当前书籍封面，使用底色、模糊与蒙层；`solid` 使用底色与蒙层；`image` 另使用包内图片、水平位置、垂直位置和缩放。播放器文字及控制区域采用 App 原有呈现，背景设计需为文字与按钮留出清晰区域。

四个 Tab 分别配置 `.normal` 与 `.selected` 图片。图片保留素材原色，`tab.normalColor` 与 `tab.selectedColor` 作用于文字和系统符号。选中图片为空时沿用常态图片；两张图片均为空时沿用基础图标。双态素材宜使用一致的画布和视觉中心。

功能图标的精确键名是 `icon.Search`、`icon.Filter`、`icon.Grid`、`icon.List`、`icon.ChevronRight`，大小写按字段表填写。

**顶部整按钮的绘制与状态**

`button.shelf.*` 与 `button.record.*` 接管对应按钮的完整外观。图片包含图标、底板、描边及固定装饰，透明部分露出页面背景。App 按素材原色、等比包含方式显示，主题素材自己决定轮廓。主工具栏使用 36 vp 方形区域，书房分组面板的按钮使用 30 vp 方形区域；图片按目标设备像素密度准备清晰的方形画布。

App 保留原有点击范围、菜单、搜索展开、长按和编辑逻辑，按下时降低整张图片的透明度作为反馈。字段留空时显示对应状态的原有按钮；记录筛选的原有中心图标继续读取 `icon.Filter`。状态需要相同外观时，在各状态字段填写同一素材路径。

书架的 `searchActive` 用于搜索展开或已输入关键词，`groupActive` 用于已选分组；`groupManage` 用于书房模式的分组管理。`viewList`、`viewCollection`、`viewGrid` 表示点击后切换到的目标视图。`add`、`expand`、`collapse`、`close` 用于书房分组面板顶部。

记录的 `filterActive` 用于已选择内容类型，`edit`、`done`、`locked` 分别对应编辑入口、完成编辑和编辑锁定。`back` 用于独立记录页面的返回按钮，`history` 用于历史入口及其返回操作。

三端制作器在“顶部按钮”中按书架和记录分组，点击字段下方“状态预览”可查看该状态的整按钮效果。每个字段分别配置浅色与深色素材。主题包继续使用版本 1，旧主题按其已有字段呈现。

`cover.placeholder`、`cover.localPlaceholder`、`cover.playerPlaceholder` 分别提供在线书、本地书与播放器的默认封面。真实书籍封面沿用书籍数据。`cover.decoration` 使用字符串 `"0"` 简洁、`"1"` 边框、`"2"` 书脊；`cover.illustratedPlaceholder` 控制默认书封的书名排版。

`background.profileCard` 提供“我的”账号卡图片。`background.coverBackdrop` 控制首页与详情的书封氛围效果，播放器背景由 `background.player.*` 单独配置。

**完整字段表：135 项**

表中浅色值与深色值来自制作器字段表，用于完整新主题的默认起点。它们表示编辑默认值；省略字段时，App 会按基础套装及对应控件的规则呈现。AI 交付时填齐两组字段，便于明确表达整个主题。

“颜色”采用前述颜色格式；“图片”采用 `assets/文件名` 或 `""`。数值与开关在 `value` 中也使用字符串。

**配色（36 项）**

| 字段 key | 中文含义 | 格式或取值 | 浅色默认值 | 深色默认值 |
| --- | --- | --- | --- | --- |
| `color.background` | 页面底色 | 颜色 | `"#F7F4EF"` | `"#161719"` |
| `color.surface` | 卡片底色 | 颜色 | `"#FFFFFF"` | `"#25272A"` |
| `color.settingsBackground` | 设置页底色 | 颜色 | `"#F5F3EF"` | `"#18191B"` |
| `color.profileMenuSurface` | 我的菜单底色 | 颜色 | `"#FFFFFF"` | `"#25272A"` |
| `color.textPrimary` | 主要文字 | 颜色 | `"#292724"` | `"#F1EFEB"` |
| `color.textSecondary` | 次要文字 | 颜色 | `"#77736D"` | `"#B0ABA3"` |
| `color.textTertiary` | 辅助文字 | 颜色 | `"#A5A099"` | `"#817C76"` |
| `color.iconPrimary` | 主要图标 | 颜色 | `"#3B3732"` | `"#ECE7E1"` |
| `color.iconSecondary` | 辅助图标 | 颜色 | `"#888179"` | `"#AAA298"` |
| `color.divider` | 分隔线 | 颜色 | `"#1A63584A"` | `"#26FFFFFF"` |
| `color.appDivider` | 内容分隔线 | 颜色 | `"#1A63584A"` | `"#26FFFFFF"` |
| `color.brand` | 主题色 | 颜色 | `"#C4475B"` | `"#EF8DA0"` |
| `color.brandHover` | 主题悬停色 | 颜色 | `"#B74052"` | `"#E38295"` |
| `color.brandPressed` | 主题按下色 | 颜色 | `"#A33547"` | `"#CC7183"` |
| `color.brandDisabled` | 主题弱化色 | 颜色 | `"#66C4475B"` | `"#66EF8DA0"` |
| `color.brandSoft` | 主题浅底色 | 颜色 | `"#22C4475B"` | `"#22EF8DA0"` |
| `color.brandDark` | 主题深色 | 颜色 | `"#983747"` | `"#C46C7D"` |
| `color.onBrand` | 主题色上的文字 | 颜色 | `"#FFFFFF"` | `"#251519"` |
| `color.controlFallback` | 控件底色 | 颜色 | `"#E6FFFFFF"` | `"#DB282A2D"` |
| `color.controlTint` | 控件光感色 | 颜色 | `"#44FFFFFF"` | `"#22FFFFFF"` |
| `color.stroke` | 材质描边 | 颜色 | `"#66FFFFFF"` | `"#22FFFFFF"` |
| `color.shadow` | 阴影颜色 | 颜色 | `"#1A302820"` | `"#44000000"` |
| `color.homeTop` | 首页渐变顶部 | 颜色 | `"#F2E6DA"` | `"#272421"` |
| `color.homeMid` | 首页渐变中部 | 颜色 | `"#F7F2EB"` | `"#1D1D20"` |
| `color.homeBottom` | 首页渐变底部 | 颜色 | `"#F7F4EF"` | `"#161719"` |
| `color.statusScrim` | 状态栏蒙层 | 颜色 | `"#88F7F4EF"` | `"#88161719"` |
| `color.floatingMask` | 底部渐隐色 | 颜色 | `"#F7F4EF"` | `"#161719"` |
| `color.homeAccent` | 首页强调色 | 颜色 | `"#C4475B"` | `"#EF8DA0"` |
| `color.homeAccentSoft` | 首页强调浅色 | 颜色 | `"#22C4475B"` | `"#22EF8DA0"` |
| `color.homeControl` | 首页控件底色 | 颜色 | `"#BBFFFFFF"` | `"#BB2C2B2D"` |
| `color.homeSurface` | 首页卡片底色 | 颜色 | `"#DFFFFFFF"` | `"#DD27282B"` |
| `color.homeShadow` | 首页阴影 | 颜色 | `"#183C3025"` | `"#44000000"` |
| `color.progressTrack` | 进度轨道 | 颜色 | `"#246B6055"` | `"#33FFFFFF"` |
| `color.detailTop` | 详情顶部蒙层 | 颜色 | `"#443B3025"` | `"#AA141414"` |
| `color.detailMid` | 详情中部蒙层 | 颜色 | `"#CCF7F4EF"` | `"#CC161719"` |
| `color.detailBottom` | 详情底部 | 颜色 | `"#F7F4EF"` | `"#161719"` |

**页面背景（42 项）**

| 字段 key | 中文含义 | 格式或取值 | 浅色默认值 | 深色默认值 |
| --- | --- | --- | --- | --- |
| `background.common.mode` | 通用背景 | `"theme"` 跟随基础套装 / `"solid"` 纯色 / `"image"` 图片 | `"theme"` | `"theme"` |
| `background.common.image` | 通用图片 | 图片 | `""` | `""` |
| `background.common.color` | 通用底色 | 颜色 | `"#F7F4EF"` | `"#161719"` |
| `background.common.veil` | 通用蒙层 | `"0"`–`"90"` | `"0"` | `"0"` |
| `background.common.blur` | 通用模糊 | `"0"`–`"60"` | `"0"` | `"0"` |
| `background.common.positionX` | 通用水平位置 | `"0"`–`"100"` | `"50"` | `"50"` |
| `background.common.positionY` | 通用垂直位置 | `"0"`–`"100"` | `"50"` | `"50"` |
| `background.common.scale` | 通用缩放 | `"100"`–`"180"` | `"100"` | `"100"` |
| `background.home.mode` | 首页背景 | `"common"` 跟随通用 / `"theme"` 跟随基础套装 / `"solid"` 纯色 / `"image"` 图片 | `"common"` | `"common"` |
| `background.home.image` | 首页图片 | 图片 | `""` | `""` |
| `background.home.color` | 首页底色 | 颜色 | `"#F7F4EF"` | `"#161719"` |
| `background.home.veil` | 首页蒙层 | `"0"`–`"90"` | `"0"` | `"0"` |
| `background.home.blur` | 首页模糊 | `"0"`–`"60"` | `"0"` | `"0"` |
| `background.home.positionX` | 首页水平位置 | `"0"`–`"100"` | `"50"` | `"50"` |
| `background.home.positionY` | 首页垂直位置 | `"0"`–`"100"` | `"50"` | `"50"` |
| `background.home.scale` | 首页缩放 | `"100"`–`"180"` | `"100"` | `"100"` |
| `background.shelf.mode` | 书架背景 | `"common"` 跟随通用 / `"theme"` 跟随基础套装 / `"solid"` 纯色 / `"image"` 图片 | `"common"` | `"common"` |
| `background.shelf.image` | 书架图片 | 图片 | `""` | `""` |
| `background.shelf.color` | 书架底色 | 颜色 | `"#F7F4EF"` | `"#161719"` |
| `background.shelf.veil` | 书架蒙层 | `"0"`–`"90"` | `"0"` | `"0"` |
| `background.shelf.blur` | 书架模糊 | `"0"`–`"60"` | `"0"` | `"0"` |
| `background.shelf.positionX` | 书架水平位置 | `"0"`–`"100"` | `"50"` | `"50"` |
| `background.shelf.positionY` | 书架垂直位置 | `"0"`–`"100"` | `"50"` | `"50"` |
| `background.shelf.scale` | 书架缩放 | `"100"`–`"180"` | `"100"` | `"100"` |
| `background.record.mode` | 记录背景 | `"common"` 跟随通用 / `"theme"` 跟随基础套装 / `"solid"` 纯色 / `"image"` 图片 | `"common"` | `"common"` |
| `background.record.image` | 记录图片 | 图片 | `""` | `""` |
| `background.record.color` | 记录底色 | 颜色 | `"#F7F4EF"` | `"#161719"` |
| `background.record.veil` | 记录蒙层 | `"0"`–`"90"` | `"0"` | `"0"` |
| `background.record.blur` | 记录模糊 | `"0"`–`"60"` | `"0"` | `"0"` |
| `background.record.positionX` | 记录水平位置 | `"0"`–`"100"` | `"50"` | `"50"` |
| `background.record.positionY` | 记录垂直位置 | `"0"`–`"100"` | `"50"` | `"50"` |
| `background.record.scale` | 记录缩放 | `"100"`–`"180"` | `"100"` | `"100"` |
| `background.profile.mode` | 我的背景 | `"common"` 跟随通用 / `"theme"` 跟随基础套装 / `"solid"` 纯色 / `"image"` 图片 | `"common"` | `"common"` |
| `background.profile.image` | 我的图片 | 图片 | `""` | `""` |
| `background.profile.color` | 我的底色 | 颜色 | `"#F7F4EF"` | `"#161719"` |
| `background.profile.veil` | 我的蒙层 | `"0"`–`"90"` | `"0"` | `"0"` |
| `background.profile.blur` | 我的模糊 | `"0"`–`"60"` | `"0"` | `"0"` |
| `background.profile.positionX` | 我的水平位置 | `"0"`–`"100"` | `"50"` | `"50"` |
| `background.profile.positionY` | 我的垂直位置 | `"0"`–`"100"` | `"50"` | `"50"` |
| `background.profile.scale` | 我的缩放 | `"100"`–`"180"` | `"100"` | `"100"` |
| `background.profileCard` | 我的账号卡图片 | 图片 | `""` | `""` |
| `background.coverBackdrop` | 书封氛围背景 | `"true"` / `"false"` | `"true"` | `"true"` |

**底部 Tab（10 项）**

| 字段 key | 中文含义 | 格式或取值 | 浅色默认值 | 深色默认值 |
| --- | --- | --- | --- | --- |
| `tab.home.normal` | 首页常态图标 | 图片 | `""` | `""` |
| `tab.home.selected` | 首页选中图标 | 图片 | `""` | `""` |
| `tab.shelf.normal` | 书架常态图标 | 图片 | `""` | `""` |
| `tab.shelf.selected` | 书架选中图标 | 图片 | `""` | `""` |
| `tab.record.normal` | 记录常态图标 | 图片 | `""` | `""` |
| `tab.record.selected` | 记录选中图标 | 图片 | `""` | `""` |
| `tab.profile.normal` | 我的常态图标 | 图片 | `""` | `""` |
| `tab.profile.selected` | 我的选中图标 | 图片 | `""` | `""` |
| `tab.normalColor` | Tab 常态颜色 | 颜色 | `"#77736D"` | `"#B0ABA3"` |
| `tab.selectedColor` | Tab 选中颜色 | 颜色 | `"#C4475B"` | `"#EF8DA0"` |

**顶部按钮（23 项）**

全部为图片字段，浅深默认值均为 `""`。填写包内透明图片路径，主工具栏与分组面板的用途见前文。

| 字段 key | 中文含义 | 格式或取值 | 浅色默认值 | 深色默认值 |
| --- | --- | --- | --- | --- |
| `button.shelf.search` | 书架搜索 | 图片 | `""` | `""` |
| `button.shelf.searchActive` | 书架搜索展开或已输入 | 图片 | `""` | `""` |
| `button.shelf.filter` | 书架状态筛选 | 图片 | `""` | `""` |
| `button.shelf.group` | 书架分组 | 图片 | `""` | `""` |
| `button.shelf.groupActive` | 书架已选分组 | 图片 | `""` | `""` |
| `button.shelf.groupManage` | 书房分组管理 | 图片 | `""` | `""` |
| `button.shelf.import` | 书架本地导入 | 图片 | `""` | `""` |
| `button.shelf.updates` | 书架更新 | 图片 | `""` | `""` |
| `button.shelf.viewList` | 书架切换列表 | 图片 | `""` | `""` |
| `button.shelf.viewCollection` | 书架切换书房 | 图片 | `""` | `""` |
| `button.shelf.viewGrid` | 书架切换网格 | 图片 | `""` | `""` |
| `button.shelf.add` | 书房分组添加书籍 | 图片 | `""` | `""` |
| `button.shelf.expand` | 书房分组展开 | 图片 | `""` | `""` |
| `button.shelf.collapse` | 书房分组收起 | 图片 | `""` | `""` |
| `button.shelf.close` | 书房分组关闭 | 图片 | `""` | `""` |
| `button.record.back` | 记录页返回 | 图片 | `""` | `""` |
| `button.record.filter` | 记录内容筛选 | 图片 | `""` | `""` |
| `button.record.filterActive` | 记录内容已筛选 | 图片 | `""` | `""` |
| `button.record.excerpt` | 记录摘录 | 图片 | `""` | `""` |
| `button.record.history` | 记录历史 | 图片 | `""` | `""` |
| `button.record.edit` | 记录编辑 | 图片 | `""` | `""` |
| `button.record.done` | 记录编辑完成 | 图片 | `""` | `""` |
| `button.record.locked` | 记录编辑锁定 | 图片 | `""` | `""` |

**功能图标（5 项）**

| 字段 key | 中文含义 | 格式或取值 | 浅色默认值 | 深色默认值 |
| --- | --- | --- | --- | --- |
| `icon.Search` | 搜索图标 | 图片 | `""` | `""` |
| `icon.Filter` | 筛选图标 | 图片 | `""` | `""` |
| `icon.Grid` | 网格图标 | 图片 | `""` | `""` |
| `icon.List` | 列表图标 | 图片 | `""` | `""` |
| `icon.ChevronRight` | 右箭头图标 | 图片 | `""` | `""` |

**书封装饰（11 项）**

| 字段 key | 中文含义 | 格式或取值 | 浅色默认值 | 深色默认值 |
| --- | --- | --- | --- | --- |
| `cover.placeholder` | 默认书封 | 图片 | `""` | `""` |
| `cover.localPlaceholder` | 本地默认书封 | 图片 | `""` | `""` |
| `cover.playerPlaceholder` | 播放默认书封 | 图片 | `""` | `""` |
| `cover.title` | 书名颜色 | 颜色 | `"#FFF4E6"` | `"#FFF4E6"` |
| `cover.localTitle` | 本地书名颜色 | 颜色 | `"#493E35"` | `"#E9DFD2"` |
| `cover.author` | 作者颜色 | 颜色 | `"#64584B"` | `"#CDC0AF"` |
| `cover.authorBackground` | 作者底色 | 颜色 | `"#00000000"` | `"#00000000"` |
| `cover.label` | 标签底色 | 颜色 | `"#AA493E35"` | `"#AA493E35"` |
| `cover.edge` | 书封边缘 | 颜色 | `"#776B5D"` | `"#BFB2A0"` |
| `cover.decoration` | 书封装饰 | `"0"` 简洁 / `"1"` 边框 / `"2"` 书脊 | `"0"` | `"0"` |
| `cover.illustratedPlaceholder` | 默认书封显示书名 | `"true"` / `"false"` | `"false"` | `"false"` |

**播放器背景（8 项）**

| 字段 key | 中文含义 | 格式或取值 | 浅色默认值 | 深色默认值 |
| --- | --- | --- | --- | --- |
| `background.player.mode` | 播放器背景 | `"cover"` 跟随书封 / `"solid"` 纯色 / `"image"` 图片 | `"cover"` | `"cover"` |
| `background.player.image` | 播放器图片 | 图片 | `""` | `""` |
| `background.player.color` | 播放器底色 | 颜色 | `"#3B4650"` | `"#3B4650"` |
| `background.player.veil` | 播放器蒙层 | `"0"`–`"90"` | `"70"` | `"70"` |
| `background.player.blur` | 播放器模糊 | `"0"`–`"60"` | `"40"` | `"40"` |
| `background.player.positionX` | 播放器水平位置 | `"0"`–`"100"` | `"50"` | `"50"` |
| `background.player.positionY` | 播放器垂直位置 | `"0"`–`"100"` | `"50"` | `"50"` |
| `background.player.scale` | 播放器缩放 | `"100"`–`"180"` | `"100"` | `"100"` |

**打包方法**

将生成文件放入工作目录，例如：

```text
theme-source/
├── manifest.json
├── theme.json
└── assets/
pack_theme.py
```

将以下内容保存为同级的 `pack_theme.py`，在该目录执行 `python pack_theme.py`。脚本使用 Python 标准库，把两个 JSON 与素材直接写入 ZIP 根层，输出 `forest-glow.jttheme`；输出文件名可按主题名称调整。

```python
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

root = Path("theme-source")
output = Path("forest-glow.jttheme")

with ZipFile(output, "w", compression=ZIP_DEFLATED) as archive:
    archive.write(root / "manifest.json", "manifest.json")
    archive.write(root / "theme.json", "theme.json")
    for asset in (root / "assets").iterdir():
        if asset.is_file():
            archive.write(asset, "assets/" + asset.name)

print(output.resolve())
```

也可使用 ZIP 工具，选中 `theme-source` 内的 `manifest.json`、`theme.json`、`assets` 三项进行压缩，再将扩展名改为 `.jttheme`。以包内根层直接显示这三项为准。

**导入与继续编辑**

1. 网页或 Windows 制作器：点击“导入主题”，选择 AI 生成的 `.jttheme`，切换浅深预览并查看首页、书架、记录、我的与播放器。
2. 手机：在系统文件管理器中打开 `.jttheme`，选择“简听阅读”，App 自动读取主题并进入制作器预览。也可进入“我的 → 主题与背景”，点击右上角“导入主题”并选择文件。
3. 根据预览调整素材位置、缩放、配色和蒙层，点击“保存并应用”。自制主题使用现有会员权益。
4. 调整后的主题可再次导出，并在三个制作端继续编辑。

网页与 Windows 预览表达配色、素材和布局关系，原生材质及实际书封效果以 App 显示为准。

**维护依据与相关文档**

本规范的字段、默认值与格式来源：

- [三端共用字段表](../entry/src/main/resources/rawfile/theme_editor_schema.json)
- [中文字段与选项文案](../entry/src/main/resources/base/element/theme_editor.json)
- [主题文档模型](../entry/src/main/ets/model/ThemeDocument.ets)
- [App 字段映射](../entry/src/main/ets/theme/ThemeDocumentResolver.ets)
- [App 主题包读写](../entry/src/main/ets/service/ThemePackageService.ets)
- [网页及 Windows 主题包读写](../tools/theme-editor/src/package.js)

人工操作步骤见 [主题制作说明书](THEME_EDITOR_GUIDE.md)，接入说明见 [主题套装与制作器](THEME_BUNDLE_PLAN.md)，开发构建见 [编辑器工程说明](../tools/theme-editor/README.md)。本文件已包含 AI 制作主题所需的完整字段定义。

