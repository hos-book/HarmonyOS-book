# 简听阅读当前交互说明

## 轨道控件统一防误触

所有原生 Slider 统一使用 `utils/SliderGestureModifier.ets`（当前 10 个页面/组件文件、22 处），覆盖播放进度、倍速、跳过时长、音量增幅、阅读章节、字体排版、边距/点击区、亮度、自动翻页、色相、蒙层和朗读参数。轨道点击不改变数值；沿控件方向拖动超过取值范围的 4% 后开始调节，减少上下滚动时的轻触和轻微横移误调。纵向亮度条保留纵向反向拖动；各控件继续使用原步进、预览、提交/确认及保存回调，加减按钮继续精细调节。后续新增 Slider 应复用同一修饰器。所有数值调节的减/加按钮统一透明背景，关闭默认按压底色与悬停底色，保留原点击区域、禁用态及符号缩放反馈。

依据已读取的在线 [ArkUI 技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md)、[ArkTS 语法技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)和 [Slider 指南](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/04-components/basic/ts-basic-components-slider.md)，使用 `SLIDE_ONLY` 和 `minResponsiveDistance`；距离单位与 min/max 相同，故按范围比例计算，二者自 API 12 提供，兼容项目最低 API 20。

## 章节大标题

阅读页 → 字体 → 章节大标题：默认显示，默认 26fp、居中加粗；可选择简约（常规字重左对齐）、加粗（左对齐）、居中（加粗），字号独立调节为 18–48fp，也可关闭。使用当前正文字体和主题文字颜色。页眉章节名称仍由原来的独立开关控制。

样式选项采用整行等宽的圆角分段按钮，高 36vp、外侧留白 4vp；选中项使用系统底色和主题强调色文字，移除紧贴文字的黑色描边。标题字号滑条与正文“字号 / 行高 / 段间距”统一为 6vp 轨道、主题色进度、系统分隔色底轨和白色滑块。依据在线 ArkUI [布局权重](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/03-layout/ts-universal-attributes-size.md)及 [Slider](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/04-components/basic/ts-basic-components-slider.md)说明，沿用现有 V2 状态回调。

2026-11-07 样式修正验证：改动组件 ArkTS 检查无错误，Release SDK 26.0.0.105 增量 Debug HAP 构建通过，包内 `apiReleaseType: Release`、最低 API 20、目标 API 26。构建 MCP 仍因 ohpm 批处理递归失败，使用 Release IDE CLI 完成编译。Mate 90 Pro 模拟器启动超时，设备连接为空，安装/启动日志报 `Device not found`；本次未完成设备视觉与交互验收。

在线小说和本地文本阅读的分页、双栏及连续滚动均显示章首标题。标题按实际高度参与排版，长标题自然换行、空间不足时跨页，隐藏后不留标题空白。标题不计入正文、朗读或书签的字符偏移；修改设置和窗口重排按原正文字符恢复。偏好持久化并参与阅读备份，旧配置及旧备份采用默认值；ReaderKit 原版 EPUB 分支不展示此设置。

2026-11-07 验证：标题排版、偏好/备份、阅读进度三个定向脚本通过，覆盖三种样式、独立字号、隐藏、长标题、图文/双栏、对话高亮、跨章预览和连续列表定位。Release SDK 26.0.0.105 Debug 构建通过，之后补充的连续列表重排条件通过进度回归，未再次占用共享构建。独立 ArkTS 检查因 LSP 未初始化不可用；构建 MCP 的 ohpm 批处理递归失败后使用 Release IDE CLI。已安装启动手机模拟器，但用户确认该设备正由其他任务使用，停止设备操作；阅读页标题、字号/开关交互及手机/平板/折叠屏视觉验收尚未完成。共享产物目录随后被另一构建更新，不将后续设备的 release 模块导出错误归因于本功能。

实现依据：已读取在线 [ArkTS 语法规则](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/references/arkts-rules.md)、[ArkUI 指导](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md)与 [V2 Param 状态传递](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/02-state-management/v2/arkts-new-param.md)，沿用 `@ComponentV2`、父页状态与事件回调、既有原生段落测量绘制；本次没有引入 API 20 以上的新接口。

## 首页与搜索弹框

首页的发现筛选、筛选分组、全部分类，以及榜单排序和书源匹配，搜索页的筛选、指定书源和同书多源结果，通过原生 `bindMenu` 展示；首页书源选择与内嵌类型筛选使用同材质原生 `bindPopup`，以支持与底栏等宽的自适应内容。`ImmersiveMenu` 与设置页“默认打开”的 Select 共用 `AppMaterial.Sheet` 及旧系统磨砂回退；由系统决定圆角、阴影和展开/收起动效，书源浮层直接使用单层 Popup，其余菜单不嵌套额外 Menu 或底部 Sheet 转场。选项使用系统文字色，选中背景为 `sys.color.comp_background_tertiary`，跟随深浅模式；书源、类型、发现分组、发现选项及已选分类同时使用品牌色对勾，保留原有书源设置箭头。

搜索历史使用普通圆角矩形标签：13fp 文字、34vp 高度、12vp 圆角和随深浅模式切换的系统浅色背景。每条记录仅绘制普通文字与底色，取消逐条实时沉浸材质；保留原有关键词宽度测量、两行排列、点击搜索和清空历史行为。

首页书源弹框在手机单列和双列下均居中，与展开底部导航栏保持左右各 16vp 的边缘对齐；宽度仅由原生 Popup 外框指定，内部 Column、搜索框与列表按父级可用宽度自适应，不嵌套 Menu/MenuItem，不设置内部固定宽度或最小宽度；左右内边距对称，避免原生 Menu 栅格限宽导致右列裁切。全网榜单、每个书源和类型选项均保留独立圆角背景，使用 `sys.color.comp_background_tertiary` 跟随深浅模式；选中状态以背景内的品牌色对勾区分，书源设置箭头保留独立点击区域。

书源浮层的宽度、内容 Builder 和关闭同步依据已读取的 [Popup 接口](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/08-dialog-menu/menu/ts-universal-attributes-popup.md)；API 26 材质沿用 PlatformCompat 守卫，旧系统使用磨砂回退。

书源搜索、单/双列切换、分类搜索、分组筛选、多源勾选及排序保存沿用原逻辑。菜单内容根节点统一拦截 Touch 冒泡，避免原生菜单将内部点击视为收起操作；不拦截子控件点击和滚动手势。书源类型和发现分组在当前菜单内切换内容，选择后回到筛选结果，保留菜单与关键词；不在自定义菜单里再次绑定子菜单。只有最终选项、确认、关闭或外部操作收起弹框。长内容按实际容器限宽限高并滚动，内容宽度预留原生菜单边距，顶部操作按钮不压缩；搜索筛选底色在点击区域内左右各收 4vp、上下各收 4vp，相邻选中项不连成整块；书源和发现列表横向再留 4vp，书源列表行间与双列列间均留 12vp、发现列表行间隔 8vp，分类胶囊保留独立间距；普通菜单高度最多为窗口的 68%，避免外层菜单产生滚动；全网榜单“选择版本”使用下述动态上下边界。所有这些菜单的列表关闭滚动条，首次打开和滑动时均不显示；复杂菜单保留紧凑标题和关闭按钮；外部点击、系统返回及主动关闭同步显隐状态。搜索标题栏使用 `@LocalBuilder`，筛选与指定书源共用页面内的稳定原生菜单宿主，按筛选按钮实测位置定位，避开 HDS 标题栏构建缓存；指定书源在当前菜单内切换内容，多选时保持展开，确认、全部来源和关闭时统一收起。全部分类保留分组与胶囊布局，每个子分类均使用独立的系统圆角背景，胶囊横向、纵向间隔均为 12vp，选中使用品牌色对勾；标题和分组标题为 16fp，项文字为 14fp。分类弹框按标题安全区与实际迷你播放器上缘计算最大高度，通过原生菜单布局边界避让底部导航栏和播放器，分类列表在弹框内滚动；无播放器时按导航栏占位预留。

实现依据为本次在线读取的 [ArkTS 语法技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md?inline=false)、[ArkUI 知识技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md?inline=false)与 [Menu 接口参考](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/08-dialog-menu/menu/ts-universal-attributes-menu.md?inline=false)。原生菜单及关闭生命周期兼容 API 20；API 23 键盘平移/缩放避让、API 26 沉浸材质通过 PlatformCompat 守卫，旧系统继续使用受限高度的可滚动内容和磨砂背景。

2026-11-08 验证：菜单相关 ArkTS 静态检查无错误，Release SDK 26.0.0.105 的 Debug HAP 增量构建通过。Mate 80 已验证搜索筛选正常弹出、精准搜索勾选后保持展开、指定源在当前菜单内切换、连续勾选两个源后保持展开、确认后关闭并可再次打开；首页单/双列及内部类型/分组切换、分类展开已完成此前真机检查。随后按反馈内收选中底色并增加行间距，该最终版本已通过检查和构建，但安装时真机断开，尚未完成最终间距的设备复核。


2026-11-09 交互修复：全网榜单“选择版本”以页面全宽锚点水平居中，内容宽度预留原生 Menu 边距，搜索框、分类标签和关闭按钮保持对齐。顶部位于首页搜索栏下方；搜索栏折叠时避开吸顶分类栏，独立榜单避开标题栏。底部按实际迷你播放器位置与导航栏高度避让，上下留 8vp 间距；迷你播放器＋导航栏双层时缩短，只有导航栏或两栏并排时增高，窗口变化时重新计算。只在弹框显示期间观察实际底栏边界；先提交锚点布局再展示，避免原生读取旧位置。API 26 同步设置 MenuOptions.maxHeight、targetSpace=0 和 scrollBar=Off，防止内容超出原生默认 80% 上限而产生外层滚动；API 20–25 将内容高度限制到原生上限内。首页标题下缘使用安全区与既有滚动行程计算，不读取 HDS 标题 Builder 代理的坐标。其他菜单保留原默认高度策略。搜索框、历史标签与结果工具栏放在导航 overlay 的实体节点中；HDS 保留原生渐变模糊和标题占位，避免自定义标题代理将历史点击转发给搜索框。历史收起、结果工具栏吸顶及筛选菜单沿用原行为，输入框显式开启获焦弹出键盘。无新增接口或数据表。

依据本次在线读取的 [ArkTS 语法技能](https://api.gitcode.com/api/v5/repos/HarmonyOS_Skills/harmonyos-agent-skills/contents/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md?ref=main)、[ArkUI 知识技能](https://api.gitcode.com/api/v5/repos/HarmonyOS_Skills/harmonyos-agent-skills/contents/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md?ref=main)及其焦点、触摸响应规则和 Menu 接口参考。原始 raw 文档地址返回 403，本次通过同仓库 contents API 读取当前内容，目录通过实时 tree API 发现；未下载知识库或执行其检索脚本。设备操作参考已读取的 `deveco-studio-verify` 技能，本轮仅验证连接的手机。

2026-11-09 本轮核对：Mate 80 已安装推荐优化版；随后用户录屏确认“选择版本”仍存在上移和外层滚动，追加了锚点跨帧提交、原生最大高度与旧 API 回退修正。改动 ArkTS 检查、搜索调度/推荐缓存/弹框布局三组主机回归通过。录屏后的最终修正版仅构建交付，按用户要求不再操作手机，单层/双层底栏的最终视觉效果及搜索加载期间流畅度留待实机复测。菜单 API 依据官方[菜单属性](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-attributes-menu)与安装的 Release SDK 26.0.0.105 类型定义；在线可查与实机验收分别记录。

## 会员能力与精品推荐排序

- AI 封面超分：进入设置读取核验后的实际状态；会员确认失效时关闭并清除开启偏好，无需手动关闭重开。
- 有声书 AI 字幕：非会员开启时提示并进入会员页；服务层同样拦截，失效后停止识别、清除展示，普通播放继续。
- 桌面歌词：显示菜单标注 VIP，非会员不能显示；字幕和电子书朗读两条入口共用服务校验，会员失效关闭系统窗口。暂停或退后台仅在权益有效时保留。
- 精品推荐：顶部排序图标打开与设置下拉选项一致的原生材质排序菜单，列出全部榜单，标题与平台名分层显示，右侧为拖动手柄。长按整行拖动，边缘自动滚动，松手即时落位并自动保存，失败回退原顺序；顶部仅保留重置与关闭图标，不再显示置顶、上移、下移文字按钮。漫画、小说、有声榜可以交错排列；平台开关仍在原设置中管理，关闭平台保留排序。

定向回归覆盖到期、迟到核验取消、非会员服务拦截、跨平台排序、禁用平台、未知/重复 ID、保存失败及恢复默认。设备验收需检查：实际到期后超分开关和歌词窗口、字幕停止但播放继续、推荐排序后刷新与重启保持、骨架屏/下拉刷新/双击回顶。本次 Release SDK 调试包已构建并安装到 Mate 90 Pro 模拟器，但锁屏阻止应用启动，随后设备连接断开；界面验收及真机会员到期验证未完成。

排序菜单高度按当前窗口限制，长榜单在内部滚动。榜单松手后写入 Preferences 并 flush，关闭弹框或重启应用均从保存的稳定榜单 ID 顺序恢复；原底部面板的三档拖动高度已随菜单统一移除。

排序持久化此前在 Mate 90 Pro 模拟器验证：长按将首榜拖至第三位后首页同步更新，关闭重开及强制停止重启后保持顺序，验证后拖回原位置。该结论覆盖排序行为，当前菜单材质与布局以“首页与搜索弹框”的验证记录为准；真实会员到期验证仍待真机完成。

## 有声书音量增幅

增幅调节不禁用喇叭入口或 Slider。AVPlayer 的增幅在原生层即时生效，实机存在 Promise 不返回的情况，因此记录已提交的目标值并将等待限制为 1.5 秒；明确失败时回退，旧请求的迟到结果不能覆盖新调节值。回归包含首次调节后再次开关弹层、连续调整和关闭增幅。

2026-11-02 已通过 62 项音频回归并安装实机；实机连续调节 24→6→12 dB，原生音频日志确认两次增幅变更，关闭弹层后可重新打开并显示 12 dB。

API 21 及以上的普通有声书播放页顶部提供喇叭图标，与右侧刷新图标固定间距 8vp。喇叭使用白色 24fp 图标，点击弹出横向增幅滑条（Builder 通过闭包绑定页面上下文），范围 0–24 dB、步长 1 dB，拖动预览数值、松手应用，0 表示关闭；开启后显示当前 dB 数值。使用 AVPlayer 原生响度增益，不改变系统媒体音量。本次运行切章/换书保持档位，重启默认关闭；音源加载或正在应用增幅时禁用入口，失败保留原档位并提示。切章恢复失败时回到关闭状态。API 20 不显示此入口。电子书 TTS 朗读播放器也提供相同的喇叭入口，使用独立的朗读增幅偏好，持久保存；阅读设置不再提供音量增幅控件；2026-11-03 实机已验证弹窗调节至 +3 dB 后徽标同步，并恢复到关闭。60 项音频命令主机回归通过（含增幅应用、换章恢复、关闭、旧系统与非法值拒绝、失败和过期回调隔离）；实际听感需真机确认。

## 书架、播放器与阅读设置动效

书架右上角视图按钮按“网格 → 列表 → 立式书架”循环，使用原 `shelf_view_mode` 偏好保存 0/1/2，旧值兼容。立式模式由 `ShelfSpineLayout` 按实际容器宽度分排，书脊高低错落、底部对齐，显示原封面，不再额外叠加竖排书名，也不显示底部作者。书架三种样式及更新面板固定使用默认中性封面占位，关闭主题封面装饰；网格与列表封面保留左侧 14% 宽的基础书脊明暗渐变，与主题装饰开关独立，真实封面和占位封面使用同一效果。页面背景仍沿用当前主题，不能把简简等主题素材叠到书籍上。2026-11-08 Mate 80 实测确认网格与列表的基础书脊、网格长按菜单及三种视图切换；保留原书架视图偏好。

书脊行以独立横向 PanGesture 响应：横划时手指下的书籍上提 16vp，上方悬浮显示当前书名，仅保留文字、无背景底框；白色字形通过 `BlendMode.DIFFERENCE + BlendApplyType.FAST` 与下方画布反色混合，避免额外离屏层。提示最多两行，左右约束在实际书架宽度内，且不拦截手势。每次进入不同书籍触发一次轻震，同一本内移动不重复触发，离开行或管理状态不震动。复用 ReaderHapticService 的预置轻触觉与无预置效果时的 10ms 回退，无马达或系统拒绝不影响滑动。松手、取消、离行、纵向滚动或切换筛选后回位并隐藏书名；命中区域固定，避免边缘抖动。行内横划不切换主 Tab 或书架类型，保留点击打开、长按/右键菜单、置顶、批量选择、删除反馈与播放器封面转场。外层行使用 LazyForEach，行内最多 32 本；窗口变化重排且不改变收藏顺序。

按用户最新要求从最初历史快照恢复书籍外观：中性底色、原封面、横向明暗及上下装订线；装订线使用上暗下亮的 3vp 细凹槽，细线收进两端暗槽，随静态书封缓存；封面保持完整不透明度，避免底部占位图透出；撤回后续增加的顶部纸芯、纸页纹理和独立侧面。保留高低、厚薄差异及轻量滑动修复，取消每本书的模糊阴影、文字阴影和抽出缩放，抽出仅平移静态缓存层，触点仍在同一本书内时不重复写入状态。搁板改为随主题适配的素色薄层板，采用 2vp 顶面与 8vp 端面；表面、淡色、细边和轻投影复用现有主题资源及深浅色配置，去掉固定木色与木纹，不增加背景模糊。书籍始终贴齐承重面，横划时层板固定不动。

书架状态筛选、分组及阅听记录的类型筛选统一使用原生 `bindMenu`，由系统控制开合动效；文字与选中项底色和设置页 `Select` 保持一致，材质沿用 `AppMaterial.Sheet` 与旧系统磨砂回退。状态与类型使用 `Menu/MenuItem`；分组选项使用明确限高的 `List + LazyForEach` 和分组名称稳定键，支持上下滚动，底部固定“分组管理”入口。不能仅给 `Menu` 加 `maxHeight`，否则超出的菜单项可能被裁切且无法滚动。

从书架三种视图点击电子书，通过 `ShelfReaderRouteParams` 携带本次封面的窗口坐标：仅封面层从书籍位置展开并沿左侧翻开，露出原阅读页，约 400ms 完成。正文固定在目标尺寸，只做短淡入，不随封面缩放/旋转，不因动画逐帧重排；仍由原阅读服务恢复章节位置。根 Navigation 优先调度本次翻书转场，避免叠加右滑；返回及其他入口沿用原转场，漫画不受影响。来源/目标测量失败、离页、导航超时和窗口变化均落到正常正文并释放状态。主机回归入口为 `scripts/test-shelf-reader-transition.cjs`。依据已读取的在线 [导航转场技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-navigation-transition/SKILL.md)、[菜单控制](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/08-dialog-menu/menu/arkts-popup-and-menu-components-menu.md)和[菜单项字体接口](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/08-dialog-menu/menu/ts-basic-components-menuitem.md)，接口经本机 Release SDK 复核。

2026-11-07：Release SDK 26.0.0.105 Debug 构建通过。Mate 80 已验证三态循环、横划过程抽出与松手回位、长按菜单、点击电子书进入阅读；主机 `test-shelf-spine.cjs`、`test-page-type-swipe.cjs`、`test-shelf-batch-delete.cjs` 通过。2026-11-08 按反馈取消书籍主题占位叠加与立式作者标注，重新构建并安装 Mate 80，实机确认多行书架显示原封面、书脊底部无作者。最终 HAP 元数据为 Release、最低 API 20 / 目标 API 26。平板、折叠屏与 2in1 尚未实机验证。实现参考在线 [ArkTS 语法技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[ArkUI 知识检索技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md) 及其 [手势响应规则](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/18-arkts-rules/arkts-interaction-rules.md)。

2026-11-08 后续反馈：取消全部装订装饰并减轻抽书/翻书绘制。四组书架及转场主机回归通过，Release SDK 26.0.0.105 完整 Debug 构建通过，最终 HAP 渠道及 API 元数据复核通过，优化版已覆盖安装并启动 Mate 80。此前已查看搁板、书架筛选及分组菜单；因手机有同时发生的其他操作，最终优化版的翻书中间帧、记录菜单及流畅度未完成独立实机复测，不以构建和回归通过代替帧率验证。性能处理依据已读取的 [ArkUI 性能分析技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/arkui-performance-analysis/SKILL.md)及其 [renderGroup 适用条件](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/arkui-performance-analysis/references/animation/render-group.md)。

2026-11-08 最终按用户要求恢复最初书籍外观及装订线，封面保持完整不透明度，移除叠加书名并增加逐本轻震与悬浮书名。修复普通对象按值传入 Builder 导致提示不刷新的问题：提示内容与位置保存到页面 `@Local pulledSpineHint`，Builder 直接读取页面状态，参考已读取的 [Builder 刷新规则](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/18-arkts-rules/arkts-ui-extension.md)。`test-shelf-spine.cjs` 已通过分排、提示左右边界、标题切换、逐本轻震和同一本去重回归；Release SDK 26.0.0.105 Debug 构建通过并安装 Mate 80。获用户同意后实机确认封面无占位图透出，滑动提示从“极道天魔”切换到“叩问仙道”，松手后隐藏并回位；未量化马达力度与帧率。

2026-11-08 本次细化：装订线改为静态暗槽、浅色细线与下缘微亮，表现线头压入书脊的效果；悬浮书名去掉背景和圆角，使用白色字形与下方画布做 DIFFERENCE/FAST 混合。依据已读取的官方 [图像效果接口](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-attributes-image-effect)，并核对 Release SDK 声明，所用混合接口早于最低 API 20。书架定向回归与 Release SDK Debug 构建通过，HAP 元数据为 Release、最低 API 20 / 目标 API 26，已安装 Mate 80。实机确认当前浅色主题下书名无底框且呈深色，滑动切换文字、松手隐藏正常，装订线显示暗槽及下缘细亮边；本轮未切换深色主题，也未量化帧率。

本次读取的在线依据：[ArkUI 开发技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-develop-skill/SKILL.md)、[ArkTS 语法技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[手势响应规则](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/18-arkts-rules/arkts-interaction-rules.md)。组件、动画与 V2 状态按已安装 Release SDK 声明和编译诊断校验。

书架网格和列表的封面在按压时短暂变暗，抬手、取消、移入滚动或打开长按菜单时恢复；不缩放封面及命中区域，保证播放器截图坐标稳定。批量勾选做缩放淡入。公共 BookCard 的首次入场收敛为前八项、每项间隔 30ms 的轻移淡入，销毁时清理等待计时器。

书架多选删除使用 180ms 短淡出，避免逐卡截图和 GPU 碎片准备；单本删除保留原消散。删除保存成功后直接过滤已加载的书架与懒加载数据源，不重读全书目录和阅读进度；删除期间发生其他收藏增删才补充加载。保留默认不删文件、部分失败项可重试的语义。详情页与迷你播放器的章节半模态默认高度由 80% 提高到 90%。

书架管理的“全选 / 分组 / 删除”操作条动态贴合底部栏，上方间距为 8vp。导航避让由 MainPage 传入当前安全区和导航栏占高；迷你播放器显示时，复用 PlayerDragTransition.measure 读取包含原生 HDS 祖先位移的实际坐标，跟随双行/单行收展、窗口变化及播放器显隐，不再固定叠加 72vp 的播放器预留。编辑状态下列表末尾留白同步计入操作条高度，退出管理或隐藏书架后解除绘制监听。位置计算遵循已读取的 [ArkUI 位置设置](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/03-layout/ts-universal-attributes-location.md)；绘制监听沿用本机 Release SDK 支持的 API 12 接口。2026-11-07 随阅读设置调整完成 Release SDK 构建并安装启动实机；按用户要求未进行额外 UI 自动验证。

播放器点击展开、收回及短拖取消使用统一的临界阻尼弹簧。展开正文稍后淡入，收回正文先淡出，几何动画完成后结束导航；拖动时正文按展开比例平滑显隐，往返相同位置保持同一效果。书架/详情来源保留原封面圆角，迷你栏仍以圆形封面开始。返回迷你栏时，文字与播控在收起几何动画内淡入，不等导航结束才恢复；手势靠近迷你栏的最后 30% 路程同步回显，反向拖动及取消沿原进度恢复。双层栏及播放器转场中的控件不再叠加错峰入场，旧版圆封面展开仍保留轻移效果。

播放页普通原图在组件挂载时加载，首次布局立即确定解码尺寸，不再等转场结束后 96ms 才开启；增强处理仍延后。运动封面先保留入口截图，收到原图解码完成通知后，以相同图源和尺寸复用图片并用 80ms 淡入接管，避免持续放大 32–44vp 的迷你封面截图。预览确认进入正式播放页时保留已就绪图片和透明度，退场只使用当前全尺寸封面快照。展开终点先让正式封面提交可见帧，再移除运动封面；迟到的解码回调不能污染已结束的转场或退场。

电子书的章节、设置、字体（含主题）与漫画的目录、设置统一使用 ReaderSettingsPopup 原生锚点悬浮面板：下缘距章节条上沿 8vp；章节条隐藏时改为紧靠底部 tab 上沿。打开面板保留底部控件，底部页签可直接切换同一面板内的内容并高亮当前项，无需先关闭；切换期间不重新执行面板进出场动画。首次打开使用淡入与轻微缩放，点击正文、关闭按钮或系统返回收起；透明正文点击层位于底栏下方，避免误翻页且不拦截页签。目录搜索保留键盘避让。面板宽度按实际容器和左右安全区计算（左右至少 12vp，最大 560vp），设置高度最多 520vp；章节目录提高到最多 760vp / 窗口高度的 84%，并避让顶部工具栏和底部锚点，横屏/分屏内可滚动。API 26 沿用沉浸光感材质，旧系统使用磨砂回退。标题区上下各 4vp、分组间隔 6vp、卡片上下 8vp，字号/间距步进和主题选项保留轻按反馈；主题选中标记缩放淡入，边距和触控区域的四向选项使用独立的共享胶囊底板滑动。没有增加动画依赖、接口、数据表或新偏好。

设置按功能关联排序：电子书依次为“翻页与操作 → 页面与显示 → 阅读辅助”，字体面板依次为“主题外观 → 字体 → 段落排版”；漫画依次为“阅读方式 → 翻页与操作 → 界面显示 → 图像与翻译”。音量键、自动翻页、图片显示/分页/预加载和 AI 功能等说明收进标题旁的感叹号，点击显示锚点浮层，关闭按钮、点击外部或系统返回可收起；浮层使用显式菜单状态与关闭回调，避免在阅读 Popup 内再嵌套 Popup。合成配置将“连续朗读 / 应用推荐 / 渐进短段合成”合为一张卡片，两段说明改为按需查看，参数按合成长度、网络请求、文本处理排序。应用推荐保留立即保存行为，手动调整仍由底部“保存并应用”保存。字体选择行标为“自定义”，阅读面板不再显示字体导入按钮；导入从“我的 → 阅听设置 → 字体管理”进入。字号、字重、行高、段距、字距、自动翻页及合成数值参数使用单行布局；字距只显示数值，去掉 vp 后缀。未新增偏好、接口或数据表。

本次布局依据在线 [ArkUI 开发技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-develop-skill/SKILL.md)、[ArkTS 语法规范](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)及[原生菜单 API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-attributes-menu)，接口以本机 API 26 Release SDK 声明复核。

有声书播放器的倍速、定时、跳过、章节与电子书朗读播放器的倍速、定时、章节复用同一悬浮面板，底部入口直接切换内容并高亮；朗读的停止按钮保持原功能。锚点跟随底部入口栏的实际位置，面板下缘留白 8vp，横屏时按入口栏居中并限制在安全区内；外部关闭热区避开入口栏。倍速、跳过使用较小高度，有声书与朗读定时按 Scroll 内完整内容的实测高度伸缩，随时长/章节模式、自定义输入和取消定时按钮更新；内部间距 8vp、底部留白 10vp，窗口空间不足时滚动；目录保留搜索、排序与当前章定位，定时选择成功或选章后沿用自动收起。此次范围不包含“我的 → 电子书”设置页。2026-11-07 已随最新阅读设置构建并安装启动实机，未额外操作阅读或播放页面进行 UI 验证。

2026-11-07 反馈修正：定时弹框改为按完整内容实测高度收缩，书源列表将顶栏留白纳入首项布局；Release SDK 26.0.0.105 构建成功，包内 Release / API 20–26，已覆盖安装并启动实机。独立 ArkTS 检查服务超时，由完整构建完成编译检查；按用户要求未额外执行 UI 自动验证。

2026-11-07 安装记录：点击区域默认折叠、章节大标题去重、字距步进及此前悬浮面板和书架操作条调整已完成 Debug HAP 构建，使用 Release SDK 26.0.0.105，包内确认 Release 渠道、最低 API 20 / 目标 API 26，并通过 start_app 覆盖安装和启动已连接实机。内置构建遇到 OHPM 批处理递归错误，Release IDE 的 Hvigor 目录缺失运行文件；在本次临时目录从 HarmonyOS 官方仓库补齐匹配的 Hvigor 6.26.4 后，通过直接 CLI、--no-daemon 和进程级缓存路径构建。临时工具及日志在安装后清理，未修改项目签名或公共构建配置。参考在线 [Hvigor 构建技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-studio-hvigor/SKILL.md)及 [设备工具技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-studio-verify/SKILL.md)的安装启动部分，未执行完整设备验证流程。

2026-11-06 验证：播放器转场定向回归通过，包含非迷你封面圆角、透明度单调/双向一致、正文独立淡出；Release SDK 26.0.0.105 Debug HAP 构建通过，包内 apiReleaseType=Release、最低 API 20、目标 API 26。独立 ArkTS LSP 未初始化，语法验证由完整构建完成。构建 MCP 的 ohpm 批处理递归失败后，使用 Release IDE CLI 与 --no-daemon 完成构建。已安装启动手机模拟器，截取了首页和书架静态页面。自动 UI 验证因缺少 UI_VERIFY 配置未能执行；随后出现非本轮操作触发的页面切换，停止继续操作以免干扰其他工作。播放器/阅读设置的完整交互、动态流畅度及手机/平板/折叠屏/手表真机效果尚未验收。

2026-11-07 验证：`scripts/test-player-transition.cjs` 通过，新增 MiniBar 文字/播控双向渐变、导航结束前回显、已解码封面预览交接、迟到回调隔离及取消清理验证。独立 ArkTS 检查仍因 LSP 未初始化不可用；Release SDK 26.0.0.105 完整 Debug 构建通过，产物确认 apiReleaseType=Release、最低 API 20、目标 API 26。已覆盖安装 Mate 80，完成点击展开、短距离下拖取消和系统返回 MiniBar；间隔采样画面中封面持续显示，展开后保持清晰，返回后标题与章节显示正常。截图采样不是高帧率录屏，未据此宣称所有帧均无闪烁；弱网冷图及平板、折叠屏的相同转场尚未验收。

封面修复参考已读取的 [一镜到底技能及交接实践](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-longtake-transition/SKILL.md)与华为 [Image 官方文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-image)：只将 `onComplete.loadingStatus === 1` 视为解码完成；同步加载只用于已解码的同源同尺寸缓存与 PixelMap，普通原图仍异步加载。相关接口与本机 API 26 Release SDK 声明核对，沿用 API 20 可用能力，未安装第三方转场依赖。

在线依据：本轮已读取 [ArkTS 语法技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[ArkUI 知识检索技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md)及 [Navigation 转场技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-navigation-transition/SKILL.md)。在线弹簧曲线参考页返回 403，相关参数以官方 API 文档及本机 Release SDK 的 @ohos.curves.d.ts 校验；未运行在线技能库的检索脚本或安装其依赖。

## 底部页签新旧样式

播放页向下拖动缩回与双层播放栏向上展开共用同一套几何插值：同一停留位置下的页面矩形、圆角、封面位置/尺寸及正文透明度完全一致，方向反转时沿原轨迹返回。下拖期间展示进入播放页前的真实底页快照，不重建首页；确认松手后保留当前几何，等底页恢复布局再测量目标播放栏并继续收起；短拖、回拖和系统取消则回弹全屏。封面禁用系统图片拖拽，避免按住后由系统拖放接管。点击收起与系统返回继续复用原有导航转场。

2026-11-04：定向回归覆盖拖动中的几何变化、反向回拖、取消回弹、上下行同位置参数一致及导航衔接；ArkTS 检查无错误，Release SDK 26.0.0.105 构建通过。最终版本已在恢复调试连接后成功覆盖安装并启动于 Mate 80；安装启动不等同于逐帧视觉验收。

双层模式的上方播放栏支持按住向上拖动跟手展开：拖动期间在根层渲染只读播放页预览，顶缘随手指等距移动，宽高、圆角和封面连续插值；回拖可逆，松手不足阈值或系统取消时以临界阻尼弹簧回到播放栏。慢拖约 58vp 松手或快速上甩确认后才压栈，并将当前几何和封面快照交给现有播放页转场继续展开，不重置到播放栏。预览仅展示缓存/当前书籍，不注册正式播放页回调、不初始化播放、不写历史或改变状态栏；销毁预览不清理正式播放页的全局回调。播放栏根节点使用 API 20 的 `HitTestMode.BLOCK_HIERARCHY` 隔离 HDS 祖先收展手势，保留子播控点击；触摸交互重置空闲隐藏计时，并在栏内提供 Up/Cancel 收尾。旧版手势行为保持不变。接口依据：[ArkUI 手势响应规则](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/18-arkts-rules/arkts-interaction-rules.md)。

外观设置的“新版双行底栏”默认关闭：旧版保留原有 HdsTabs 横向悬浮页签与 MiniBar，不是固定的不悬浮底栏。开启后，MainPage 实际容器小于 600vp 时使用系统 HdsTabsMiniBar.barLayoutMode = HdsBarLayoutMode.VERTICAL。进入主页、返回主页和切换页签先显示双行：上面完整播放器，下面全部导航页签。向下浏览收成单行：左侧仅当前页签的圆按钮，右侧完整播放器，保留标题/章节、播放暂停、下一章和目录；向上浏览恢复双行。600vp 起使用 HORIZONTAL，导航与完整播放器并排常显，不跟随滚动收展。双行封面 32vp、左侧内边距 4vp，单行及宽容器封面 44vp、左侧内边距 8vp。新版播放暂停使用播放页同款 play_round_triangle_fill/pause_round_triangle_fill 系统图标，保留圆角三角形底形；旧版保持原图标。目录按钮在当前主页弹出共用 ChapterSheet，按需补全目录，选章直接切换音频/朗读而不跳播放页。

首页（含嵌套榜单列表）、书架、记录、我的通过实际纵向 onDidScroll 回调驱动新版窄容器收展，仅响应 ScrollState.Scroll，同方向累计 24vp 后切换，忽略惯性/回弹、非当前页、目录弹层及子路由期间的滚动。窄容器收展始终保持 VERTICAL，不用切换布局参数模拟动画。实机 API26 在原生 COLLAPSE 下显示双行（miniBarWidth/tabBarWidth = 328/328vp）；原生 EXPAND 下显示单行（264/56vp）。通过 applyMiniBarStyle 在这两种原生状态间切换，使用系统几何动画；封面 32↔44vp 和左内边距 4↔8vp 由 onMiniBarAnimationStart 同时启动 350ms 内容过渡，onMiniBarAnimationEnd 校准终态；不在滚动事件提前改播控尺寸、不再延迟 80ms 启动原生栏体，MiniPlayer 不叠加独立尺寸 animation。反向滚动达到阈值后立即提交新的原生目标，迟到的旧 end 回调只在目标匹配时校准，不能覆盖最新目标；onBarStyleChange 负责初始化、窗口变化和圆页签点击的状态同步。页签使用官方 BottomTabBarStyle 保持文字节点稳定，避免条件重建 Text 导致标签闪现。产品“收起”指页签收成圆按钮，不等同于 HdsBarStyle.COLLAPSE，不能将新版播放器内容缩成孤立封面。点击原生圆页签恢复双行时同步页面状态。禁止调用 applyHideAnimation 隐藏整组底栏。新版 HdsTabs 直接设置 barFloatingStyle；旧版独立分支保留 CompatibleTabsModifier 渲染链，API 20–22 由其回退为固定栏，共用页签内容。开关切换时重建原生控制器并初始化对应状态；旧版返回主页、切换页签不执行新版展开重置，只镜像系统状态，保留圆封面点击展开和展开体进入播放页的行为。保留 Scroller 注册用于双击页签回顶部。保留 barOverlap(true)、barPosition(End)、vertical(false) 三项前提及原生材质绑定。API 24 以下不开放双行开关；API 23 保留横向悬浮栏。双行模式增加内容尾部避让，切换不停止播放。

本次动画同步参考已在线读取的 [ArkTS 语法技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[ArkUI 开发技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-develop-skill/SKILL.md)及华为 [HdsTabs 回调文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdstabs)。回调声明已与本机 Release SDK 26.0.0.105 核对，沿用 API 23 悬浮栏及 API 24 双行布局守卫。 2026-11-06 已通过 ArkTS 检查、Release SDK Debug 构建和 `scripts/test-floating-tab-layout.cjs`；真机确认双行/单行终态均保留完整播控，点击圆页签恢复双行，日志验证 start→end 状态顺序。尚未与华为音乐做同机逐帧曲线对照。

新版底栏使用 MainPage 实际容器宽度，扣除两侧各 16vp 与对称安全区。小于 600vp 时保持 VERTICAL，显式将 barWidth 的三个分档设置为可用宽度，避免四页签默认 328vp 的栏宽在 Pura X 等较宽双行窗口仍像普通手机一样短；miniBarWidth 不设置，由原生收展布局为圆页签及间距自动让位，禁止将两栏固定为相同整行宽度，否则收起时页签可能与播放器封面重叠。600vp 起有播放任务时先预留两栏间 8vp，再将剩余宽度均分给导航栏和播放器，禁止在宽容器中将两栏各自设为整屏宽。无播放任务或播放器因空闲隐藏时，导航栏使用完整可用宽度。窗口跨越断点时切换原生布局，返回窄容器后沿用原收展状态，不改当前页签、滚动位置和播放状态。旧版继续沿用原有系统宽度和侧边距。依据[官方 HdsTabs 分档宽度与布局模式](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ui-design-hdstabs#hdsbarwidthrangeoptions)，barWidth 从 API 23 支持，VERTICAL 从 API 24 支持；此修改仅在现有 API 24+ 新版分支启用。`scripts/test-floating-tab-layout.cjs` 检查窗口宽度、两行/一行配置、安全区及回退；Pura X 和大折叠屏的原生渲染仍需对应实机验收。

后台恢复或播控重复挂载时，已处于双行状态不再重置样式；使用普通字段记录原生已生效/已提交状态，目标不变时不重复调用带动效的 `applyMiniBarStyle`。原生回调同步此记录，控制器重建、无播放内容或空闲隐藏后清除；调用失败允许重试。窗口临时上报零尺寸不重配底栏，真实窗口缩放仍正常适配。对应定向回归验证重复恢复无动画提交、正常收展、窗口变化和失败重试；动画接口语义见[官方控制器说明](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ui-design-hdstabs#applyminibarstyle)。

新版底栏的最终外观经 V2 Computed 隔离：前台会员/主题核验、同书切章等中间状态未改变最终外观时，不重新执行 HdsTabs 的属性配置。仅复用 Builder 或 style 对象不足以阻止原生 MiniBar 重建；不能通过 AttributeModifier 省略未变化的属性，否则系统会清除样式。2026-11-04 实机日志确认修复前同进程后台恢复发生卸载/重挂载，改用最终外观 Computed 后未再发生；真实宽度、安全区、主题、播放显隐变化继续更新。

封面复用文件缓存与在途请求：系统播控的普通网络封面也通过 CoverPrefetcher 读取，避免另走 HTTP 下载。同书同封面切章时保留当前系统封面，书源封面解析为本地路径后不再因原始 URL 缓存键查空而插入占位图；换书或封面地址变化仍显式更换，防止串图。封面生命周期定向回归覆盖这些行为及迟到请求、释放和缓存上限。

设置 → 播放提供“听书控件自动隐藏”：永久（默认，永不自动隐藏）、1、5、10、20 分钟。本机偏好重启恢复，听书与电子书朗读共用；暂停且未操作迷你控件达到所选时间后，仅隐藏主页 MiniBar（含新版、旧版和旧 API 固定布局），保留底部导航、播放进度及会话。播放或加载时始终显示，恢复播放、加载或切换书籍后恢复；触碰控件重新计时，其他页面滚动不重置计时。改为永久立即恢复控件。页面卸载清理计时器，不改变桌面歌词的显示策略。

实现依据：[华为 HdsTabs 官方 API 文档](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ui-design-hdstabs)的 HdsTabsMiniBar、HdsBarLayoutMode、applyMiniBarStyle 和 BarStyleChangeCallback。实机验收须覆盖冷启动完整双行、两方向滚动及系统动画、单行完整播控和放大封面、原位章节 Sheet；构建和安装成功不代表布局验收通过。

2026-11-03 本轮已用 Release SDK 构建并覆盖安装实机：确认新版播放按钮保留播放页同款圆角三角形底形，关闭开关恢复旧版完整导航栏与独立圆封面，切换页签仍保留旧版圆封面。设置项仅保留“新版双行底栏”标题和开关，下方说明已删除并核对实机页面。

同日已安装到 MatePad Pro 13 模拟器（2880×1920）：横屏全宽首页的导航与播放器各占 700vp、间隔 8vp，界面与布局树均确认不重叠；导航分栏后的 440vp 左侧容器保留上下双行。

## 漫画官方榜单

腾讯动漫使用 /Rank/comicRank/type/ 下的 TOP100、月票、飙升、新作、畅销、男生、女生榜，不再将全部漫画目录当作人气榜。只读取当前榜期，完整榜页未提供作者或封面时，从腾讯官方作品页的 ComicSeries 结构化元数据按需补齐；仅加载可见作品/轮播，跨榜合并同 ID 请求，最多三个并发，缓存七天，失败保留已有封面和榜单。界面平台名使用“腾讯漫画”。哔哩哔哩漫画接入国漫、日漫、韩漫、新作、完结榜，解析官网页面结构化数据并校验榜单 ID，使用当前排序而非上期排名。漫画榜请求使用桌面页面请求头；点击作品仍通过用户导入的漫画源匹配，榜单不变成内置内容源。

2026-11-03 官网实时回归：腾讯七榜各 30–99 条，哔哩哔哩五榜各 50 条；解析、去重、缓存失败回退和既有书源匹配回归通过。实机联网结果另外确认，不以电脑请求代替设备验证。

## 有声书字幕模式

连续切换字幕/封面时，先使旧任务回调失效，再向识别 Worker 发送关闭消息；同步 native 识别结束后由 Worker 自行关闭，收到 onexit 才允许下一实例启动。临时音频同样延后到退出后删除，避免模型并发占用和在途解码文件被删除。退出超时只报告失败，不绕过退出屏障创建第二个模型。Mate 80 / 鸿蒙 7 的 2026-11-05 日志确认：Worker 导入带 @Trace 的 UI 状态后报 Trace is not defined，连续点击使 Worker 从 1 增至 14，09:14:23 被 RSS_THRESHOLD_KILLER 结束。UI 状态已拆入 AudioSubtitleState，Worker 共享数据模型不再含 ArkUI 装饰器；主机测试在无 UI 全局对象的环境直接加载共享模型，并验证退出屏障。

播放页顶部工具栏及阅读页朗读设置提供“桌面歌词”菜单，提供显示/隐藏和锁定/解锁。播放器移除独立详情按钮，封面模式大封面、字幕/朗读模式小封面统一点击进入详情。API 23+ 且设备支持时由系统管理窗口与样式：听书显示 AI 字幕，电子书朗读显示当前正文。暂停保留当前行，后台播放继续更新；切章和拖动使用新的播放位置，不混入旧章节字幕；系统窗口关闭操作同步到应用入口，后续元数据更新不得擅自重新打开。缺少识别模型时提示到播放页 AI 字幕入口下载，不自动下载模型。不支持设备显示明确说明，原有悬浮段落入口保留。主机回归入口：`scripts/test-desktop-lyrics.cjs`、`scripts/test-audio-subtitles.cjs`。接口依据：[系统歌词接入指南](https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/media/avsession/avsession-desktop-lyrics.md)。

2026-11-08 同步修正：系统 PCM 与 HTTP 朗读在实际起播回调后发布当前句；合成预取不提前跳句，暂停/等待时保留末句，换章先清空旧句并拒绝迟到回调。AVSession 同时写入 API 17 的 singleLyricText，听书接管时清空单句字段并继续使用原音频 LRC。片段内仍按真实音频进度估算字符位置，合成接口无逐字时间戳，不承诺逐字对齐。

桌面歌词菜单沿用朗读音色菜单的 `MenuOptions.systemMaterial = AppMaterial.Sheet`，经 `PlatformCompat.immersiveMaterial` 守卫启用，低版本保留系统菜单；菜单材质随全局沉浸光感偏好变化。系统歌词浮窗自身的样式仍由系统管理。TTS 无整章音频时长时省略元数据 `duration` 字段，不传显式 `undefined`，否则原生 AVSession 返回 `get metaData failed` 并阻止显示；正文继续由真实朗读回调更新，不虚构整章时间轴。

桌面歌词验证（2026-11-03）：Release SDK 构建及桌面歌词、字幕、音频控制、TTS 主机回归通过；API 26 手机已安装，实机确认系统桌面 AI 字幕随播放更新、顶部歌词入口和点击小封面进入对应详情。已复现并修复 TTS 空时长元数据错误，实机确认《小王子》朗读正文在系统窗口显示并切换句子；专项回归增加原生元数据字段校验和无时长 TTS 场景，49 项 TTS 回归通过。暂停/锁定及菜单光感外观尚未完成连续实机核验。

普通有声书播放页顶部提供纯图标字幕开关，始终使用透明底色，开启时内部横条向上循环滚动、关闭时静止，偏好自动保存，默认保留原大封面。开启后使用与 TTS 一致的小封面、书名和滚动正文布局；当前片段高亮并居中跟随。手动浏览后暂停自动滚动，点击“回到当前句”恢复跟随，切回封面不改变播放位置。

首次显示模型下载说明，点击后下载约 350 MiB 中文模型并校验；音频在设备端识别。网络章节可能需要先完整缓存音频，界面分别显示下载模型、准备音频和识别状态。失败可重试，空间不足、不支持的音频与超限分别提示。未播放或音频加载中使用等待提示，不把这些状态显示为静音。

以 12 秒窗口识别，内置 CT-Transformer int8 标点恢复模型（约 72 MiB），使用当前及前两个相邻窗口的有限上下文恢复标点；拼接连续窗口的带时间戳字符后统一分段，不再因 1.5 秒间隔中断合句。内置约 419 KiB 的 30,345 条成语词库，移除成语内部误加的标点，覆盖跨窗口成语。短句保留完整；超过约 42 字的长句优先在接近 28 字的逗号或分号处分成阅读段，避免两端不足 8 字的碎片，不在任意字数处硬切。没有合适标点时保留长句。标点模型只能插入标点，不能改写识别正文；时间优先沿用 token 时间戳，无法对齐时使用窗口内近似时间。字幕缓存版本升级后重新识别，已下载语音模型复用。语音错字、专名和语义断句仍可能有误，不承诺原书准确率。先准备当前约 24 秒，再准备下一章实际起播位置（含跳过片头）约 24 秒，随后补齐两章各最多 120 秒。下一章需要开启“章节预加载”且已有完整本地音频，时长元数据未就绪不再阻止预识别；不会为字幕额外下载下一章。音频预加载不等于字幕已生成，快速切章或算力不足时仍可能等待；当前窗口已有识别结果时，补后续字幕不再标为“识别字幕中”。跳转后优先补当前位置，下一章结果不混入当前正文，换章读取已生成缓存。暂不支持 HLS/直播。未显示系统桌面歌词时，关闭字幕、退出播放器或退后台释放识别任务，已有字幕缓存可复用；系统桌面歌词可见时保留同一个识别任务，退出页面或切回封面不停止桌面字幕。回归清单包含开关持久化、暂停/拖动/换章跟随、预识别缓存恢复与失败隔离、手动滚动回到当前句、关闭后播放继续、模型下载失败重试与缓存恢复。

分段/下一章预识别更新：26 项主机定向回归通过，覆盖停顿分句、长句拆分、token 对齐降级、换章缓存恢复、seek 优先、下一章失败隔离、关闭取消和预加载关闭。Release SDK 构建及包元数据检查通过，已安装并启动真机；本轮尚未量测真机连续预识别耗时。

2026-11-02 语义断句版本已完成：28 项主机定向回归、Release SDK 构建与 API20/26 双 ABI 包检查，并安装至 VYG-AL00 实机。`AudioSubtitleMp3Device` 实机用例通过（1/1）：校验内置标点模型读取、44.1kHz 双声道 MP3 重采样、12 秒 seek，以及 Worker 语音识别加标点恢复；12 秒窗口首次处理约 7.7 秒，包含模型初始化，仅为该样本数据。另已用真实桌面模型验证中文上下文断句。设备用例为 `AudioSubtitleDevice`、`AudioSubtitleMp3Device`（显式选择时执行）；全量旧设备测试有已删除书源类的引用错误，本次临时隔离测试入口后构建，原入口已恢复。未完成在线书源整条播放链路、长时间连续字幕跟随及耗电验收，不以单样本结果代替。

2026-11-02 成语保护版本已通过 33 项字幕回归、真实标点模型加实际分段器的截图文字验证、Release SDK 构建及包内词库校验，已安装至 VYG-AL00。覆盖成语任意字符处跨窗口、错误句号、长句按逗号拆分、带时间戳缓存恢复；本轮未完成截图原音频的实机逐句对照验收。

首次无缓存时先显示播放位置附近 4 秒的临时文字，不等待标点模型初始化，后续用完整 12 秒上下文替换。临时结果不写入正式字幕缓存，可能随上下文修正。未变化的已验证模型复用校验收据，减少冷启动重复读取。首用模型下载、音频缓存和模型初始化仍需等待。

2026-11-02 首段优化版本通过 38 项字幕回归、播放器转场回归和 VYG-AL00 的 `AudioSubtitleMp3Device`（1/1）。同一 MP3 样本中，首次 4 秒临时文字返回 7,158 ms，其中语音模型初始化 6,655 ms；后续 12 秒完整结果另需 1,981 ms（含标点模型初始化 453 ms）。计时从 Worker 请求发出开始，不含下载及文件准备，仅为单次样本；模型冷启动仍是主要瓶颈，不宣称秒出或固定加速比例。设备测试等待主 Ability 创建后再启动 Worker，避免复用校验收据后测试抢在主 HAP 加载前执行。1.0.2 发布包通过 Release SDK/API20/26、发布签名、双 ABI、词库和标点模型校验，并核对混淆产物保留原生解码入口。

## 折叠屏平行视界

根 Navigation 的 NavBar 常驻 `MainPage`，详情、搜索和设置等页面继续使用同一个 NavPathStack。实际容器宽度达到 720vp 且已有非沉浸目的页时启用原生 Split：左侧保留当前首页/书架/记录/我的，右侧显示目的页。左栏初始占 42%，可在 320–440vp 内调整，右栏至少 400vp；仅停留首页时使用完整宽度，不留下空白右栏。折叠、分屏或缩窄至断点以下回到 Stack，不清栈、不重建首页，返回仍按原页面顺序。

阅读、漫画、播放器、书源网页登录及其后续页面沿用全宽；退出这些路由后恢复分栏。阅读页自身的正文双栏与导航分栏独立。宽窗口禁用进入双栏详情的跨栏封面一镜到底与迷你播放器拖拽展开；书架进入全宽播放器仍按被点击封面的实际窗口坐标展开，返回重新定位同一封面。窄窗口保留原交互。颜色、材质、标题栏和卡片沿用现有设计。使用最低 API 20 已支持的 Navigation 接口，不依赖 API 26 的 fullScreenOverlay。

宽窗口的根页与首层非沉浸目的页之间直接切换布局，Navigation 级即时完成转场覆盖页面级百分比平移；同时关闭单双栏模式切换动画，避免书源/设置返回时出现白块、拉伸和叠影。双栏内部跳转、窄窗口和全宽播放器保留原有页面转场。不把 `didShow` 当作动画结束回调，不通过固定延时猜测结束时刻。

参考已读取的华为官方 [Navigation 分栏开发](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-navigation-split-mode.md)、[Navigation 转场动画](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-navigation-animation.md)及[平行视界兼容方案](https://developer.huawei.com/consumer/cn/doc/doccenter-multi-device/bpta-easygo-parallel.md)。项目自行控制原生 Navigation.Split，未配置 easyGo；仅借鉴系统平行视界根页进出不叠加自定义动画的处理。`enableModeChangeAnimation` 自 API 15 可用，已核对本机 Release SDK。回归脚本 `scripts/test-parallel-navigation.cjs` 覆盖空栈首页、断点往返保栈、沉浸页与返回、根页进出即时结束、分栏内部与手机转场保留、播放器重复入口清理。设备验收需覆盖书源/设置进入与返回、快速连续返回、展开→详情→折叠→展开→返回，以及阅读位置与弹层返回；主机回归不能替代平板转场视觉验证。

2026-11-01：改动文件 ArkTS 检查无错误，导航策略回归通过，Release SDK 26.0.0.105 Debug HAP 构建成功（min API 20 / target API 26）。按用户要求停止普通手机模拟器测试，不将手机横屏视为折叠屏验收；折叠屏展开/折叠与实际双栏交互尚未完成设备验证。

## 阅读双栏、朗读浏览与章节信息

文本分页阅读在实际视口横向、对称避让后的正文容器至少 688vp 宽时自动使用左右双栏，栏间距 48vp，保留每栏至少 320vp。双栏使用对称安全区与左右用户边距的较大值，正文、页眉与页脚共同居中；额外限宽留白不写回用户设置。栏间中央显示 0.5vp、正文色 16% 不透明度的竖线，在正文区域内上下各留 8vp 空隙，与页眉、页脚横线断开，不拦截点击或翻页手势。竖屏、窄分屏和连续滚动保持单栏。两栏沿用同一章节的原生排版片段，按跨页字符偏移恢复位置，奇数末栏留空，不重复正文。切换窗口、字号后仍保留原字符位置。

双栏的“正文边距”左右联动，调节任一侧会同步另一侧，面板显示实际采用的共同数值并提示同步调整。基础限宽留白仅按窗口和对称安全区计算，再叠加用户边距，避免大屏自动居中抵消 0–64vp 的设置变化。单栏仍独立调节左右边距；调整继续走既有字符位置保留和设置保存流程。

2026-11-03 边距修复通过阅读进度与偏好回归，覆盖不同窗口宽度、单侧安全区、左右调大／调小及单栏独立设置；Release SDK 完整构建通过并覆盖安装平板。平板双栏将边距调至 9vp 时，布局树确认左右各 69vp（60vp 基础留白 + 9vp 用户边距），不再被固定限宽抵消，仍停留在第 5 章。

页眉下方、页脚上方增加与中线一致的 0.5vp、正文色 16% 不透明度分隔线，沿正文容器宽度绘制。阅读设置提供“显示页眉页脚分隔线”独立开关，默认开启，可统一隐藏两条横线；对应页眉／页脚关闭时横线也隐藏。选择即时生效、持久化并参与阅读备份，恢复默认重新开启；双栏中间竖线不受此开关影响。横线叠加在已有预留区域内，不额外压缩正文或改变分页高度，也不拦截翻页手势。

后续按平板试读反馈将栏间距进一步调至 48vp，中线两端各缩进 8vp。ArkTS 检查无错误、Release SDK 完整构建通过，已覆盖安装平板，并在横屏阅读界面确认中线与上下横线断开。

2026-11-03：对称外边距与中线改动通过 Release SDK 26.0.0.105 Debug HAP 构建，包内最低 API 20／目标 API 26／Release 渠道已核对；阅读进度、分页排版、阅读偏好三组主机回归通过。根据平板试读反馈将栏间距从 24vp 加宽至 32vp，并增加页眉／页脚线；完整构建及阅读位置回归通过，独立 ArkTS 检查此次等待 300 秒超时。已覆盖安装 MatePad Pro 13 模拟器，在《青莲之巅》第 4 章确认三条分隔线、32vp 栏间留白和阅读位置恢复，左右外边距对称。

听书播放页目录沿用小说阅读目录的原生常显滚动条，不再单独固定为 8vp 或缩短上下轨道，恢复系统按压态与触摸热区。保留手动触摸／拖动时取消延迟目录定位的逻辑，防止滚动后被拉回当前集。已读取的 [OpenHarmony 滚动组件公共属性](https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/reference/apis-arkui/arkui-ts/ts-container-scrollable-common.md)说明显式设置宽度会固定正常态与按压态宽度；[原生 ScrollBar 实现](https://raw.githubusercontent.com/openharmony/arkui_ace_engine/master/frameworks/core/components_ng/pattern/scroll/inner/scroll_bar.cpp)进一步确认显式宽度分支令 `touchRegion_ = activeRect_`，默认分支则扩展触摸区域。改动已通过完整构建并安装平板，实际目录拖动手感待用户试用确认。

朗读设置的“朗读跟随翻页”默认开启，关闭后正在播放或加载的朗读不会因手动翻页/滚动而重新生成；正文下方显示现有沉浸胶囊样式的“返回 / 从此听”。返回定位到当前朗读位置而不重启语音，从此听从当前阅读位置重新启动。暂停后翻页仍更新续听位置。该偏好参与本地持久化和阅读设置备份，旧配置保持原默认行为。朗读高亮背景使用标记颜色的 20% 不透明度，正文维持原色；空颜色跟随当前主题强调色，选字背景仍保留正文颜色的 20% 不透明度。

搜索列表、网格、同名书籍来源列表和换源候选显示源提供的最新章节信息；列表行将最新章节置于右侧并右对齐，最多两行省略，左侧保留书名/来源信息；网格保持卡片内展示。无元数据时隐藏，不将章节标题中的数字冒充总章数，也不逐条抓取目录。替换净化规则的预览、取消、保存按钮使用 `AppColor.Brand/OnBrand` 配对颜色，保证系统深色模式下可辨认。

实现参考：[窗口尺寸适配](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/06-solutions/multi-device/hmos-multidevice-screen-window-size/SKILL.md)、[自适应布局](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/06-solutions/multi-device/hmos-multidevice-screen-window-size/references/adaptive_layout.md)与 [ArkTS 编译检查](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-syntax-checker/SKILL.md)。继续沿用项目 V2 和既有安全区/重排流程，不引入新窗口监听器。

2026-11-01：改动文件 ArkTS 检查及 Release SDK 26.0.0.105 Debug HAP 构建通过；分页/原生绘制、朗读同步、阅读偏好、换源四组回归通过，覆盖双栏字符恢复、20% 高亮、独立浏览不重启朗读、返回和暂停跟随。Mate 90 Pro 模拟器已更新安装，实际查看横屏双栏、转回竖屏单栏和系统深色替换规则弹层；折叠屏真机、真实在线 TTS 试听及全部操作组合尚未验收。

## 综合书源首页频道

首页除“精品推荐”外的分类书单，在分类栏右侧提供列表／网格切换；书源“发现”进入分类后的书单，以及首页分类／更多书单，在标题栏右侧提供同样的切换按钮。默认采用原生 WaterFlow 瀑布流，每本书的封面按原始宽高比完整显示，卡片按最短列接排，不再按整行最高封面对齐；复用 AdaptiveLayout，手机默认三列、窄窗口两列、宽屏随实际容器宽度增加列数。列表复用首页封面、书名、作者和简介行；切换回到书单顶部，保留已加载书籍和分页状态，不重新请求第一页。首页切换分类时沿用当前布局，精品推荐保持原展示；两种布局均懒加载并保留详情封面转场，分页仅追加新书节点；瀑布流底部分页提示跨整行显示，首页保留迷你播放器与底栏避让。验收需覆盖来回切换、加载更多、详情返回、分类切换，以及首页下拉刷新和双击回顶。

2026-11-01 布局切换验证：改动 ArkTS 文件检查无错误，Release SDK 26.0.0.105 Debug HAP 构建通过，包内最低 API 20、目标 API 26、渠道 Release。已安装到 HUAWEI Mate 80，实际查看首页分类网格→列表→网格、返回精品推荐，以及通过“更多”进入发现共用书单页的网格→列表切换。书源管理→发现完整入口、分页续载、刷新和双击回顶尚未完成本轮实机回归。

2026-11-06 瀑布流调整验证：首页分类及分类／更多书单改用 WaterFlow；Release SDK 26.0.0.105 的 Debug HAP 构建通过，包内最低 API 20、目标 API 26、渠道 Release，已安装并启动到连接真机。首页频道定向回归通过；BlockMorePage ArkTS 检查无错误，HomePage LSP 检查超时，由完整构建完成编译验证。因真机同期有其他操作，本轮未完成混合比例封面的视觉检查及刷新、分页、列表切换、详情返回和双击回顶回归。

有多个发现分组的导入源，在搜索栏下方、轮播图上方显示“综合 / 源定义频道”横向标签，分类栏留在轮播图下方，避免两行标签堆叠。复用 `ImmersiveTabComponent` 的轻透材质、主题文字和细下划线选中态，以及首页边距、两侧渐隐。频道随顶部内容滚走，分类栏吸顶；切换分类收起轮播时，频道保持在搜索栏下方。普通无分组书源保持原有布局。

顶部最左侧的书源分类/频道下拉（例如“男频首页 / 女频首页”）在筛选选项返回后即可打开和切换，不等待推荐书单全部加载。仅保存筛选结果时阻止重复操作；保存失败恢复原选择，成功后沿用书源变更事件刷新首页和请求代次校验。轮播下方“分类”总览仍使用原有独立入口。

2026-11-05：`scripts/test-home-channels.cjs` 使用真实服务及页面方法挂起推荐请求，确认旧逻辑拒绝切换、修改后允许切换，并覆盖重复保存、失败回滚与旧请求迟到；ArkTS 检查无错误，Release SDK 26.0.0.105 Debug HAP 构建通过。MatePad Pro 13 模拟器冷启动后下拉菜单可打开；实际慢网下的切换耗时及真机尚未验收。“分类”总览的长时间点击延迟在本轮模拟器未复现。处理依据为已读取的 [ArkUI 分阶段展示指南](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/arkui-performance-analysis/references/startup/staged-display.md)：已就绪的操作入口不依赖非关键推荐区完成。

综合预览按分组轮询，最多四组、两路并发，避免小说分类占满预览；频道内展示完整分类并只加载该频道预览。综合页分类名带分组前缀以区分同名“都市”“全部”等，频道内省略前缀。每个源独立记忆频道，缓存和在途请求按源与频道隔离，快速切换的迟到响应不得覆盖当前页。明确标为影视、视频、电影、电视剧或 video 的分组全部过滤，频道、分类和推荐均不展示，旧影视频道偏好回退综合。首页频道不修改源定义的搜索变量；搜索仍遵循源设置。

实现参考：[ArkUI Builder 规则](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/18-arkts-rules/arkts-ui-extension.md)与 [LazyForEach 指南](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/09-rendering/arkts-rendering-control-lazyforeach.md)，继续使用项目 ArkUI V2 与现有材质兼容守卫。

2026-11-01：改动文件 ArkTS 检查无错误，频道服务/页面竞态、首页按需加载和分类横滑三组主机回归通过；Release SDK 26.0.0.105 Debug HAP 构建通过，包内最低 API 20、目标 API 26、渠道 Release。Mate 90 Pro 模拟器已导入 WMH1234 综合源并更新安装；截图确认频道位于搜索栏下、轮播上方且无影视，漫画轮播与书单实际加载完成，切换分类收起轮播后频道位置正常，返回推荐恢复轮播。吸顶/下拉刷新/双击回顶、深色和真机视觉尚未完成验收。

## 听书后台恢复与自动翻页

后台定时停止、耳机/系统播控暂停及音频焦点打断后，播放器采集最终时间并顺序保存续播位置，再释放后台音频任务。再次进入前台先校准原生位置，不主动播放；未完成的 seek 和正在换章时仍保留目标位置。

阅读设置根据当前模式显示“自动翻页”或“自动滚动”。分页模式默认每 10 秒，可调 3–120 秒；小说滚动模式按速度连续移动，默认每分钟 20 行，可调 6–100 行；漫画连续模式提供独立速度 6–120，默认 30。点击“开始”收起设置和工具栏，正文保留“暂停 / 继续”和“×”控制按钮，复用 `ImmersiveActionButton`、`ImmersiveCircleButton` 的原生材质及离屏圆角裁剪，避免外溢阴影。分页复用原动画，漫画适宽长图读到底再换图；连续模式沿原列表补章，加载、图片解码、重排期间等待，掉帧不补滚整屏。两种模式独立记忆参数，末尾或加载失败停止。

运行期间保持亮屏；只有点击“暂停”才进入暂停状态，恢复原亮屏设置并保留“继续 ×”，无需重新打开设置。触摸正文、显示工具栏或手动按键翻页不暂停自动阅读。点击“继续”从当前位置恢复，分页重新等待完整间隔；点击“×”关闭并移除控制按钮。控制按钮独立于正文触摸区域，点击不会触发正文翻页。切后台、离开阅读页或开启朗读仍停止并清除暂停状态；加载、选字和弹层操作期间临时等待。自动阅读与朗读跟读互斥，重进页面需手动启动。验证重点：触摸及显示工具栏不暂停、按钮暂停期间不翻页/滚动、继续后完整计时、关闭暂停会话、速度变化、长图不漏读、跨章、加载迟到不跳屏、退出后不再滚动，以及字体/窗口变化与重新进入后的阅读位置。

小说、漫画的自动阅读控制按钮按实际视口及安全区直接定位，默认右下方，小说同时避开底部阅读状态。开启智感握姿后复用当前阅读页的握持状态：左手移到左下方、右手移到右下方，换边沿用页面弹簧动画，关闭智感握姿或设备不支持时保持默认位置。显示底部工具栏时，控制按钮上移至工具栏及章节进度条上方，避免遮挡。按钮及宿主使用 `HitTestMode.Default`，允许子按钮响应并阻挡底层正文，禁止使用会屏蔽子按钮的 `Block`；不使用全屏 `Transparent` 宿主。暂停、继续和关闭不得透传点击并触发底部 Tab 栏，按钮外的正文仍可正常点击和滚动。

小说与漫画自动滚动共用 `Scroller.scrollEdge(Edge.Bottom, { velocity })` 原生匀速动画（API 12+），不由 ArkTS 逐帧调用 `scrollBy`。业务每 200 ms 检查加载/边界及进度，同一速度持续移动时不重启动画；小说按行高换算每分钟行数，漫画速度单位为 vp/s。暂停、后台、离页通过当前偏移的无动画 `scrollTo` 停止，加载、选字、缩放和位置恢复时等待；触摸时让手势接管，松手且惯性结束后恢复。漫画自动滚动期间解除逐帧 `onDidScroll` 监听，进度随低频检查上报。实际刷新率由设备和系统决定，构建及行为回归不代表帧率实测。

原生自动滚动开始时，通过 `displaySync` 仅声明 60–120 Hz、期望 120 Hz，不注册逐帧回调；不支持高刷时退回 60 Hz 声明，声明不可用时仍可原生滚动。暂停、加载等待、触摸、后台和退出时同步释放帧率声明。实机 Trace 曾在未声明时记录到 60→30 Hz 的短暂降频，优化效果按相同设备的滚动区间采集验证，不把期望值当作实测帧率。

漫画控件靠右且工具栏收起时，额外向上避让 40 vp，保留右下角章节/页码信息及间距；靠左时保持底部安全区位置。

设置页在横屏、竖屏和分栏容器中均采用单列铺满当前可用宽度，分组依次为外观、布局与交互、启动、播放、缓存与预加载、搜索、书架、全网榜单。HiCar 和简简设置已移至“我的”页并列入口。外观集中主题模式、材质、主题色和 AI 封面超分；布局与交互集中新版双行底栏、横滑切换和智感握姿；简简独立页面集中管理陪伴、夜间关怀、AI 配置与聊天入口。主题模式与材质之间以及同一卡片相邻设置项使用统一分隔线。普通开关行最小高度 52vp，下拉行 56vp，分组间距随容器为 12/20vp；横屏不将高低不等的设置卡片配成两列。设置项的解释文字统一移入标题行的圆圈感叹号，复用阅读设置的 `SettingsHintButton`，点击显示锚点说明弹层，可通过关闭按钮、点击外部或系统返回收起；音频播放方式的说明随当前选项更新。缓存占用、加载和错误状态仍直接显示。搜索推荐与并发设置合为同一卡片，全网榜单的说明入口独立于展开按钮，收起时也可查看。

此设置调整参考在线 `lang-syntax`（`https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md`）和 `hmos-arkui-knowledge-retriever`（`https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md`），并读取其 `@Local`、Button 与 Slider 参考。沿用 ArkUI V2、现有 PreferenceService 与 API 24 底栏守卫；在线指南读取不代表检索脚本或设备流程已执行。

设置中的“音频播放方式”标题与选项选择器横向同排，标题左置、选择器右置，模式说明放在下一行。

漫画“切换书源”位于右上角功能菜单，点击后关闭菜单并打开原换源面板，不再单独占用顶部按钮。

100 行上限及停止胶囊调整已通过自动阅读回归和 Release SDK 26.0.0.105 构建，修正定位后的版本已覆盖安装并启动到 Mate 80。实机正在被使用且已切至其他应用，尚未完成 100 行设置重进保存与新版胶囊下缘的实机视觉确认。

朗读/音色面板新增“合成配置”，可调整段落数、字数上限、网络超时、失败重试和预合成并发；系统音色使用单段最多 300 字的独立上限并提前准备下一段。特殊字符过滤默认开启；替换规则采用每行“原词=>读法”的字面匹配，右侧留空表示不读，不修改阅读正文。保存后从当前段内位置应用，避免三倍速在每个短句重新等待合成；具体音频中的停顿仍取决于音色提供方。暂停、跳读、切音色时取消旧预取与重试。

合成配置默认展开，点击标题可收起；五个数值控件使用独立 ArkUI V2 组件，拖动时立即同步右侧数值，点击保存才持久化。暂停朗读后手动翻页、切章、跳书签或停止滚动，只更新下一次朗读的原文字符位置；再次点击小窗播放或系统媒体播放时从新位置开始。未移动正文则继续暂停位置，取消翻页和字体/窗口重排不修改续读目标。

自定义 TTS 导入支持 GET、POST、字符串或嵌套对象 JSON 正文，请求头可用 JSON 对象、JSON 字符串或逐行 `Name: Value`。Kokoro `/v1/audio/speech` 可直接使用 POST，`input` 填 `{{speakText}}`，`Content-Type` 为 `application/json`；引号、换行和反斜杠按 JSON 转义。兼容轻页的 `@http…?参数` 仍表示 POST 表单，查询串移入正文；GET 地址不要加 `@`。`contentType: audio/wav` 是音频格式，不能代替请求头。

小说和漫画的“智控键翻页”设置入口暂时隐藏；读取旧配置或备份后，页面仍保持智控键翻页关闭，不启用相关事件订阅。原偏好字段和服务保留，音量键翻页继续使用独立设置。发布日志不再列出智控键翻页。

2026-10-30 智控键隔离排查（未修复）：`supportKeys` 返回 false 不再阻止 API 26 的 `keyPressed` 订阅调用；订阅失败清理另一方向并重置启用状态，后续可重试。Mate 80 日志显示 `probe up=false down=false`，订阅调用未抛异常，注入 3234/3233 可在连续滚动正文中前后移动。但用户实体上滑/下滑复核失败，系统 `NotificationFingerprintVm` 仍收到滑动并拉出通知栏，未观察到对应应用翻页回调。因此注入验证和订阅返回均不能证明实体隔离成功。`KeyMonitorManager` 的 `Invalid subscription key` 在公开源码中只是当前事件与某条订阅键不匹配，也不能作为设备不支持的证据。已完成的定向回归、ArkTS 检查与 Release SDK Debug 构建仅证明应用接线及构建有效，不代表硬件验收。官方依据：[优先响应系统功能键](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/keypressed-guidelines.md)，API 26 智控滑动键为非通用键值，需确认实际事件上报；硬件支持与应用事件上报应分别核实。

实现依据：[ArkUI Builder 参数刷新规则](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/18-arkts-rules/arkts-ui-extension.md)、[系统功能键官方指南](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/keypressed-guidelines)及本机 Release SDK 的 `inputConsumer` / `KeyCode` / `inputDevice` 声明。在线技能索引与所选指南已读取，目录树 API 返回 HTTP 429，未完成相关分支的目录遍历。

2026-10-29 本项验证：47 项 TTS 回归及 JSON 配置、阅读跟读同步、阅读偏好/备份、漫画按键和智控键订阅六组定向脚本通过；附件 Kokoro 等效配置及生成的直连 JSON 均通过真实解析器和请求模板校验。Release SDK 26.0.0.105 编译、打包与签名成功，Debug HAP 元数据为 Release、minimum API 20、target API 26。构建工具 OHPM 批处理递归失败后使用 Release IDE CLI；签名文件占用解除后重建通过。按用户要求停止启动流程，未完成滑条实时显示、真实 Kokoro 出声或智控键硬件验收，不将主机回归视作实机验证。

普通设置进入时只加载本地值。会员查询在现有生命周期中静默执行，页面和搜索并发区域不再随全局查询显示加载行；只有提交会员设置才等待鉴权。可编辑搜索并发草稿，应用前仍需有效会员，查询失败不能获得权限；已确认失效时展示默认值。

实现参考：轻页 [ReaderAutoScrollClock](https://github.com/hos-book/legado-harmony/blob/345fef5cf80ed5b26238da83aec3fe21e8ea1907/entry/src/main/ets/core/reader/ReaderAutoScrollClock.ets) 的按帧位移及掉帧限幅思路；在线 [IAP 订阅技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/sdk/hmos-one-sdk-skill/hmos-sdk-basic-skill/IAP%20Kit%28%E5%BA%94%E7%94%A8%E5%86%85%E6%94%AF%E4%BB%98%E6%9C%8D%E5%8A%A1%29/hmos-iap-kit-integrate-subscription/SUB_SKILL.md) 的请求频率与验签约束、[Account Kit 静默登录技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/sdk/hmos-one-sdk-skill/hmos-sdk-basic-skill/Account%20Kit%28%E5%8D%8E%E4%B8%BA%E8%B4%A6%E5%8F%B7%E6%9C%8D%E5%8A%A1%29/hmos-account-kit-silent-login/SUB_SKILL.md) 的无交互身份检查。SDK 26 本地声明确认 `FrameCallback/postFrameCallback` 自 API 12 可用；本次没有替换账号登录或支付流程。

阅读与漫画设置共用的分组卡片采用独立的浅色／深色背景资源。根据视觉反馈，底色不透明度进一步从约 25% 下调至 20%，让选项背景略微更透；保留现有淡边框与主文字色，弹层继续使用现有沉浸材质。需在设备上检查两种外观下的分组边界、说明文字与开关可读性。

正文边距使用“上／下／左／右”横向选项 Tab，每次只显示当前方向的滑条，移除滑条下方起点与终点数字。左、右、下仍为 0–64vp，上边距仍可调到阅读视口的一半；保留右侧当前值和原有边距偏好。

设置组件与量程标识此前已通过 ArkTS 检查、Release SDK 26.0.0.105 Debug HAP 构建，包内最低 API 20／目标 API 26／Release 渠道已核对。本次背景减淡仅调整颜色资源，未重新构建或完成实机视觉验证。

本轮验证：TTS 46 项、音频命令 55 项及 HTTP 超时/重试、自动滚动/翻页、设置加载/提交、搜索并发、阅读进度与跟读同步回归通过。独立 ArkTS 检查受 LSP 未初始化限制，改用 Release SDK 26.0.0.105 完整构建并核对产物渠道。Mate 80 重连后曾出现 HDC 会话失效，重启主机调试服务后已成功覆盖安装最新版并启动；尚未完成新版完整 UI、后台停止复现和三倍速试听验收。在线目录和所列技能已读取，部分引用子文档返回 404/429，不据此声称完成支付或账号流程验证。

## 会员权益对比

会员标识统一使用“声页”透明素材：月度紫色翻页、年度橙色展开书、永久橙黄色无限书页环。套餐图标为 56vp、会员页昵称旁为 36vp，使用 512px 正方形图源。个人页昵称小标为 24vp、账号页为 28vp，使用收紧透明边距的高 128px 图源并按各自原始比例显示；个人页三款图案可见高度均约 22vp，与 20sp 昵称文字匹配。所有图标保留透明背景。

套餐卡片与权益对比保留 24vp 间距。三个套餐卡片按最高内容等高拉伸、顶部对齐，优惠标记位于右上角，徽章、套餐名、现价、划线原价与周期说明纵向居中排列；现价按月度黑色、年度金色、永久深黑金色区分；优惠标记贴右上角叠放，不占内容行；图标高 56vp、内容间距 4vp、上下内边距 10vp，仅保留 14vp 原价行用于对齐；统一 2vp 边框避免选中后内容位移，金额沿用实际套餐数据。内容区按固定间距纵向滚动，购买说明勾选框与订购按钮位于滚动区外，固定在会员弹层底部并避让系统安全区；购买区背景透明，透出页面原有渐变。订购按钮固定显示“11月1日 00:00 开放订购”，禁用且无购买点击回调；切换套餐、勾选说明或会员状态变化均不解锁，不按设备时间自动开放。

会员页在套餐卡片下方展示“权益 / 非会员 / 会员”三列对比，包含 AI 上色、AI 翻译、AI 超分、图标、主题、云备份、搜索并发、功能尝鲜和专属客服。表格随页面纵向滚动，保持金色视觉；默认图标、基础主题和手动云备份标为免费能力。会员搜索并发按产品要求展示“无限制”；本次仅更新展示，现有搜索设置的 1–12 并发范围尚未调整，不能将此文案视为运行逻辑已开放。2026-10-28 套餐卡片对齐与禁用订购按钮通过 ArkTS 检查和 Release SDK Debug HAP 构建；设备未连接，卡片视觉、窄窗口与大字体下的换行及整表滚动尚未完成实机验收。

已上线权益的会员限制：AI 上色覆盖工具栏、设置、预热、队列、缓存显示及 HAR 宿主；AI 翻译的图片与离线推理入口独立校验，失效后取消任务；AI 超分、替换图标、自动备份和自定义搜索并发继续使用现有验签权限。默认主题免费，其余主题套装可免费预览，应用时要求会员；冷启动在首帧前读取已保存主题与本地有效会员展示记录，先恢复所选套装，再后台核验；回前台复核不闪回默认套装。本地记录只恢复已选外观，不授权新会员操作；订阅到期、账号变更或核验失败时撤销展示，缺少有效记录时使用默认套装。原有自定义强调色、材质和阅读纸张保持免费。“功能尝鲜”和“专属客服”按产品要求仅保留权益说明，尚无功能入口。

## PDF 本地导入

文件选择器、ZIP 内文件及系统“使用其他应用打开”均支持 PDF（`.pdf`、`application/pdf`、`com.adobe.pdf`）。保留原版页面，扫描版与文字版都按本地图像书阅读，可缩放、翻页并恢复进度；不做文字重排或朗读。导入页提供自动识别、电子书、漫画三种阅读类型，自动模式下 PDF 按漫画导入，手动电子书模式仍显示原版图片。未上传封面时使用默认书名封面；旧 PDF 自动指定的第一页封面在读取时恢复为默认封面，用户自选封面不变。目录每 50 页一节。转换在后台任务池逐页执行并显示进度，单文件不超过 128 MiB/2000 页，页面图片累计不超过 512 MiB。需要密码、损坏文件、设备不支持及空间不足会明确提示；转换失败清理整本临时产物，不修改用户原文件。回归覆盖页序、横竖页尺寸、目录与图片持久化、删书及失败清理；原生 PDF 渲染清晰度、旋转页和实际设备进度恢复仍需实机验证。

## 提示文案语气

日常提示采用“简简陪你看、陪你听”的亲切语气，涵盖小说、有声书和漫画。跨内容类型的搜索、首页等公共提示使用“内容”等通用表述，具体阅读或播放场景再使用对应名称。加载、找书、整理章节等等待状态可以使用“简简正在…”，成功反馈先说清完成了什么，再适度使用“啦”；空状态明确当前没有什么，并给出真实可用的下一步。分页结束统一使用“简简努力找过啦，这就是全部了～”。同一屏避免反复自称简简，不使用堆叠感叹号、表情符号或含糊的“出错啦”替代具体原因。

按钮、标签、计数及手表端保持简短，保留“保存 / 删除 / 取消 / 重试”等动作名称。失败提示保留具体对象、原因和补救方式；支付、会员、权限、隐私、证书、删除和数据覆盖确认保持准确，不以卖萌弱化风险，不暗示尚未成功的操作已经完成。占位符、数量、单位、格式限制与实际行为保持一致。面向用户的新增提示统一放在字符串资源中，页面引用资源；服务诊断、外部书源返回消息及日志保留原意。

| 场景 | 文案示例 |
| --- | --- |
| 搜索等待 | 简简正在帮你找精彩内容… |
| 搜索为空 | 简简还没找到相关内容 / 换个书名或作者，再找找吧～ |
| 导入完成 | 书已放好啦，去书架看看吧～ |
| 保存书签 | 书签夹好啦，下次接着读～ |
| 翻到末页 | 已经读到最后一页啦～ |
| 加载失败 | 这次没加载好，点一下重试 |

封面复用：详情与书架更新只在封面为空时补取，不自动替换已有封面；主动编辑封面仍以用户选择为准。详情主图与背景共用书源封面解密入口。解密文件在页面往返和应用重启后复用，缓存缺失或加载失败再补取，登录或源定义变化仍隔离缓存。书架阅读进度变化只更新文本，不作为整张书卡的列表 key；章节数等元数据变化仍更新书卡。已有完整目录的详情沿用缓存，首次补齐详情/目录和书架每日更新不因封面缓存而跳过。回归覆盖普通与加密封面的补缺策略、旧详情缓存、重启复用、失效重取和书架无变化不写库；性能收益不以功能回归代替实机测量。

后续实测确认 `sourceSize` 修复生效：690×1945 原图按 690×1944 解码。书源执行对象按完整定义缓存规范化字符串并为每次请求创建独立实例；缓存管理器维护已知字节总量，未超预算的每秒清理检查不再全量遍历。PID 26873 在 14:05:52～14:05:59 的两次滑动 Trace 中，最长主线程回调 10.238ms、最长 ReceiveVsync 6.474ms，窗口内未再出现前一版的 40～86ms 主线程区间；不同页码与缓存状态不能作为严格同条件加速比，也不代表全场景稳帧。≥8ms 的 `ComicPerf` 计时另发现清单编码 8～15ms，因此持久化只保存图片稳定键、地址、页序与尺寸，书源/章节归属在重开时恢复，避免重复写入原请求和整章键。图片预加载、缓存预算/淘汰、书源全链路及精简清单重开回归通过；最后一项精简清单未计入上述实机 Trace。

2026-10-24 漫画滑动 Trace 补充：PID 15038 的连续滑动样本记录 `CreateImagePixelMap` 原图 690×839、目标 4480×5443，以及主线程 `FreeBufferHandle` 205,996,032 字节耗时 20.557ms。SDK `ImageSourceSize` 明确数字单位为 vp，原代码将物理像素预算直接传入导致再次乘屏幕密度。现将预算换算为 vp 后传给 `sourceSize`，并避免解码宽度超过原图；回归覆盖 1/2/3.5 倍密度、原图/超分图/长图，普通阅读保持 4M 像素、1536px 宽、4096px 高预算；捏合放大采用下述预算。相同 Trace 的数据库完成回调另有 50～72ms 主线程区间，书源定义规范化按完整原文缓存不可变字符串（最多八项、合计两百万代码单元）；读取数据库、动态元数据、删除与登录状态仍保留。新版性能须以复测数据判断，不能将预算测试视为帧率结果。

全应用底部弹层统一支持拖动顶部手柄调整高度，覆盖目录、阅读/播放设置、换源、书架管理、搜索、导入、外观和会员等 31 个入口。沿用各入口原始展开高度，通过原生 `detents` 提供原始高度、45% 和系统最大高度三档；原本默认最大高度的弹层提供最大、45%、70% 三档。原按内容适配的弹层仍以内容高度打开。全部显式使用底部形态并显示拖动条，较低档位可滚动访问内容，关闭及保存/导入期间的关闭保护沿用原逻辑。使用 API 11 起支持的高度档位能力，兼容最低 API 20。回归检查顶部手柄上下拖动、最低档内容与底部按钮可达、输入法避让、返回关闭，以及横屏/折叠/窗口缩放后的安全区。

2026-10-23 底部弹层验证：12 个修改文件通过 ArkTS 检查（无错误），Release SDK 26.0.0.105 构建成功，HAP 元数据确认 Release、最低 API 20、目标 API 26，已安装并启动手机。阅读设置弹层实机界面树记录顶部由 y=1618（45%）上拖到 y=164（最大），再下拖回 y=1618；低高度下设置内容可独立滚动，系统返回关闭弹层并保留原章节与页码。自动 UI 验证服务缺少配置，改用设备直接操作及界面树核实。其余入口、横屏/折叠/桌面窗口和旧系统尚未逐项实机覆盖。

会员促销：仅终身商品 `lastVip` 使用 `lifetime_half_2026`，展示华为返回的优惠价和划线常规价；月度 6 元、年度 60 元不参与此活动。后台终身原价 120 元、活动价 60 元，活动覆盖至 2026-12-25 全天（结束时间 12-26 00:00），旧 `cheaplist` 已结束。价格与活动有效性以华为返回为准。购买前重新查询促销商品，优惠失效或价格变化时停留页面重新确认。签名失败停止下单，禁止静默按原价购买。签名服务已部署到中国区 AGC 云函数 `membership-offer` 版本 `1`，App 通过 CloudFoundationKit 客户端鉴权调用；云端测试已返回有效格式的优惠签名。PC/2in1 需 API 23+，不支持时明确停止优惠下单。真实收银台金额和付款仍待邀测验证，不能将云端签名返回成功视为真实支付成功。

会员功能当前开放：账号卡片显示会员入口，已购会员按展示状态显示徽章和彩色昵称，主题页显示会员提示。会员中心提供购买、恢复购买和订阅管理；搜索并发、自动备份及主题图标按现有会员权益规则校验，书源导入对所有用户不限数量且不核验会员。主题入口、主题图标区、“搜索并发数”和“自动备份”标题旁显示金色 VIP 标签，标识功能权益，不代表当前账号会员状态。非会员搜索并发固定为 3，VIP 可设置 1–12；默认图标免费，其他主题图标为 VIP 专享。自动备份下方不再展示“开通会员”按钮；点击受限开关仍执行会员校验，状态核验失败时保留重试。主题入口继续可用。

会员中心在“会员周期”标题旁显示金棕色小字“会员半价活动截至到 2026年12月25日”，窄窗口下允许提示换行并完整显示日期。会员中心右上角并排展示“恢复/刷新”和“管理订阅”，底部不再重复展示；账号区会员徽章紧跟昵称。“我的”页账号区域右侧不显示进入箭头，点击账号区域仍进入账号页面，登录/恢复中保留加载提示。

月度会员在会员中心选择年度套餐并同意购买说明后，主按钮显示“升级年度会员”，进入华为订阅变更收银台；当前月度套餐、已预约年度套餐和年度转月度仍进入管理订阅。升级需核验当前订阅组与月度、年度商品组一致，并完成旧订单发货；若华为返回下期续订年度，页面显示年度预约说明，当前徽章、有效期仍按月度展示，直到签名订单确认年度生效。扣费及生效时间以华为确认页为准。

会员支付校验：订阅凭据同时匹配本应用包名与 App ID，订单中的 App ID 须与订阅载荷一致。按华为数据模型允许省略 `finishStatus`，省略时仍尝试确认发货，已发货错误按幂等成功处理。收银台等待华为真实返回，不设会提前释放购买锁的本地支付超时；查询和确认发货仍保留请求超时。依据：[官方 IAP Skill](https://gitcode.com/HarmonyOS_Samples/iapkit-sample-serverdemo/tree/Java/harmonyos-iap-integration)、[IAP 数据模型](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/iap-data-model)。

漫画分片高度按当前窗口的物理像素取整，图片按既定比例填满分片，避免连续阅读时因缩放留边露出深色细线；解码宽度按物理像素计算并保留像素预算。终身会员标识从原始素材提取透明轮廓，∞ 的两个内孔透明且保留金属高光；外层仅图形与中文会员名称，完整 LIFE VIP 标识仅用于会员中心。

漫画连续列表接章/裁剪使用 `onDatasetChange` 按范围批量通知，避免上百张图片逐条触发布局；重置也使用同一通知协议。逐图完成仍立即发布可显示地址，整章清单按 300ms 窗口合并保存，不阻塞下一张下载；整章预缓存等待最后一次保存后才判定离线完成，强制刷新会等待旧保存退出。回归覆盖 193 张单次插入通知、前后接章锚点、九张完成仅一次合并保存和离线判定。2026-10-24 13:42～13:43 的旧样本已确认耗时纯解析在非主线程（PID 8318、TID 8457/8986），该样本没有此前秒级 Vsync 超时，但仍有短顿反馈；不能将此视为帧率达标。此次批处理的实机效果另行采样。实现参考 [ArkUI 懒加载指导](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/arkui-performance-analysis/references/scroll/lazy-loading.md)。

上述接缝修复通过 ArkTS 检查及 API 26 Release SDK 构建并安装 Mate 80：对比《她的微笑像颗糖》第 2 话第 24–29 张缓存原图确认不存在对应整宽细黑线；修复后抽查同章第 62 页附近，截图无细接缝，布局树相邻边界为 626、1309、1991、2674px，连续衔接。未完成其他屏幕密度与横屏设备验收。

桌面卡片仅 `PlayerCard` 声明 `isDefault: true`；`ReaderCard` 和 `ReaderCompactCard` 为非默认卡片，仍可在卡片管理中添加。发布包校验跨 profile 检查重复默认卡片。

桌面“继续阅读”另提供 `ReaderCompactCard` 1×2 横向小卡片，仅居中显示“继续阅读”四字，无封面、书名及进度。整张卡片可点击，沿用阅读卡片快照与路由，继续最近的电子书或漫画并恢复已有阅读位置；没有阅读记录时打开应用首页。原有 2×2 阅读卡片保留。

EPUB 发布包保留动态模块导出名 `EpubParserService`、`createEpubReaderController` 和 `createEpubReaderBuilder`，避免预解析/导入报 `Cannot read property open of undefined`，或旧 EPUB 阅读入口无法调用。发布校验需传入本次构建的 `--name-cache`；`scripts/test-release-epub-import.cjs` 直接执行混淆后的导入入口并核对阅读组件导出，不能仅以未混淆的开发包导入成功作为验收。

“我的 → 主题”提供并列的“主题图标 / 主题套装 / Tab 图标”页签。底部图标页提供可点击的底栏预览，为首页、书架、记录、我的分别从系统相册选择图片，保存后立即生效；隐藏记录时预览同步隐藏该项，仍保留其图标设置。建议透明正方形图片，非方图居中裁剪，输入不超过 20 MiB、输出最长边 256px 的 PNG，保留透明背景及原色。单项或全部恢复默认后跟随当前主题套装；切换套装不覆盖自定义图片，桌面应用图标保持独立。图标文件与偏好保存在本机，冷启动在页面加载前恢复，缺失文件回退套装图标。保存失败保留原图和原偏好，成功替换/重置删除不再引用的图片，离页时未完成的选图不迟到应用。继续使用原生 BottomTabBarStyle，选中反馈沿用底栏标签与系统指示，不为选图重建导航或迷你播放器。实现参考在线 [ArkTS 语法技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[ArkUI V2 类属性观测](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/02-state-management/v2/arkts-new-observedV2-and-trace.md)及已安装 Release SDK 的 PhotoViewPicker、ImageKit 与 BottomTabBarStyle 声明；维护性回归见 `scripts/test-bottom-tab-icons.cjs`。

2026-11-07 底部图标验证：Release SDK 26.0.0.105 的 Debug HAP 构建通过，包内为 Release / 最低 API 20 / 目标 API 26；`scripts/test-bottom-tab-icons.cjs` 与 `scripts/test-startup-tab.cjs` 通过。手机模拟器确认三个并列页签、系统相册选图与取消、保存后预览及原生底栏即时更新、冷启动恢复、单项和全部恢复默认及旧图片清理。已修正观测单例过早实例化造成的即时刷新问题。独立 ArkTS 检查因 LSP 未初始化不可用，MCP 构建遇到 OHPM 批处理递归错误，实际使用 Release IDE 的 Node/Hvigor `--no-daemon` 编译。未进行物理真机、平板或折叠屏验证。

冷启动时先读取“默认打开”，再以对应索引创建底部 Tab，避免先显示首页再动画切换。创建后底部导航始终绑定当前选中页；播放状态刷新、从详情/播放页逐层返回、切回前台及修改启动设置均不得重新跳到默认页。底栏顺序是首页、书架、记录、我的；隐藏“记录”时，默认“记录”回退首页，“我的”映射到第三项。初始化期间收到的明确 Tab 跳转优先于默认设置。偏好读取失败回退首页。主机回归脚本：`scripts/test-startup-tab.cjs`。

底部 Tab 由原生控制器切换已缓存页面，仅内容区以 180ms EaseOut 从 55% 不透明度淡入；底栏与迷你播放器不参与淡入，不播放整页横移动画。重复点击当前 Tab 不重播淡入；`MainPage.nativeTabIndex` 用普通字段同步保存最新物理索引，`currentTab` 仅驱动子页显隐与页面行为。不可让当前页的响应式状态回写 `HdsTabs` 创建参数，否则同组浮动栏属性会重新应用，重建迷你播放条和封面。书架首次加载在下个任务执行，不额外等待 350ms；热切换不重读书单/进度，当天自动检查的结果复用内存门控；自动或手动检查已逐本应用变化，不在结束时再全量加载书架。进入详情/阅读后的返回同步是另一条路径，仍需更新元数据和进度。定位参考：[ArkUI 性能分析](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/arkui-performance-analysis/SKILL.md)、[状态观测与刷新范围](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/arkui-performance-analysis/references/component/state-observation.md)、[hilog 工具指南](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-studio-hilog/SKILL.md)。

2026-10-21 手机采样：浮动栏绑定修正前，5 次往返产生 5 次 MiniPlayer 创建和销毁；修正后重建消失，但用户仍反馈卡顿。暂停其他设备操作后的 5 次独立切换中，3 次进入书架未新建 FavoritePage 或 CoverImage，300ms 整页横移期间 RenderService 的 RenderFrame 最大耗时分别为 10.34/12.05/9.52ms，超过 120Hz 约 8.3ms 的帧预算；2 次返回全网榜单首页因随机更换六张推荐封面，UI 帧达到 18.25/20.12ms。此证据区分了缓存复用与绘制开销，不能将服务缓存命中当作页面没有掉帧的证明。

直接切换的新包已通过 ArkTS 检查、Release SDK 26 构建，以及书架每日门控/Tab 加载回归并安装同一手机。相同 5 次往返复测中，3 次进入书架的 UI 帧最大耗时为 2.84/2.29/3.50ms；点击后 360ms 内，应用表面标为全屏脏区的绘制从每次 38 次降至每次 1 次，书架及迷你播放栏没有重建。RenderFrame 仍有 8.57–10.48ms 峰值，返回首页随机换封面仍有 14.84–17.60ms UI 帧，不能宣称整机零掉帧。设备确认了书架长按菜单、多选和切 Tab 退出管理；双击回顶与下拉刷新执行了操作，未完整验收网络更新结果。未进行其他设备与系统版本的流畅度验证。

漫画阅读页复用电子书侧边亮度条，随漫画底栏同步显隐；漫画设置提供独立的“显示亮度条”卡片，漫画亮度与开关独立持久保存，自动模式跟随系统，离开漫画正文恢复原窗口亮度。“我的 → 设置 → 外观”提供“智感握姿”总开关，默认开启，控制首页及阅读底栏、电子书/漫画亮度条和朗读小播控跟手效果；关闭后注销握持监听，亮度条恢复右侧，小播控恢复左侧。

上述新增漫画亮度与握姿总开关已通过 Release SDK 构建及偏好回归（漫画/电子书隔离、重载、数值校正、总开关写入失败回退），并安装到手机；手机布局确认漫画侧边亮度条与“我的 → 设置”中的握姿入口。平板、折叠屏及电脑尚未完成设备验收。

正文朗读期间显示圆形封面、播放/暂停、关闭组成的小型胶囊播控，使用与“听”按钮相同的 HDS 沉浸材质（API 20–22 回退背景模糊）。默认位于左侧章节条上方；仅点击正文中间唤出工具栏时显示；隐藏工具栏、翻页或滚动时同步隐藏，暂停不改变此显隐规则。长按 350ms 后只能上下拖动，始终贴边并限制在顶部安全区与底部工具栏之间；窗口变化后按可用区域比例恢复纵向位置。封面打开朗读页且不改变暂停状态，关闭停止朗读并收起播控，正文高亮同步清除。仅显示当前阅读书籍的朗读会话。

亮度条使用明确的侧边坐标，不继承底部 Stack 居中位置。亮度条与小播控通过 API 20 的 holdingHandChanged 跟随左/右手握持；双手、未持握和未知状态保留原侧，不支持感知的设备保留默认位置（亮度右侧、播控左侧）。阅读页声明 DETECT_GESTURE 权限，正文不可见时注销监听。已通过 API 26 Release 构建并安装手机，布局树确认亮度条与播控贴边，截图确认沉浸背景，检查过程中观察到播控从左侧切到右侧；不同设备的握姿识别稳定性及横屏拖动边界尚未验收。

漫画图片直接响应双指捏合，在原阅读位置进行 1–4 倍缩放（连续、左右翻页、渐隐模式均支持），放大后单指拖动查看。取消双击缩放和独立全屏放大页。缩放围绕双指中心，长图拖动边界按当前可见窗口计算，首尾均可到达；缩回 1 倍恢复原图片位置及滚动、翻页。双指接触和放大期间暂停父 List/Scroll/Swiper 与音量键翻页，最后抬指不触发点击或跨章；回收节点和窗口改变时重置缩放。松手后才提升解码尺寸，上限 8M 像素、4096px 宽、8192px 高；普通阅读仍遵守 4M/1536px/4096px 预算。手势竞争依据 [ArkUI 事件规则](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/18-arkts-rules/arkts-interaction-rules.md)处理，stopPropagation 不作为父手势拦截机制。

漫画“左右”翻页设置新增“图片分页”，“图片分页 / 页间重叠”均与翻页效果一样，标题和选择控件横向同行：原图宽度保留单图纵向滚动；整图适屏（默认）将一张原图完整居中放进视口，双指放大可跨越原有留白区域；拼接分页将相邻源图片无缝连续排列，横滑、点按两侧及音量键按视口高度即时翻页。拼接分页可选 0/10/20/30% 页间重叠（默认 10%），不自动识别分镜、不重新编码整章图片；原图本身缺失的内容无法补回。渐隐支持原图宽度和整图适屏。分页、重叠设置全局保存，连续与拼接模式按源图序号及图内比例保存进度，重进和窗口变化后恢复同一阅读位置；拼接模式计数显示“张”，不将源图数量称为屏数。整图适屏语义参考[轻页 ReaderComicSettings](https://github.com/wip3l/legado-harmony/blob/145f70ec5b7211e2608f4c543b853b54611aeb49/entry/src/main/ets/core/reader/ReaderComicSettings.ets)，实现沿用本项目 ArkUI V2。定向回归覆盖留白缩放边界、翻页重叠、同图进度、异步图片尺寸恢复和偏好失败回退。

漫画阅读设置中，翻页效果、翻页震感、音量键翻页、显示章节条、显示亮度条、AI 超分、AI 上色分别使用独立卡片，说明放在对应卡片内部。漫画设置对所有漫画统一生效，退出重进后保留，章节与图片页进度仍逐书保存；旧进度中的阅读模式不再覆盖全局设置。音量键翻页默认关闭，开启后音量加上一页、音量减下一页，连续模式按屏滚动，长图不跳过未读部分；设置、目录、换源弹框及章节拖动和提交期间、页面不可见或进入后台时不占用音量键。漫画章节条首次继承旧共享偏好，此后独立保存，不再修改小说章节条。着色卡片使用独立 HAR 子包进行本机处理，无 API/密钥/模型配置入口；仅有效会员可开启，需设备支持；入口、预热、队列和 AI 宿主均校验会员权益。翻译旁新增“着色”按钮，与设置开关同步；每次进入阅读默认关闭。电子书“显示章节条”独立于页眉设置。朗读倍速范围为 0.5–3 倍，点击关闭停止朗读并回到同书正文与朗读字符位置。

漫画设置、章节和换源弹框保留沉浸材质。弹框从 `onWillAppear` 到 `onDisappear` 期间隐藏底部工具栏、章节滑条及侧边亮度条，减少被遮挡的实时材质参与背景采样；收起动画完全结束后恢复，不销毁底栏，也不重置漫画列表和阅读位置。连续模式在弹框期间对裁剪到视口的正文启用 `renderGroup`，关闭后释放绘制缓存；每张图不再嵌套禁用滚动的 `Scroll`，由外层 `List` 统一滚动，分页模式保留长图滚动。设置弹框固定从底部弹出。实现参考 [ArkUI 绘制缓存指导](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/arkui-performance-analysis/references/animation/render-group.md)。

2026-10-23 漫画弹框验证：修改文件 ArkTS 检查无错误，Release SDK 26.0.0.105 增量构建、安装手机成功。连续模式打开设置后亮度条隐藏，关闭后恢复；弹框开关前后图片边界保持一致，正文图片没有内层 `Scroll`。设备注入音量加/减键后正文按屏前后滚动，并回到原图片位置。短时 Trace 未发现整章重载，最新单次布局峰值为 11.39 ms；采样条件及次数不足以得出稳定帧率或掉帧完全消除的结论。章节/换源弹框及其他设备尚未完整覆盖。

漫画音量键与全局设置验证：三份定向主机回归覆盖默认关闭、保存/重载、漫画与小说隔离、写入失败回退、翻页及连续滚动、边界续章和弹框/后台订阅条件。修改文件 ArkTS 检查无错误，API 26 Release SDK 增量 Debug HAP 构建成功，包内最低 API 20、目标 API 26、apiReleaseType=Release；已安装并启动到手机，在既有漫画中确认“音量键翻页”卡片及说明。自动 UI 验证工具缺少运行环境配置；实体键前后翻页、跨漫画继承和重启记忆尚未完成完整实机验收，主机回归不替代设备结论。

电子书正文右侧提供竖向亮度条，与底部工具栏同步显隐；阅读设置可独立关闭亮度条。亮度与开关持久保存，“自动”恢复跟随系统，离开正文恢复原窗口亮度。朗读页刷新按钮旁新增进入阅读按钮，保留朗读；正文分页及上下滚动模式正常跟随朗读位置自动翻页/滚动；手动翻页、滚动和选字期间暂缓自动跟随，确认翻页或目录切章后从新页原文位置继续，上下滚动在停止后从可见内容继续。取消翻页不跳读，暂停会话不因翻页自动恢复；高亮当前朗读自然段，工具栏显示时也保留高亮。本轮通过 Release SDK 构建、阅读偏好与朗读导航回归及 31 项 TTS 回归；设备连接已断开，新增亮度条和边听边读入口尚未完成真机验收。

书架搜索展开时，列表回到包含导航占位的起点，类型筛选与书卡整体下移，保留首行间距；收起与输入筛选后也沿用同一起点。Search 显式清零默认外边距，避免上下额外的 16vp 使筛选栏溢出导航区、挤掉书卡间距。失效有声书打开自身播放器并提示换源，不回退到另一部正在播放的书；未切源前不复用另一部书的章节、进度及播放控制。取消换源仍留在所点书籍，已有下载可继续播放，禁用搜索但保留定义的书源仍可解析。

书架分组菜单始终提供“全部分组”和“未分组”。管理多选栏支持批量设置分组；详情页在阅读/收听记录前提供“分组”；本地导入支持选择或新建分组，默认未分组，应用到本次音频、电子书及 ZIP 导入结果。每本书仅属于一个分组，移组后不再显示在原组；命名分组的单本菜单与批量删除支持“仅在当前分组删除”，移回未分组并保留收藏、本地文件和记录。

书架删除确认框与书卡退场后立即退出管理、移除待删卡片并恢复滚动、筛选、搜索、打开其他书籍及返回。文件、章节缓存和记录在后台串行清理，连续提交的批次共用队列；大章节目录使用异步文件删除并分批让出事件循环。失败项恢复到书架并提示重试，后台完成不重置后来打开的弹框或新的多选状态；离开页面仍完成已确认任务，不访问已销毁页面的 UI。默认仅移出书架并保留文件与记录。实现参考在线 [ArkTS 语法技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[ArkUI 生命周期规则](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/18-arkts-rules/arkts-ui-basic-rules.md)与[高频工作性能规则](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/arkui-performance-analysis/references/component/frequent-work.md)。

书架排序：置顶书保持在最前方并保留置顶顺序，普通书按最近加入、阅读或收听的操作顺序前移，小说、漫画、音频和正文朗读共用此规则。排序复用收藏列表持久化，重启和备份恢复后保留；连续保存同一本书的进度不重复写入排序或刷新书架，未收藏及已移出的书不会因进度回调重新加入。

上述改动通过 API 26 Release SDK 构建与手机安装。手机实测覆盖漫画独立设置卡片、电子书章节条独立卡片、批量移组后的计数与列表更新、仅移出分组、详情/导入分组入口，以及 3 倍速切换和关闭朗读返回正文。实际导入新文件后的分组落盘及平板/折叠屏/电脑仍未做设备验收；主机回归覆盖分组持久化、保留文件、写入失败和朗读速度/路由。

桌面新增“继续阅读”2×2 方形卡片：浅色底、左右布局，左侧封面按原始比例完整显示，右侧显示书名与“继续阅读 XX%”，本地无封面书籍使用统一占位封面。网络封面缩图保持原始宽高比，缓存版本升级后不复用旧的方形拉伸图。整张卡片可点击，恢复原有小说/漫画阅读位置。百分比按当前章节位置计算；没有记录时引导打开应用。阅读进度保存后同步卡片，同章翻页不重复刷新展示；独立于播放卡片，点击阅读卡片不会触发启动自动播放。

书架 Tab 性能：首次加载合并生命周期触发，阅读进度由保存事件更新，历史目录扫描分段让出主线程，自动检查延后且离页取消。书架顶部搜索、筛选、分组、更新和视图按钮使用原生圆形 Button，使用半透明页面同色底（浅色 #80F5F5F5、深色 #801A1A1A）和半径 12 的原生背景模糊，亮度与饱和度均为 1，避免预设磨砂额外提白；不再为每个按钮嵌套带材质滤镜的 HdsTabs。其他页面默认材质模式保留。Mate 80 的 hitrace 在点击抬起至 Tab 动画结束窗口内，修复前书架 RenderFrame 平均 8.88ms、26/36 帧超过 8.33ms；去除嵌套 HdsTabs、使用普通按钮后的两次分别平均 7.96/8.07ms、均 10/37 帧超过预算；记录页对照为 7.92ms、9/38。最终同色轻磨砂版本已通过编译并安装，后续采样时设备连接断开，因此上述复测数据不代表最终磨砂版本。指标为系统渲染线程 CPU 时间，受其他系统窗口及调度影响，不等于实际屏幕丢帧数，也不代表所有设备无掉帧。采集使用 ace/app/graphic/sched/freq/idle，按真实切换动画事件截取；采用已读取的 [ArkUI 性能指导](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/14-performance/analysis/ui-performance-overview.md) 中“定位 Trace 耗时后复测”的流程。

2026-10-19 书架与阅读补充：书架选中的分组保存到本机偏好，退出重进恢复；全部/有声书/电子书/漫画数量按当前分组统计。列表/宫格模式同样保存到本机，页面恢复时读取，连续切换按操作顺序写入，迟到的初始化读取不会覆盖用户刚选的模式。来源开关保存后通过事件及书架可见时同步刷新书卡，无需重启。Mate 80 已验证分组进程重启恢复、分组数量以及网格来源开关双向更新。2026-11-08 阅读选区修订：分页选字始终保留原 Paragraph 正文；选区高亮、手柄与拖动命中统一使用原段落的字形范围、分页起点和逐行偏移，菜单锚定实际选词位置，经 PlatformCompat 守卫使用 AppMaterial.Sheet 沉浸光感材质和透明底色，旧系统回退磨砂。应用排版不再用透明 Text 重新排版定位手柄。翻页手势固定注册，在回调中隔离活动选区。本次手机实测覆盖长按定位、两端跨行拖动、沉浸菜单与外部点击关闭；重进阅读恢复原章节与页码。连续滚动、多栏、字体/窗口变化及旧系统回退仍待设备验收。交互实现参照已读取的 [ArkUI 交互规则](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/18-arkts-rules/arkts-interaction-rules.md)。

桌面听书卡片同时接收有声书与电子书朗读的书名、作者、封面、章节和播放状态，后台暂停/恢复继续同步。快照保留播放类型，电子书字符位置独立保存；卡片播放、暂停和上下章按播放类型分发，冷启动可恢复电子书。旧有声书暂停/释放回调不能覆盖最近的电子书快照。主机回归覆盖前后台同步、冷启动控制、字符恢复、倒序切章及迟到命令取消，Release SDK 编译和手机安装通过；有声书桌面卡片播放、暂停、续播与图标同步已通过手机实机验收，电子书卡片实际交互及列表模式进程重启仍需设备验收。

卡片暂停直接交给当前音频或朗读服务，同时取消未完成的冷启动播放；不等待初始化或读取持久化快照。正在播放的有声书优先按实际运行状态分发，历史朗读快照不能拦截其播控。点击入口不再并行清空偏好缓存并预写播放状态，图标由播放器实际状态回传，避免暂停命令与卡片刷新竞争。卡片登记、播放快照分别使用独立 Preferences，避免主应用和卡片进程写入同一个偏好文件时覆盖登记或状态；只刷新对应卡片缓存，兼容旧数据，清空记录同步清除新快照。主机回归覆盖缓存不可读、旧朗读快照、初始化等待、暂停取消迟到播放及跨进程整文件写回；2026-10-27 手机实机确认后台有声书多次播放、暂停及原进度续播，播放器收到 source=widget 的命令并切换 playing/paused，卡片登记保持 forms=1，截图确认暂停与播放图标同步切换，最终保持暂停。该结果不覆盖电子书朗读、长时间后台、鸿蒙 6 或手表设备。

后续反馈修订：分页与连续阅读的短按直接通过闭环触摸事件和位移/时长判定，按已设置的点击区域呼出工具栏或翻页；长按继续走选字，选区内短按明确清除选区，拖动选区不触发点击。电子书和漫画隐藏章节条、底部工具栏时同时使用 `Visibility.Hidden` 和禁用状态，避免仅透明及父层 `HitTestMode.None` 仍让子节点响应，保持正文布局稳定。电子书听书页采用左封面、右来源/书名/作者，下方章节区不重复书名。书架长按菜单中“查看详情”下依次为“设置分组”“封面与重命名”，两项各有独立内容；分组列表提供删除按钮，必须经确认弹窗后才落盘删除，原组书籍恢复为不分组，当前筛选若已被删除则回到全部分组。此轮手机离线，最新触摸改动和布局尚待安装实测，不能沿用上一包的设备验证结论。

漫画设置的“翻页模式”复用小说阅读设置的 `ReaderSettingCard` 和右侧 `ImmersiveOptionTabs`，提供上下滚动、左右翻页、日漫 · 从右向左、消散模式四项，选择后保留设置面板。日漫模式点击左侧或向右滑动前进，点击右侧或向左滑动返回；章尾前进进入下一章，章首返回进入上一章末页。阅读模式全局持久化，旧日漫方向偏好保留，切换模式保留原章节与图片位置。漫画两侧短按在 Touch Up 立即翻页，原生 Click 只处理工具栏，避免双击缩放识别造成约 300ms 等待或重复翻页；双击缩放限于中间区域。左右分页动画统一为 260ms/EaseOut，保留两侧邻页，动画中阻止重复请求。`test-comic-page-turn` 验证实际处理函数的立即翻页、重复点击隔离、工具栏、长按/移动/取消与动画锁，以及日漫点击方向、跨章滑动边界和模式持久化。日漫恢复本轮 ArkTS 检查无错误、定向回归通过；已绕过本机 ohpm/Hvigor 启动故障，使用 Release SDK 26.0.0.105 完成 Debug HAP 构建，包内最低 API 20／目标 API 26／Release 渠道；已安装并启动于 VYG-AL00 实机，日漫翻页交互仍待实机验证。

漫画设置提供“同章图片预加载”：关闭、2、5、10、20 张，默认 5 张，独立保存到 Preferences。滚动与分页模式均只提前下载当前阅读位置之后的指定张数，至章尾停止；切页、切章、修改设置、进入后台或退出阅读会取消旧窗口，回到前台重新计算。跨章整章预缓存仍按全局章数执行，进入目标章后停止该章的整章预取，交由同章窗口控制；已经缓存的图片继续复用。后台请求仍受公共图片加载器并发限制，可见图片优先。

本次同章预加载验证：`test-comic-preload`（张数、关闭、章尾、复用与取消）、`test-comic-page-turn`、`test-comic-continuous` 通过；Release SDK 26.0.0.105 Debug HAP 构建通过，包内最低 API 20 / 目标 API 26 / Release 渠道，已安装启动于 Mate 80。尚未完成漫画设置与保存恢复的实机交互验证。

漫画点击区域按最新反馈固定为横向三等分，删除设置中的左右宽度与上下高度滑块，不再读取或修改小说阅读页的区域比例。分页/消散模式左侧上一页、中间工具栏、右侧下一页；上下滚动模式保留点击呼出工具栏。

电子书播放页顶部音色入口复用有声书的小弹框，先逐项展示系统实际提供且已安装的自带音色（包括当前设备的两个音色），各自显示名称、独立选中并调用系统音色切换，后面列出已导入音色；不再用一个“默认自带音色”合并两个选项。没有导入配置也可以分别选择自带音色，导入仍在阅读页“听”的设置中。竖屏正文使用播控上方的剩余高度，短窗口保留滚动布局；正文上下以透明渐变蒙版柔化边缘，背景保持透出，蒙版不拦截触摸。朗读分句将连续问号等尾部标点归入上一句，跳过纯标点、纯符号与纯表情片段；星号、装饰分隔符和不可见控制字符仅从合成输入清理，英文、数字与正常标点仍保留。整章只有分隔符时按原有章末设置停止或继续下一章，网络/引擎错误仍正常报错。数字脚注 `[10]` / `【10】` 仅从合成输入去掉，原始正文与章节字符位置不变。`test-player-speech-voices` 验证两个自带音色各自切换、导入音色来回切换、选中项定位及有声书菜单；`test-text-to-speech` 的 43 项回归通过，包括示例脚注、连续问号、系统语音推进和原有导入音色/暂停/恢复用例。布局依据已读取的 [ArkUI 指引](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md)，语法依据 [ArkTS 规范](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)；真机检查范围另行记录。

本轮已使用 Release SDK 26.0.0.105 编译并安装到 Mate 80：第 318 章从原报错附近继续朗读，进度推进到 76%，未再显示语音错误；已查看正文扩展和上下渐隐截图。顶部音色弹框的空列表/导入音色切换尚未完成本轮真机验证。

电子书播放页进入定位：同步取得当前朗读书籍后按段内播放坐标准备自然段与段落序号，列表使用 `initialIndex` 直接从当前段落创建可见项；首帧布局完成后，通过 TextController 的真实字符矩形定位当前行，保持在文字视口中央。长段内部随音频进度换行跟随，同一行不重复启动滚动动画；首尾留白，窗口尺寸改变后重新居中。段内播放坐标独立于阅读持久位置，不触发正文逐字重排；系统音色和自定义 HTTP TTS 均使用真实播放进度估算字符位置，不承诺逐字精确同步。懒加载定位有限重试，列表卸载时失效待执行定位并释放控制器引用，控制器表上限 64 项。

本轮定位与默认音色修改已用 Release SDK 26.0.0.105 编译通过；依照已读取的 [ArkTS 编译修复指引](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-syntax-checker/SKILL.md) 及本机编译诊断，将 List 卸载回调校正为 `onDisAppear`。当前设备列表为空，本轮新包尚未安装，首次定位速度与默认音色弹框仍待真机验证。

## 漫画

设置 → 图像与翻译提供“去除白边”，默认关闭，漫画全局持久化。后台将原图缩至最长边 768 像素识别四周连续白色外缘，保留两像素保护边、每边最多裁 25%；空白页、透明边及有正文触边时保守保留。仅裁剪显示，不改原图或原始宽高；适宽、完整显示、原图大小、连续/分页、1–4 倍缩放及 AI 图片复用裁剪框。连续阅读等裁剪尺寸就绪后恢复当前图片内进度，检测失败保留原图。

2026-10-19 预缓存补齐：普通 HTTP 图片也通过 App 侧桥接调用公共核心 `ComicImagePipeline` 写入 `comic_images`，每批最多四张，沿用源 Cookie、请求头、解密与单图 20 MiB 上限，不改上游托管文件。按“预缓存章节数”逐章等待图片落地；清单解析和图片预取分别去重，当前章打开不等待整章图片。全部本地文件有效后才显示整章缓存勾，失败仍可在线读并保留云朵状态；离页、后台或明确跳章取消旧预取。`test-comic-preload` 使用真实图片管线和缓存服务验证普通图片下载、本地恢复、四并发上限、任务复用、打开不阻塞、取消/失败和文件缺失失效。

电子书“跟随系统深浅色”模型及偏好缺省值统一开启，恢复默认也开启；已明确保存关闭的设置继续保留。`test-reader-preferences` 验证缺省开启、保存恢复、重置和已有关闭值兼容。

本轮连续滚动、图片预缓存、阅读偏好及公共引擎主机回归通过；Release SDK 26.0.0.105 构建通过并安装、重新启动 Mate 80。实际漫画源已验证清单解析及图片显示入口，本轮完整跨章流畅度和离线整章阅读尚未完成真机复验。

2026-10-19 目录一致性修订：漫画章节弹框按电子书目录布局统一标题、章节总数/分段切换、`ChapterSheetActions` 正倒序与首尾定位、搜索、分段网格和“回到当前章节”。打开列表自动定位当前章，当前行显示品牌色标题和右侧 `scope` 标记，缓存云朵/勾号统一位于行尾，整行可点击；点击当前章保留图片位置。目录列表使用真实章节身份懒加载。沿用本轮读取的 [ArkUI 指引](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md) 与 [ArkTS 规范](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)。Release SDK 26.0.0.105 编译与 `test-comic-page-turn` 回归通过；安装时 Mate 80 已断开连接，本次目录改动尚未安装及真机验证。

当前漫画加载分为目录恢复、整章图片清单解析和图片显示。先恢复章节/图片序号，检查该章清单中的全部本地图片文件；任一缺失或仍是网络地址，都不算完整离线缓存。缓存未命中时走导入书源公共链，图片清单先返回，图片下载和解密由 ComicImageLoader 调度公共核心，首图无需等待整章。当前章按图片预加载数量提交后续图片，后台最多两张并发，可见图片优先，总并发最多六张；翻页保留重叠窗口和刚进入视口的在途任务，离开窗口、后台、切章或设置变化会停止失效任务。图片落盘即通知已挂载的屏外邻页提前装载，不等待章节清单写盘；通知不会重置已装载图片，节点回收时移除监听。章节成功后按“预缓存章节数”串行预取后续章，预取失败停止本轮预取，不打断当前章；切章复用目标章在途请求并提高优先级，取消其余请求，离页停止预取。切章成功才更新当前章节与图片页，失败保留原章。目录云朵表示未具备完整本地整章缓存，不等于该章从未看过。

连续滚动使用独立 `ComicContinuousComponent`，相邻章图片增量加入同一列表，通过稳定图片身份和 `maintainVisibleContentPosition` 保持视觉锚点，自动接章不整章刷新、不跳到顶部。接近列表两端时准备相邻章；关闭预缓存时等到实际边界再请求。等待/失败只显示边界加载或重试入口，保留当前图片；章节标题、目录高亮及进度跟随首张可见图片所属章节。保留当前附近章节，最多五章，只删除屏幕外远章；预取解析结果另有七章以内的内存复用窗口。目录选章、手动切章、刷新或改变排序才明确重置连续列表。分页读至最后一图后继续向下一页滑动，仍按原逻辑进入下一话。`test-comic-continuous` 覆盖增删锚点、章节页码映射、倒序、请求去重、旧请求隔离、失败重试与关闭预缓存；`test-comic-page-turn` 覆盖原翻页手势。

设置提供“消散翻页”，采用淡出/淡入，阅读模式按漫画全局设置恢复。AI 超分为有效会员主动开启的本地处理：API 26+ 且具备系统视觉能力时，处理可见的本地缓存静态图片；复用固定版本轻页 HAR 的重叠分块处理：单块边长不超过 2048、像素不超过 512K，原生四倍超分后按显示物理宽度收敛，整图输出约束在 12M 像素；不支持或失败保留原图。结果使用 comic_images/sr_ 缓存，与原图和着色共用 5 GiB 预算，不再读取旧 comic_super_resolution_v1 结果；增强图不会改写原图宽高，开关本机持久化，不上传漫画。漫画着色使用 `@legado/aiengine` 独立 HAR 子包的本地 AlacGAN / MindSpore Lite，不配置远端 API、不上传漫画。翻译右侧为“着色”按钮，开启时主题色高亮，再次点击关闭并恢复原图；设置卡片与工具栏同步。仅有效会员在设备支持时可操作，每次进入阅读默认关闭；会员失效时取消在途任务并恢复原图，缓存结果不能绕过校验。仅处理可见缓存图，Worker 串行执行，关闭、后台、弹框或离页取消当前任务；失败关闭本轮并保留原图，可重新开启重试。CPU 与 NNRT 模型随包，首次处理可能较慢；着色结果独立保存并计入原漫画缓存预算，可与翻译同时开启，先上色再在彩色图上绘制译文；关闭其中一项保留另一项效果。子包安装方式及设备验证边界见 `COMIC_AI_ENGINE.md`。

搜索结果、书架、记录/未收藏历史、书源管理以及榜单版本匹配均提供“漫画”分类；书源管理的类型筛选与用户自定义分组叠加。首页仍展示所选导入源自己的发现分类，漫画书卡经详情进入独立漫画阅读页。

漫画阅读采用深色背景、绿色强调色和可收起的顶部/底部工具栏；默认连续滚动，另提供左右翻页和右至左日漫模式。目录按每书章节顺序显示，上一话/下一话沿用该顺序。底部章节条参考轻页，通过 HdsTabs.barFloatingStyle 的 systemMaterialEffect 使用官方 IMMERSIVE 沉浸光感材质（API 23+，旧版回退磨砂），左右切章按钮和 OutSet 章节滑块；拖动显示目标章节标题和全书百分比，松手直接跳章，倒序目录映射到阅读顺序。仅轻点屏幕横向 10%–90%、纵向 15%–85% 区域切换工具栏，滑动及边缘点击不切换，双击居中放大/还原。长章节使用 LazyForEach 和少量邻页缓存；图片保持原比例，大窗口正文限宽。单图失败可重试，整章失败保留返回、目录及相邻章节入口。

漫画工具栏默认收起，正文铺满屏幕，顶部/底部工具栏叠加在正文上，工具栏按窗口安全区避让，状态栏随工具栏显隐。图片及空白区域点击统一按屏幕中间区域判定；顶部为返回、刷新、换源、详情四个悬浮圆形按钮，无标题背景。目录、设置和换源各用独立 bindSheet 宿主，底部按钮独立响应点击。底部复用小说阅读页的 HDS 沉浸光感浮动 Tab，提供上一话、目录、设置、下一话，旧 API 使用兼容回退。底栏和收起时的页码放在独立的全高底部对齐 Stack 中，不能用子节点 `.align()` 代替父 Stack 的定位；未加载图片时不显示页码或滑块。加载失败日志记录异常和图片数量，不输出章节正文或源地址。2026-10-15 已在 VYG-AL00 实机显示 G站漫画《武炼巅峰》的正文图片；未验证的来源和设备不能由这一结果推定可用。

章节图片清单复用 OnlineTextContentCache 存储，只有全部本地图片存在才视为缓存命中；丢失后重新取章。预缓存按原设置数量串行执行，切章/离页后停止旧队列，当前章复用在途请求并提升优先级，预取使用低优先级。明确跳章才取消其他章节旧请求并在成功后替换画面；连续滚动保留相邻章及在途请求，只增删边界图片。失败保留当前章。刷新清除当前章清单及已验证的漫画缓存图片再获取；系统图片缓存清理包含 comic_images。目录显示实际缓存状态。直接远程图片地址不冒充离线缓存。

公共核心返回的缓存/解密图片路径必须通过 `fileUri.getUriFromPath` 转为 ArkUI Image 可读取的 URI，保持 HTTP/data/file URI 原样；裸沙箱路径会被当作资源路径并报 `GetAsset failed`。图片首次装载前异步读取本地文件头的真实宽高，预取时一并保存到章节清单；Image 首次构建就使用该比例计算高度与解码尺寸，完成回调不重复修改已知比例。尺寸读取失败保留原有解码回退，所有 ImageSource 均释放。连续列表只在首个可见图片身份变化时上报位置，避免尾部可见项变化和停止滚动重复触发父页面更新及进度保存。网页抓取宿主位于 Index 导航外层，避免阅读时随首页 NavDestination 隐藏，继续使用按需挂载、隐私模式和独占 Web 会话。

阅读位置按“章节 + 图片页 + 长图内比例”保存，返回书架、记录及会话历史可继续漫画阅读；阅读模式与震感为漫画全局偏好。漫画支持同类型在线换源，不提供音频下载或朗读。漫画与电子书章节滑条共用 ReaderChapterJumpHint：拖动预览标题和百分比，松手直接跳转，提示为无外溢阴影的沉浸圆角胶囊，仅显示系统 undo 图标及圆形触区。连续跳转保留本轮首次跳转前的章节、图片页和长图内比例，点图标恢复；失败保留原页或撤销入口，隐藏工具栏、打开目录/设置及离页清除提示。漫画“翻页震感”依次为无效果、强劲、中等、弱感，默认关闭，与小说独立保存，选择后反馈一次。手动左右翻页、渐隐、长图按屏翻页及滚动位置真正变化时反馈；一次滚动手势仅反馈一次，自动翻页、恢复重排、缩放和边界未移动不反馈。

本次章节交互参考在线 [ArkTS 语法技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[ArkUI 开发技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-develop-skill/SKILL.md)及 [事件响应规则](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/18-arkts-rules/arkts-interaction-rules.md)；在线目录及相关原文已读取，未运行上游检索脚本。

参考：[Mihon](https://mihon.app/) 的多阅读模式与来源独立设计、[WEBTOON](https://www.webtoons.com/en/) 的分类与封面展示，以及轻页固定版本的 `ReadBook.ets`、`ReaderImageMarker`、`ComicImagePipeline`。ArkUI 实现依据已读取的 [在线检索技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md)、[LazyForEach 指南](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/09-rendering/arkts-rendering-control-lazyforeach.md) 和 [ArkTS 语法技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)，保留项目 ArkUI V2 约束。

本文记录手机、折叠屏、平板及鸿蒙电脑的页面行为，作为 UI 开发与真机回归基线。架构和数据说明见 [CLAUDE.md](../CLAUDE.md)。这里的回归清单是验证要求，不代表每项已在当前设备执行。

应用对外名称统一为“简听阅读”，桌面入口、播放卡片、关于页面和隐私政策保持一致。当前上架文案与实机截图见 [app-gallery/README.md](app-gallery/README.md)。

## 主框架与导航

- EPUB 正文插图与前后文字共同分页：按图片像素尺寸显示，小图不放大，超出正文宽度或翻页可用高度时等比缩小；仅剩余空间不足时换页。滚动模式不强制整页高度，双栏按单栏宽度重新排版。旧导入书籍打开时读取图片头尺寸，无需重新导入；原字符坐标保留，阅读位置和朗读高亮沿用现有映射。本次实现依据 [ArkUI 组件与状态指导](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md)，使用现有 V2 组件承载混排片段。

- “我的”保留本地导入，移除该页的下载管理入口，增加“日志管理”。日志默认关闭，可在日志页手动开启“记录日志”，开关状态仅保存在本机；关闭后停止新增诊断记录并保留历史，运行检测仅在开启时可用。日志页支持刷新、仅错误筛选、复制和确认清空，最多保存最近 200 条本机记录；运行检测检查 API/设备能力、可用空间和临时文件读写。导入记录选取数量、格式、大小、解析及保存阶段与错误码，不主动记录文件名、正文或账号。EPUB 解析通过隔离的本地模块按需加载 ReaderKit，避免直接动态导入系统 HSP 导致解析器未定义。
- EPUB 优先读取 spine 对应的原始 HTML（含转义路径，最多 32 MiB）并进入现有纯文本转换；原文不可用时回退系统排版接口，回退失败仍报告错误，不跳过章节。2026-10-02 在已连接 API 26 手机验证：原失败 EPUB 导入 42 章并打开/翻章，MOBI 导入 340 章，日志检测、错误筛选和复制通过；本地回归覆盖原文回退/缺失章节拒绝、日志限量/持久化/脱敏/清空。本次没有平板实机验证。
- 2026-10-02 历史性能验证：同一 API 26 手机、同一《凡人修仙传》EPUB（14,853,515 bytes），2469 章正式导入从 66.427 秒降至 7.447 秒；全部章节正文 SHA256 和目录标题/顺序一致。该记录对应当时的解析实现，不能作为当前自研 ZIP/XML 与原版资源导入的耗时。音频最多 4 路复制/探测，ZIP 临时音频直接移动，用户选择的原文件保留。本地音频恢复目录后使用新书籍引用刷新 V2 界面，避免缓存对象原地更新导致误显示空目录；当时实机 M4A 导入、目录显示和播放进度验证通过。
- 当前多章节电子书导入将正文和 EPUB 原版页面/章节映射按最多 16 文件或 256 Ki 字符一批交给后台写入，最多 4 个在途任务；保持 150ms 进度节流，尾批完全落盘后才报成功。EPUB 按授权 URI 读取，预览和正式导入都不复制整书；最多 4 章/512 KiB 并行解压，大单章独占一批，目录按路径索引。纯文字转换每批最多 64 片段/512 Ki 字符，图片和超大片段保留逐段处理。保留全文、目录顺序、插图、原版资源及失败回滚；读取失败先等待同批读取，写入失败先等待在途任务，再清理本书目录。日志分别记录转换任务等待及章节装配，写入活跃时间与解析重叠，不可直接相加。
- EPUB 中各章重复引用的图标、插图和背景，在单本书导入内按完整资源路径复用同一图片文件，保留全部引用位置；不同目录同名图片分开保存，失败读取不作为缓存命中。缓存仅保存路径，图片字节和尺寸仍受原限制约束。2026-11-10 的实际 1579 章 EPUB 导入生成 2301 个图片文件、共 894,202,693 bytes，暴露了纯文字基准没有覆盖的重复图片开销；对应回归覆盖 2000 次引用只读取/落盘一份图片、图片位置与字节一致、路径隔离及失败重试。导入/解析回归与 Release SDK 26.0.0.105 编译通过，该书优化后尚无有效的同机精确计时。实现约束参照已查阅的 [ArkTS 语法规范](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)，设备日志按 [hilog 技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-studio-hilog/SKILL.md) 以应用进程过滤。
- 2026-11-10：主机导入及自研 EPUB 解析回归通过，覆盖 2200 章导入、尾批、UTF-8 短写入、并发/内存限制、损坏条目和写入失败清理；Release SDK 26.0.0.105 的 Debug 应用与定向导入测试包编译通过。同一 API 26 手机、同一 5000 章生成样本：修改前预览 1.389 秒、正式导入 53.162 秒、合计 54.551 秒；优化后预览 0.890 秒、正式导入 26.691 秒、合计 27.581 秒，总耗时减少约 49.4%。设备用例验证 5000 章数量及首/中/末章目录和正文，主机回归验证逐章内容、原版资源及失败清理。该结果仅代表此生成样本，不替代用户实际书籍、PDF 渲染、音频复制或其他设备实测。设备测试编译临时限定到现有本地导入用例，避开其他旧书源测试对已删除模块的引用，编译后已恢复原测试入口。

- 安装目标为 `phone`（含折叠屏）、`tablet`、`2in1`（鸿蒙电脑），最低 API 20、目标 API 26。电视、车机与穿戴设备不在当前设备声明中。
- 电脑首页返回使用窗口最小化，手机/平板沿用移到后台；扫码导入先检查系统能力，不支持时隐藏扫码入口，仍可从文件、粘贴规则或链接导入。
- 多端布局基于实际容器宽度（vp）：书架、搜索结果和分类书单在 320–599vp 保留三列，小于 320vp 为两列，600vp 起按可用宽度增加列数；加载更多占满当前列数。窗口缩放只调整布局，不重新发起搜索或清空选择。
- 播放器在宽度达到 600vp 后使用左侧封面、右侧可滚动播控，较窄窗口保留纵向布局。设置页在 840vp 起使用双列。主页面保留四个底部 Tab，宽窗口浮动导航及迷你播放区域居中限宽。
- 阅读正文最大行宽为 760vp，额外居中缩进不修改用户保存的边距；在线文本与 EPUB 均以当前窗口排版。重新分页按章节和字符位置恢复，不按旧页码恢复。字体像素换算使用当前 UIContext。
- 书架每天首次进入或在书架回到前台时静默检查在线收藏，按本地自然日持久化去重；同日失败不反复自动请求，书架取消下拉刷新，仅保留顶部“书架更新”按钮，进入面板后通过“立即检查”手动重试。空书架和纯本地书不消耗当天检查机会，详情与目录最多三本并发。自动检查不弹提示；工具栏“书架更新”可查看持久化的最近结果。更新结果使用原生沉浸光感半模态弹层（旧系统回退磨砂），展示检查时间、封面、书名、最新章节、更新前后总数、新增章/集徽标及失败数量，列表懒加载；点书关闭弹层后进入详情。
- 书架网格与列表的封面底部显示半透明书源名称标签，按书籍 sourceUrl 匹配已导入源（含停用源）；长名称最多两行并省略，不使用主播或分类代替来源。未匹配来源时显示原来源地址，本地书无书源标签；顶部保留内容类型、置顶和选择标记。
- 删除书源只清除定义及其登录会话等来源数据，书架、阅听记录、进度和书籍元数据继续保留并参与备份。已删除源的电子书仍进入阅读页，有声书进入播放器，均可使用现有换源入口；不因来源库为空或暂时读取失败隐藏收藏。
- 云同步启动返回 22400001（系统云服务尚未就绪）时，间隔 1 秒、3 秒最多重试两次；等待期间可取消，换号后不重试。持续失败保留原云备份，不标记成功；账号页单独提示检查系统云同步并可使用本地备份。日志开启时记录失败阶段、系统码和重试次数，不记录账号或备份内容。
- 书架长按和鼠标右键打开同一操作菜单。阅读正文在工具栏与弹层关闭时支持左右方向键、PageUp/PageDown 翻页，不依赖音量键设置；设置、目录、朗读和输入弹层打开时不抢占按键。
- 多端回归要求：手机竖横屏、折叠屏展开/收起、平板全屏/分屏、电脑自由窗口缩放；检查 599↔600vp、839↔840vp 切换，书架选择/右键、首页骨架/刷新/双击回顶、阅读字符位置/字号/边距/安全区及播放操作。构建和模拟服务回归不等同于平板、折叠屏和电脑实机验收。

- 底部四个 Tab 为“首页 / 书架 / 记录 / 我的”。单击切换，在 300ms 内双击当前 Tab 回到该页顶部；首页双击只回顶。
- `Index` 使用 `NavPathStack` 集中管理搜索、详情、阅读、播放、下载、导入、书源、账号、设置等路由。
- “我的”昵称后显示现有 16vp 会员图标，间隔 6vp，长昵称省略时保留图标。昵称下方以 12fp 金色显示“Lv.1 初识书声”等等级与对应勋章名称，长名称单行省略。账号身份核验和成就加载完成后展示。等级复用九枚勋章门槛（1/10/50/100/300/500/1000/2000/5000 小时），不足 1 小时默认 Lv.1；等级取账号已获最高勋章，与佩戴选择无关，删除阅听记录或清零统计均不降级。游客数据仅在首次迁移时归入首个核验登录账号，后续账号独立累计。退出或切换账号立即隐藏上一账号成果，同账号再次登录恢复；云端跨设备恢复使用现有同账号云备份流程，不是自动实时同步。
- “我的”页面不显示“内容来源”“我的内容”“系统”分组标题，保留卡片分组和功能入口；在“关于”下方提供“简听交流群”入口，行尾显示群号 602330717；点击优先用 `mqqapi://card/show_pslcard` 拉起 QQ 群资料页，未安装 QQ 或系统未匹配时回退到浏览器打开 QQ 官方加群链接 `https://qm.qq.com/q/dzljNVMPJu`，都失败时提示重试。
- “我的”在“日志管理”正上方提供“使用教程”；“关于”页保留版本与获取更新、使用教程、开源声明、技术与支持、合规说明、隐私政策入口，两处教程复用 `guide` 路由及 `GuidePage`。“获取更新”通过包名 com.huan.listenbook 打开华为应用市场详情页，失败时尝试官方 HTTPS 页面，由市场显示是否可更新；不再启动 GitHub 版本检查或显示其缓存红点。“技术与支持”打开星光致谢页面：顶部深绿黑金主视觉展示双向旋转光轨、呼吸光晕与悬浮爱心；技术支持和感谢赞助保留“排名不分前后”，开源轻页与 HenDo 使用黑金重点卡片，其余名字使用主题色／金色自动换行按钮。每个名字首次进入可见区时交错淡入、上移，按压缩放回弹，点击打开带姓名与感谢语的居中原生弹窗；弹窗具有独立星轨、缩放淡入与遮罩动效，可通过关闭按钮、底部按钮、遮罩、系统返回或 Esc 关闭。底部“还有正在阅读的你”也可打开感谢信。25 位名单成员分别对应独立的资源字符串感谢信，通过姓名映射保持顺序调整后文案不串人，不再按索引轮用模板；轻页与 QG 使用用户提供的完整感谢原文，长信可滚动；页面自动播放动效，不提供暂停／播放按钮；后台、离屏和弹窗展示时暂停对应背景动效。内容按实际容器宽度适配，840vp 起双栏、最大 1000vp，页面与名单表面跟随深浅主题；返回图标为 24vp、点击区为 48×48vp。“合规说明”和“使用提醒”在合规说明页展示，开源声明口径与仓库 `THIRD_PARTY_NOTICES.md` 和隐私政策一致。

技术与支持页实现参考本轮在线读取的 [ArkTS 语法约束](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[ArkUI 开发规范](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-develop-skill/SKILL.md)与[原生动画规则](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/arkui-performance-analysis/references/animation/animateTo-patterns.md)，并核对本机 Release SDK 26.0.0.105 中的弹窗转场接口（API 19 起）。2026-11-10 定向 ArkTS 检查无错误，Release SDK 调试 HAP 构建成功并安装到 Mate 80；已查看名单页面的真机静态显示，尚未完成长感谢信滚动、深色、大屏及连续动画验收。
- “简听交流群”下方显示微信公众号卡片，说明为“关注「简听好运来」获取最新更新计划”；点击“复制名称”将“简听好运来”写入剪贴板，并提示结果。使用教程支持离线查看：首页以“从第一本书开始”入门主卡、六个主题卡片和常见问题入口组织内容；主题为书源与找书、阅读与朗读、听书与播放、书架与记录、本地与下载、备份与设置。卡片默认两列，实际容器宽度达到 600vp 后三列，统一 24vp 圆角和 12vp 卡片间距。点击进入 `guideDetail`，按编号、操作标题和说明分步展示，保留快速上手、书源、首页搜索、书架、记录、有声书、电子书、漫画、本地导入、离线下载、备份、迷你播放栏、系统播控、设置及常见问题全部 15 组教程。详情使用稳定 ID 的 `LazyForEach`，返回保留首页位置；页面跟随应用主题，正文限制最大宽度并避让动态安全区，文案统一使用资源字符串。
- 设置页进入即展示布局，本地偏好就绪后开放外观、启动与播放操作；搜索并发的会员核验独立加载，不阻塞整页。读取失败显示重试，离页和重试后的旧请求不得回写页面状态。
- 教程入口的右箭头统一为 24vp，不添加底座；保留 48×48vp 的布局区域，整张卡片均可点击。页面使用应用设置页的分层背景，卡片使用主题表面色，避免浅色模式下卡片与背景混在一起。
- “我的”中书源管理、成就馆、本地导入、使用教程、日志管理、设置、关于统一使用 `ProfileMenuDestination` 整页侧滑：按所在屏幕物理对角线分为小于 8.5 英寸 320ms、8.5 至 12 英寸 380ms、大于 12 英寸 450ms，为实际可见动效的 200/250/300ms 下限留出缓入缓出及采样余量，进入与返回时长一致。关于内的使用教程、隐私政策、开源声明及书源账号、子源、网页登录、编辑、调试、发现/登录面板路由复用同一规则；书源编辑页仍保留未保存修改的返回确认。用物理 DPI 计算英寸数，分屏、窗口缩放和字体大小不改变档位；屏幕信息异常时回退 450ms。
- 菜单转场使用 `EaseInOut` 曲线并保持页面不透明，左上角返回、系统返回和导入完成后的返回共用路由转场。回归检查各菜单的进入、返回和连续操作无残留位移；质检以录屏中的实际可见时长为准，系统动画回调耗时不能替代画面变化时长。
- 底部迷你播放器与浮动 Tab 栏共同避让内容和系统手势区。小圆封面保持静止，占圆形容器的 92%，外圈用 1.5vp 细环展示当前集进度；完整播放页封面同样不旋转。
- 浮动底栏的渐变遮罩随深浅模式切换，深色模式与页面底色保持统一，顶部保留少量主题色光感。
- 记录列表通过首尾滚动偏移避让标题和底栏，内容可连续滑入悬浮底栏后方，不在底栏上方硬裁切；滚动到底时最后一条完整露出。
- 普通窗口、小窗和窗口切换后的安全间距由 `WindowUtils` 更新。
- 首页、书架、记录和搜索的滚动内容使用原生弹簧边缘效果；空态、单项或内容不足一屏时同样允许拖动后回弹。书架网格/列表及全部/有声书/电子书筛选均遵循此行为，首页横向分类和书单也保留左右边界反馈。

- 书源批量校验最多 6 个并发，完成一个即补入后续任务，补位先于每批结果落库。发现/阅读校验按分类取得候选后立即验证详情、目录和公开章节内容，首本通过即结束；失败继续后续候选，最多检查 8 个分类、4 本不重复书籍，取消后不再请求后续候选。回归覆盖提前结束、失败换书、去重、采样上限、取消、并发上限及保存失败；实际耗时仍取决于书源响应。

## 华为账号

- “账号与备份”顶部华为账号横框整行可点击，包含头像、文字、留白及右侧图标；未登录时发起登录，已登录时更新头像昵称。登录、恢复或其他互斥操作期间整行禁用，防止重复请求。

- “账号与备份”页的“本地备份”“WebDAV 备份”和“华为云空间”卡片默认折叠，只展示标题及方向箭头；点击标题行可独立展开或收起说明、操作与状态信息，重新进入页面恢复默认折叠。滚动内容始终从标题栏下方靠顶排列，内容不足一屏时不垂直居中。
- WebDAV 支持保存/清除本机配置、测试文件夹连接、手动备份和恢复，无需华为账号。填写已有文件夹地址和应用专用密码；备份沿用本地 JSON 格式，发布为 `listenbook-backup.json`。上传前确认替换上一份备份，临时文件完整上传后以 MOVE 发布；失败或取消尽力清理临时文件。恢复先校验快照、确认内容，再保存本机安全快照。账号密码仅保存在独立加密数据库，不进入备份。连接测试验证目录可访问，不代表上传/移动权限已验证。
- 首页、搜索和播放器封面共用 `CoverLoader` 下载队列与本地原图缓存，展示不再另发网络请求。总并发上限 4，后台预取最多占 1 路、每批预取前 4 张；可见项优先，离屏释放订阅并撤下无人使用的排队任务。网络失败最多尝试 2 次，之后短期冷却；已开始的共享请求可完成缓存，但无人使用时不再重试。源绑定图片保留书源、会话、请求头及解密链路。

- 登录后，“我的”昵称后展示当前佩戴的一枚 20vp 勋章（间隔 6vp，长昵称省略时保留勋章），支持不佩戴。“我的”菜单新增独立“成就馆”入口；“账号与备份”不再展示勋章，保留本地/云备份及必要的账号操作。“成就馆”内容区上下滚动至首尾、左右拖动至边界时均使用原生弹簧回弹；登录提示、加载失败及内容不足一屏时也可触发，标题栏保持固定，保留系统侧滑返回。“成就馆”的勋章列表使用三列网格，隐藏国庆纪念勋章，仅展示 1/10/50/100/300/500/1000/2000/5000 小时听书勋章；勋章下方不再单列小时数，已获得时显示实际获得日期，历史补发且无确切日期时显示“历史累计解锁”；未解锁图片灰化并标记未解锁，点击查看门槛与剩余时长，已获得勋章点击查看获得信息并佩戴/取消佩戴，佩戴项有主题色边框。顶部显示获得数量及累计时长，新解锁只提示而不自动换装。历史时长自动补发并标注“历史累计解锁”，不虚构获得日期。加载失败显示重试，不按零时长覆盖。登录前隐藏勋章及列表，成就馆显示登录提示并可前往账号页，登录返回后展示勋章；勋章与本机统计同作用域，随本地/云备份保存，切换账号不会分割本地成就。图片采用用户提供的 9 枚素材，移除与画布边缘连通的白色背景，保留内部高光和文字，边缘抗锯齿，768px 透明 WebP 无损编码；深浅色主题共用纯勋章图，旧图片全部移除。国庆及旧 3000 小时成就仅保留历史备份记录，不展示、不计数、不可佩戴。“我的”采用横向个人信息卡片，未登录时保留登录说明。
- 两处账号头像共用图片自身圆角与缩放插值，底层使用独立圆形占位底图，不再通过外层容器硬裁剪；API 23 起开启图片边缘抗锯齿，API 20–22 保留圆角与插值显示。

- “我的”顶部账号行统一进入账号与备份页；本地备份仅保留在该页，未登录也可使用。可通过系统文件选择器导出 JSON 或从文件恢复；本地卡片与云卡片使用相同按钮尺寸和主题色。备份包含书源的搜索/发现规则及分页、详情/目录/正文规则、分组、开关、锁定、置顶和排序；旧快照缺少新增字段时兼容默认值。同地址书源遵循已有导入合并规则，保留本机管理状态及锁定保护。
- 本地恢复先检查 32MiB 上限及完整快照格式，展示备份时间、书架和书源数量，确认后才恢复；普通书源 JSON 提示转到书源管理导入。文件选择或恢复确认取消不覆盖业务数据，读取/写入失败不显示成功。恢复前保存本机安全快照，与云备份、资料更新、退出操作互斥。

- “我的”顶部个人信息区左侧为 56vp 圆形头像，间隔 14vp 后显示 20sp 中等字重名称及勋章，垂直居中；上下各留白 20vp，使用与其他功能卡片一致的背景、圆角及 24vp 右箭头。账号详情使用同一圆形头像组件，尺寸 48vp。点击个人信息区进入账号与备份页；请求中显示主题色加载动画并防止重复点击。
- 登录后显示系统授权返回的华为昵称和头像，头像下载到本机缓存，加载失败时显示占位。点击进入“账号与备份”，可主动更新华为头像昵称、备份、恢复和退出。旧版登录缓存仍可恢复身份，补充资料由用户主动授权。退出前确认，清除本机账号资料，保留书架、记录、书源会话与云端备份。
- 云备份使用用户自己的华为云空间。立即备份更新该账号对应的应用备份文件，等待系统同步完成及文件上传状态确认才显示成功，并立即刷新最近备份时间；同步中显示进度状态，可取消。备份范围为在线书架、阅听记录、阅读与播放进度、常规阅读设置、逐书目录顺序、朗读进度与设置、统计、通用设置和清洗后的书源定义；不包含音频/导入文件、自定义背景/配色/字体、账号资料或书源会话。异常阅听记录只在导出副本中逐条跳过，不删除本机数据。
- 恢复先同步、下载并完整校验文件，再展示备份时间、书架和书源数量。确认后覆盖在线记录及通用设置、合并书源；保留本地导入数据和锁定书源。恢复前保存本机快照；恢复途中存储失败会明确提示未全部完成。同步/恢复时禁止退出账号，写入期间禁止取消和离开页面。
- 启动、前台及云操作期间检查系统账号，换号后旧资料失效，云文件按账号区分；临时服务异常可重试。无云空间权限、网络、电量、配额、温度、超时、文件损坏等均有明确反馈。隐私政策 v3.3.0 说明资料授权、本地文件与云备份范围、华为云空间及删除方式。
- 云备份失败时分别提示数据准备、云文件读写或同步异常；有系统错误码时一并展示，方便反馈，不再把所有异常都提示为本机存储问题。云文件使用分块读写，每次创建新版本，确认本次文件上传完成后保留最新两份已同步备份，避免覆盖重命名失败；复制失败或取消时保留已有备份。恢复兼容旧固定文件名，选择当前账号最新已同步版本，不使用临时文件或未完成上传的版本。
- 华为云空间卡片增加“自动备份”开关，默认关闭；登录后所有用户均可开启并选择每天、每 3 天、每周，不再跳转订阅或因会员状态重置设置。显示最近成功备份、正在备份、等待重试或具体错误，不主动弹成功提示。说明按距上次成功/内容检查的间隔在应用使用期间执行，关闭应用不保证定时；退后台中断后下次补做。无变化不重复上传，失败退避重试并保留旧版本。新设备遇到已有云备份先暂停，提示恢复或点击立即备份并二次确认使用本机数据。开关按账号和设备保存，退出/换号停止原账号任务；手动操作优先并等待自动任务释放，返回账号页上一层不取消自动上传。
- 自动备份回归：会员可开启、非会员引导开通、手动备份免费、默认关闭、1/3/7 天持久化、无变化跳过、手动成功后计时更新、后台取消/前台补做、失败退避、换号隔离、首次已有云备份零上传、恢复/本机确认后解除保护及调度存储失败提示。
- 账号回归：未登录/取消/失败重试、昵称头像、旧缓存、进入详情、更新资料、重启、系统换号、退出；云回归：完成回调、失败/超时/取消、不同账号隔离、下载后确认、损坏快照零写入和恢复错误。模拟回归不等同于华为云空间真机联调。

## 系统版本兼容

- 发布渠道由 `ReleasePolicy` 控制：AGC 邀测的会员购买按钮显示“11.1开始订阅”并禁用；正式版开放购买，仍要求权益核验、商品价格和协议同意。构建前使用 `scripts/set-release-channel.py` 明确设置渠道、版本名和内部版本号，详情见 `docs/RELEASE_NOTES.md`。

- “我的”顶部账号卡片在昵称下展示会员标识，分隔线下为权益说明和金色会员中心按钮，点击打开会员弹层；主题图标页保留独立入口，点击受限图标可打开会员弹层。会员中心展示月度、年度、终身套餐以及恢复购买、管理订阅。
- 所有用户导入、新增书源均无会员数量上限；非会员搜索并发为 3。自动备份与周期、专属图标及 1–12 自定义搜索并发要求有效会员。状态未知显示核验错误和重试，不直接引导再次购买。
- 手机调试使用 Release SDK 的 debug HAP；正式分发使用发布签名的 release APP。会员逻辑回归见 `node scripts/test-membership.cjs`；真实购买、退款和换号仍需华为 IAP 环境验证。
- 八款资源由 `scripts/extract_app_icon_variants.py` 从指定 JPEG 及替换玻璃 PNG 生成，每款包含 1024×1024 前景、背景、合成预览及分层描述；背景不透明且无预制圆角。素材是扁平图，前景/背景通过边缘采样与柔和蒙版重建，不等同于设计源文件的独立物体图层。
- 新增小狐狸、卡通猫、卡通狗使用用户提供的 1024×1024 PNG，前景、背景、合成预览及分层描述同步至 AppScope 和 entry，经过保留 RGBA 像素的无损压缩。三款主体在原有构图基础上居中等比放大约 20%，保留耳机、书本和阴影完整，桌面图标与设置页预览同步；猫狗前景透明；小狐狸前景保留整幅不透明原图，尚未拆分独立主体图层。
- 八款主体按各自构图收紧留白：普通款比初版放大约 1.24–1.62 倍，独立磨砂玻璃款小幅放大，保留书页和声波完整；桌面资源与选择页预览同步。选择卡片左右内边距为 6vp。
- 图案以书本或收音机主体的视觉重心居中，右侧淡声波和投影不等权计入：水墨在原居中位置基础上等比放大约 18%，取景框收紧至 288px，预览与桌面分层资源同步；其他需要校正的款式右移约 1.3%–3.8%，磨砂玻璃保持原位；保持原有比例，不做横向拉伸。

- 应用图标前景、背景均为 1024×1024 PNG；常规款背景铺满且完全不透明，无圆角蒙版。透明玻璃款使用全透明背景与带边缘高光的透明前景，不烘焙桌面底色；桌面是否补底由系统启动器决定，须单独实机确认。`scripts/generate_app_icon.py` 同步生成 AppScope 和 entry 两套资源；entry 构建任务在资源编译后、打包签名前保留原图，避免 SDK 自动缩成 512×512。

- 新增“夜曲·白”：纯白背景、炭黑书页与原彩色声波，沿用夜曲主体的 1.15 倍居中放大，放在原夜曲选项之后；由 `scripts/build_app_icon_wave.py` 从同一源图生成。

- 主题页新增莓果酒红、活力橙、石墨灰、明亮紫、透明玻璃五款，保留绿色声波和夜曲及其他既有选项。`scripts/build_selected_app_icons.py` 直接复用 `docs/icon-design/icon-selected-preview.html` 的 Canvas 绘制，导出前景、背景、合成预览和分层描述到 AppScope 与 entry，避免配色、光晕和透明度在接入时丢失。

- 最低支持 HarmonyOS 6.0 / API 20，目标版本为 HarmonyOS 26.0.0 / API 26，使用正式版 SDK 编译。
- API 20–22 使用固定底部 Tab 栏，迷你播放器独立显示在其上方；阅读工具栏独立覆盖正文，通过位移与透明度显示/隐藏，不改变正文视口。
- API 23 及以上保留 HDS 浮动底栏和折叠迷你栏，材质与沉浸渐变模糊另按实际能力启用；能力不足使用可见底色、常规磨砂及普通渐变模糊。API 20–22 导航使用渐变模糊。
- 材质效果提供“跟随系统 / 强 / 均衡 / 弱”，新用户及默认主题默认选择跟随系统（保存为 6）；已保存的手动档位保持不变，旧值 0 仍兼容归一为均衡，重启和备份恢复保留选择。HDS 在 API 23+ 必须查询到 IMMERSIVE 能力才启用沉浸材质；ADAPTIVE 仅代表系统策略，不能单独作为支持证明。具备能力时，跟随系统优先 ADAPTIVE，否则使用 IMMERSIVE；手动档使用 IMMERSIVE，四档等级分别映射 ADAPTIVE / EXQUISITE / GENTLE / SMOOTH。API 26+ 同时经过 `PlatformCompat.immersiveMaterial` 判断，不再将弱算力设备的跟随系统强行提升为均衡。普通 ArkUI 跟随系统使用各场景默认厚度且不强设品牌触摸光效，手动档保留厚薄策略；阅读和播放弹层仍固定厚材质。设备算力档不等于系统设置中的光感强度，手动选择不能突破设备能力。
- API 26 及以上仅在 `uiMaterial.isImmersiveMaterialSupported()` 返回支持、应用材质配置未禁用且 `getGlobalMaterialLevel()` 不是 SMOOTH 时启用 uiMaterial 沉浸光感。旧 API、不支持材质、SMOOTH 设备、禁用配置及能力查询异常统一回退系统底色与磨砂，四种用户偏好均适用。首页类型/书源、书架分组/筛选、播放音色、阅听记录筛选、搜索选项弹窗，以及字体/通用选项下拉菜单均保留降级底色，随系统深浅模式切换；Select 回退时清除旧原生菜单材质。按钮、统计胶囊、迷你播放器、朗读浮窗及书架批量栏按实际材质能力分流，小说和漫画工具栏不再用后续透明背景覆盖回退底色。正常启用光感时不叠加兼容磨砂或不透明背板；统计胶囊、圆按钮最外层离屏圆角裁剪与 `clip(true)` 保留，统计胶囊下缘仍须实机检查无阴影外溢。
- 版本回归需分别在 API 20、API 24 和 API 26 检查启动、四个主 Tab、迷你播放器、阅读工具栏、弹层及安全区；构建通过不等于旧系统真机验证通过。

2026-11-07 材质兼容修复验证：材质定向回归覆盖 API 20/23/25/26、仅有 ADAPTIVE、原生支持返回 false、SMOOTH 设备、配置禁用、查询异常和四种偏好，执行真实书架弹窗配置与公共材质修饰器；偏好回归覆盖新默认跟随系统、旧值迁移、手动档位、重启和备份恢复，均通过。Release SDK 26 增量 Debug HAP 构建通过，包内最低 API 20、目标 API 26、`apiReleaseType=Release`，字节码与当前编译输出一致；ArkTS 检查工具因 LSP 未初始化不可用，MCP 构建发生 ohpm 批处理递归栈溢出，因此使用已安装的正式版 IDE CLI 完成构建。已安装到当前连接的 VYG-AL00，查看书架分组/筛选弹窗、底栏、迷你播放器及记录统计胶囊，原生模糊保留且胶囊下缘未见阴影外溢。用户反馈的畅享 90 Pro Max（鸿蒙 7）未连接，低能力回退仅完成主机模拟验证。另有 `test-theme-definitions.cjs` 的既有会员主题门控断言失败，原始代码基线同样失败，本次未修改该逻辑。

能力语义参考官方 [uiMaterial](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-uimaterial) 与 [HDS 材质](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsmaterial)；本轮读取并采用在线 [ArkUI 知识技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md)、[ArkTS 语法技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[Hvigor 构建技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-studio-hvigor/SKILL.md) 和 [设备验证技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-studio-verify/SKILL.md)。以上设备结论来自手动 UI 操作及截图检查，不代表已执行跨机型自动验收。

## 首页

- 发现分类后续分页成功返回空列表时，保留已加载书籍，停止继续分页，底部显示“简简努力找过啦，这就是全部了～”；无下一页或整页重复时也显示该结束提示。网络请求、接口业务或字段解析失败仍显示“这次没加载好，点一下重试”，首屏为空保留原有空态或书源诊断。

- 首页与发现页的列表、网格、专辑卡片和封面轮播在封面右下角显示有效评分，统一为 0–10 分并保留一位小数；大于 10 且不超过 100 的值按百分制除以 10，显式百分号或 /100 也按百分制（例如 95 → 9.5、9/100 → 0.9），/10 保持十分制；超出量程的值不显示。详情评分使用同一转换规则；评分字号、内边距、圆角和边距随封面宽度等比例缩放，普通书卡 100vp 宽封面对应 12vp 字号，首页顶部大封面轮播的评分角标在此基础上缩小 15%。无评分直接隐藏，不用热度或排名替代评分。

- 首页包含“全网榜单”和“书源首页”两种布局。首次使用或保存的源失效时进入全网榜单；有效的既有首页源继续保留。顶部直接复用原首页“搜索框 + 右侧首页源切换”及可搜索下拉菜单。中部采用最多六张去重海报轮播：进入首页或点击“精品推荐”时从有内容的具体平台随机选择一个，整叠封面只取该平台；多个平台可用时避免连续重复。点击具体平台时轮播跟随该平台，下方榜单仍按选中的分类展示。轮播（5 秒自动切换、支持手动滑动，离屏或匹配弹层打开时暂停），配合延伸到状态栏、向榜单区域逐渐淡出的柔和封面背景；切牌时背景采用 900ms EaseInOut 双层覆盖渐变，旧层保持不透明，新图解码并提交绘制后才渐入，完全覆盖后再隐藏旧层，加载失败保留原背景，连续切换接续最新封面；背景独立铺满横屏摄像头区域，高度止于分类栏底部并渐隐为页面底色，随头部滚动移出，不延伸到下方榜单；仅导航与榜单内容应用左右安全区留白。分类栏复用原首页 ImmersiveTabComponent 与原生材质，位于 HDS 标题 bottomBuilder 前景，左侧固定“分类”，右侧横滑“精品推荐 / 起点 / 懒人听书 / 喜马拉雅 / 七猫小说 / 晋江文学”。分类总览提供各平台榜单入口；切换平台只更新内容，不主动返回顶部。导航结构与书源首页一致：外层 HDS 仅承载搜索前景并关闭滚动模糊与材质层，内层 HDS 承载轮播、分类和榜单，整个内层导航随外层 Scroll 等距移动；首屏固定占位与内层导航保持完整高度，不按帧收缩标题布局。搜索栏的 56vp 高度纳入外层滚动行程，搜索前景同步上移并在末段淡出，移出后隐藏且不接收点击；232vp 轮播随滚动移出，吸顶前最后 64vp 淡出，分类栏在状态栏下方吸顶并在右侧显示同款 42vp 搜索按钮，点击进入搜索页，回顶恢复完整搜索栏。榜单 List 及其内容容器使用 clip(false) 和透明背景，书籍滚出列表视口后仍绘制到分类栏背后，供胶囊沉浸材质采样；由内层导航对榜单进行原生滚动模糊，分类胶囊及右侧搜索按钮使用自身材质，不被外层导航再次模糊。小说及漫画榜单区块按实际容器宽度显示一至三列，每列上下两本、最多六本：小于 600vp 显示一列，600–839vp 显示两列，840vp 起显示三列；保留封面与文字尺寸，宽度分配给并排书目。左侧留 24vp，有隐藏列时右侧露出 28vp 提示横滑，全部同屏时左右各留 24vp 并关闭榜单横滑；分屏、导航分栏及窗口缩放时重新计算列数，并将横滑位置限制在有效范围。点击行仍进入版本匹配；排行编号与榜单详情页一致，左侧数字采用 26fp Medium 斜体；有声使用专辑横滑卡片。全网榜单的轮播、排行列表、专辑卡片及匹配弹层封面均等比例完整显示，宽高比不匹配时留白，不裁切图源内容。全网榜单首屏采用左侧书名、作者和简介，右侧扑克牌式封面堆叠；轮播不显示榜单、平台小字或“查找书源”提示；轮播上下留白进一步收紧，总高度为 232vp，封面尺寸保持不变，简介最多四行，骨架、导航收起范围和正文占位同步；后两张向右上错位并轻微旋转，横向拖动顶牌时下一张同步抬升，滑过阈值后顶牌先侧移，再降低层级收回队尾，全程不淡出；新顶牌上前时左侧介绍同步更新，不足阈值或取消时回弹。封面不施加矩形外层阴影，避免方形封面四角出现阴影块。HDS 标题栏中的右侧封面区域（整叠牌及周围留白，不含左侧介绍）通过完整触摸闭环识别横滑，整个轮播区域的纵向拖动联动标题收起与正文滚动，松手后支持惯性滚动；右侧区域仍只在横向拖动时切牌。整个轮播区域在触摸识别开始前排除外层 Tabs 的内置横滑，介绍和留白处横滑不会带出书架；只有右侧封面区域可切牌。点击封面不跳转，点击左侧介绍进入当前书籍的书源搜索匹配弹层。保持五秒自动切牌，手动拖动、离屏和弹层打开时暂停，单张不轮换。轮播小说封面按 3:4、有声封面按 1:1 布局；起点列表与匹配弹层同步使用 3:4，圆角贴合实际图片边缘。顶部导航继续使用 HDS 原生沉浸光感，底栏与迷你播放器沿用 MainPage；匹配及来源选择弹层使用 AppMaterial 材质和低版本磨砂回退。匹配弹层高度为 92%，标题最多两行并为右上角关闭按钮预留空间，超长标题和作者省略；提供“全部 / 有声书 / 电子书”及实时数量，分组仅筛选结果，不重复发起搜索。匹配列表仅在结果变化时刷新，拖动和惯性滚动期间保持现有顺序，停止后合并显示最新结果。搜索结束且当前分组无结果时才显示导入/管理书源。进入详情时暂存弹层，点击返回或侧滑返回首页后自动恢复关键词、分组、结果和列表位置，无需重新搜索；继续进入阅读或播放时，等实际返回首页再恢复。手动关闭后不再自动弹出。
- 全网榜单叠牌封面宽度统一为 120vp：小说高 160vp、有声高 120vp；折叠与展开保持同一尺寸，增加的横向空间留给介绍文字，加载骨架同步使用该宽度。回归时固定同一本书对比折叠/展开，封面高度倍率应不超过 1.2，并检查不同封面比例、叠牌拖动与分类吸顶。
- 2026-11-05 榜单容器适配：沿用 `AdaptiveLayout` 的 600/840vp 断点，参考已读取的[多设备屏幕与窗口尺寸技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/06-solutions/multi-device/hmos-multidevice-screen-window-size/SKILL.md)及[响应式布局指南](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/06-solutions/multi-device/hmos-multidevice-screen-window-size/references/responsive_layout.md)。两份修改文件 ArkTS 检查无错误，Release SDK 26.0.0.105 Debug HAP 构建并安装成功（最低 API 20、目标 API 26）。MatePad Pro 13 模拟器横屏 2880×1920 确认前三列共六本完整可见，布局树确认 `displayCount=3`，并验证“查看榜单”进入与返回。系统分屏未成功切换，单列/双列窗口、宽窄往返及书目匹配点击仍需设备验证；未以模拟器结果代替平板真机验收。
- 全网榜单版本匹配弹层的来源结果使用低透明度黑色叠层，基于原弹层材质轻微加深，配合低对比细边框；保留圆角、卡片间距及系统文字色，避免大面积实色泛白。
- 全网榜单仅分类 Tab、右上角首页源入口及排行数字保留主题强调色；平台名、榜单标签、轮播圆点、分类总览入口、匹配弹层操作与来源标记均使用系统中性色，加载与刷新指示也使用中性色，并适配深浅模式。
- 五个平台各提供 6 榜，共 30 榜；分类总览和平台页由同一榜单配置生成。懒人补充热搜、免费、畅销、完结周榜，喜马拉雅补充有声书热播、新品、口碑和小说 VIP 榜，七猫补充男女生新书与完结榜，晋江补充季度、半年、VIP 强推与字数榜。首页榜单区和二级榜单统一显示“榜单名·平台名”（如“月票榜·起点”），平台名字号略小，不再单独放置平台小字；首页标题分别为 23fp/16fp，二级榜单为 34fp/22fp，长标题最多两行省略。精品推荐将“热播周榜·懒人听书”置顶，其余榜单保持相对顺序；平台榜单按各自原始顺序展示；起点依次提供月票榜、完结榜（畅销完本）、阅读榜、推荐榜、新书榜、畅销榜，每榜展示官网公开首批 20 项，跨榜书籍可重复；首页每个榜单标题下及二级榜单显示各自真实获取时间，统一为“更新于 YYYY年MM月DD日 HH:mm:ss”（本机时区）；刷新失败保留旧时间，不显示虚假的本次刷新时间。缓存有效期为 6 小时，重新进入时过期才联网更新，下拉刷新立即请求，无后台定时刷新；“查看榜单”显示该入口返回的前列项目及实际数量（最多 99 项）、获取时间，进入与返回采用项目统一整页侧滑（WindowUtils.getPageTransitionDuration，按物理屏幕尺寸使用 320/380/450ms，EaseInOut）；发现首页保留在组件树中，返回保持原平台、分类总览、轮播与纵横列表位置，不回顶，转场期间阻止重复开关。全网榜单也支持下拉刷新与双击底栏回顶；刷新时海报和分类栏保持原位，主内容随下拉距离下移，在分类栏与正文之间单独留出 loading 空间；进度环跟随应用主题色，拖动显示进度、刷新后旋转，顶部不显示默认 loading；单榜加载失败不隐藏其他榜单，旧缓存会标明暂未更新。
- 点封面先显示版本匹配弹层，编辑书名可重新搜索；无可用书源时引导导入，书源管理返回后继续匹配。书名相同不代表演播版本相同，用户选择后进入原详情页。推荐封面不会替换用户选定版本的来源身份、目录或进度。
- 回归重点：无源首次进入、平台切换、完整前列列表、下拉刷新/离线缓存、双击回顶、切回原首页源、书源禁用后回退、导入返回继续匹配、快速点不同书籍及关闭弹层后迟到结果隔离。已在 Mate 80（API 26）确认顶部搜索/来源、六张轮播、分类原生光感及吸顶，既有版本已验证匹配和来源详情/目录；匹配分组、加高弹层、详情返回恢复及最新单层导航的胶囊清晰度尚未完成实机复核（设备连接中断）。

- 首页右上角来源选项顶部提供搜索框，按名称、地址或分组实时筛选，忽略英文大小写与首尾空白。清空输入恢复全部可选源，重新打开重置搜索；无匹配时显示提示。列表按源地址稳定标识并懒加载，选择搜索结果仍保存对应的原始源。

- 首页初始化仅按地址读取当前选中的来源；完整来源列表在打开切源菜单时加载，并按书源变更版本复用。首页与书架切换不读取全部书源规则；书架来源标签和更新检查只解析收藏实际引用的来源，禁用源仍可解析，删除源不移除已有收藏。

- 切回最近使用的来源时复用最多 4 个来源、5 分钟内的分类与推荐缓存；首次加载先显示已完成的分类推荐。下拉刷新重新获取数据，来源定义或登录状态变化后重新加载。回归检查快速 A→B→A 切源、慢分类不阻塞已完成内容、单分类失败及刷新。
- 首页处于“分类”总览或其他源分类 Tab 时，侧滑返回先切回“精品推荐”；处于“精品推荐”时，侧滑返回退出前台、将应用移到后台。
- 书源首页、全网榜单首页、榜单详情与搜索页的状态栏字色统一跟随深浅主题，展开、吸顶、回弹时不切换黑白字；两层导航使用相同字色，运行中切换主题同步更新。保留原有透明沉浸导航，不额外叠加状态栏背景。书架分类栏下方首行内容留白为 12vp（原 24vp），网格与列表共用。

- 最近更新的三行横滑书单右侧使用爱心收藏按钮：未收藏为空心，已收藏为主题色实心；点击切换收藏并同步书架，封面与书名仍进入详情。

- 推荐和分类使用首页顶部选择的发现源；选项列出已导入、启用且具备发现内容的小说和有声书源，选择保存在本机。源禁用、删除或关闭发现后回退全网榜单。书源管理不再提供首页源切换。
- 搜索、轮播和分类 Tab 整体随滚动上移，Tab 到状态栏下方后吸顶，随后内容列表才开始滚动并经过 Tab 的模糊层。分类 Tab 和折叠搜索按钮始终位于 HdsNavigation 标题栏的 bottomBuilder 内，使用导航区的原生沉浸光感，旧系统使用磨砂回退。顶部使用 HdsNavigation 的原生渐变模糊，轮播进入顶部时逐渐模糊，搜索与 Tab 前景文字保持清晰，不叠加手工状态栏底色遮罩。首页源的下拉菜单使用与弹层一致的沉浸光感材质，跟随外观设置的厚度与主题色；API 20–25 使用对应厚度的磨砂回退。
- 首页搜索框用于进入独立搜索页，右侧为独立的首页源下拉标签，按当前源名称自适应宽度，最长占顶栏可用宽度的 45%，书源名称使用 13fp 字号和中等字重、随主题色变化，不显示三角箭头。点击标签弹出已启用的小说/有声发现源选项，弹层随筛选结果及单双列内容收缩，只限制最大高度为视口的 68%，超出时列表滚动，加载和空态不撑出大块留白；选择与保存由 HomeSourceService 处理；来源菜单也提供“全网榜单”，与搜索框紧凑排列；仅当前选择项使用系统三级背景高亮，外框圆角遵循原生菜单，每次打开清空筛选并定位到已选源（优先居中），选择保存为下次首页默认入口；无可用源时显示全网榜单首页。默认选中精品推荐，源分类读取所选源的发现定义，保留源返回顺序，不注入固定分类。切换源时清除旧推荐和分类，旧请求不能覆盖新源内容。通用源预览前四个分类，未提供发现内容时显示提示。右箭头位于书源切换弹框内每个书源选项的右侧，图标为 24vp、点击区为 48×48vp，独立进入对应源的原发现设置，不更改首页源选择；点击该行源名称仍切换首页源。首页顶栏只保留源名称标签，全网榜单选项不显示箭头。弹框最大高度为当前窗口的 68%，全网榜单右侧使用单个沉浸光感图标按钮（不显示中文）切换一列/两列并记住选择，不另设切换栏；一列目标宽 248vp、两列目标宽 640vp，均限制在容器安全区和两侧边距内，源名称单行显示，超出宽度使用省略号，书源行高为 48vp，列表懒加载；未选中的源选项背景透明，当前选项使用系统三级背景高亮，选项间隔 4vp。
- “精品推荐”页按“搜索栏 → 封面轮播 → 分类 Tab → 推荐内容”的顺序排列，使用当前源推荐板块的最多 6 本小说或有声书籍，按来源与书籍地址去重。顶部与全网榜单复用 BookPosterCarousel：左侧书名、作者与最多四行简介，右侧三层封面叠放并轻微旋转，横竖屏均为 232vp 总高、最大 120vp 封面宽度；书源封面采用图片原始宽高比，圆角使用与详情相同的 8vp。背景透明，不再额外展示底部书名，封面保留书名无障碍说明；轮播底部不叠加组件与父容器的 padding，分类栏紧跟封面阴影区域，搜索位于视口 HdsNavigation 的 stackBuilder 前景，轮播与分类栏位于滚动内容中 HdsNavigation 的 bottomBuilder；两者绑定同一外层 Scroll，搜索前景按同一位移上移，移出后由原生标题栏收起区域，轮播与 Tab 随父容器等距上移，滚动不压缩标题区域高度或裁剪轮播；内层 List 上滑采用 PARENT_FIRST，Tab 完全吸顶后才开始滚动，下滑采用 SELF_FIRST，先回列表顶部再展开整个头部；固定视口的 HdsNavigation 提供顶部渐变模糊，Tab 所在的 HdsNavigation 响应吸顶后的列表滚动，保留 Tab 材质与清晰文字；标题栏使用固定构建函数，API 26 起保留自定义区域节点；加载骨架使用相同顺序且不再显示书名占位。点击封面进入现有书籍详情。每 5 秒自动翻牌，支持在右侧封面区域左右拖动；触摸、翻牌、离屏或进入详情时暂停，仅 1 本时静态展示。点击左侧介绍或当前正面封面直接进入来源详情；翻牌和竖向滚动后抑制误点击，横向手势不带动主 Tab。切换源清空旧轮播，刷新重置到第一本，无可用封面时不显示轮播。
- 书源首页使用当前推荐轮播封面作为整页虚化背景，固定铺满视口并延伸到状态栏、底部和横屏摄像头区域；前景内容继续避让安全区。背景复用双层低分辨率解码和 450ms 淡化，自动/手动轮播同步更新，横竖屏保留当前封面，分类切换沿用当前背景；刷新回首张、切源和空轮播时同步更新或回到页面底色。背景不拦截触摸、不参与无障碍焦点，新封面加载失败保留已显示背景。
- 首页内容层统一使用 `WindowUtils` 的左右动态安全距离，搜索框、首页源入口、轮播、分类 Tab、骨架和书单共用安全宽度；背景仍铺满摄像头与系统区域。监听安全区变化，左右横屏及恢复竖屏时同步更新两侧边距、顶部占位和底部导航留白，页面销毁时解除监听；轮播方向按原始视口宽高判断，避免安全边距影响方向判定。
- 书源首页横竖屏统一使用全网榜单同款介绍与叠放封面，窗口增加的宽度分配给左侧介绍；仅图片和文本占用轮播区域，不额外叠加卡片底色。窗口变化保留当前书籍，加载骨架与导航占位共用 232vp 高度。横竖屏切换须检查分类吸顶、双击回顶、下拉刷新及底部导航避让。
- 书源首页和全网榜单共用翻牌绘制与触摸识别：横拖顶牌沿侧边收回队尾，后两张连续前移；自动翻牌间隔 5 秒，触摸、离屏或详情打开时暂停。仅书源轮播允许点击当前封面进入详情，全网榜单保留点击介绍进行版本匹配。
- 封面和点击入口以来源地址与书籍地址组合标识，首页与详情共用 8vp 圆角；共享轮播保留当前牌序，横竖屏切换不重建两个独立分支。回归覆盖非首张书籍、连续旋转、单张和两张轮播，以及进入详情后返回当前书籍。
- 自动翻牌暂停/恢复不重置牌序；仅换源或刷新推荐数据后回到首张。距离分类栏吸顶的最后 64vp，封面与介绍一起渐隐，完全吸顶后不可在透明状态栏区域残留封面底边。
- 首次加载且无板块数据时显示封面轮播与推荐板块的呼吸骨架，不叠加居中加载圈或“加载推荐中”。骨架与真实轮播共用介绍与叠放封面的尺寸和总高度，均无额外顶边距；推荐骨架共用 28vp 标题行、84vp 书籍行、首板块右侧露出量和 128vp 横向书卡宽度，加载完成时分类栏和首板块不跳位。
- 搜索入口完全展开且列表在顶部时可下拉刷新，内容位移阈值为 96vp，固定下拉跟随比例为 0.5，对应手指移动约 192vp；达到阈值后松手刷新，请求入口再次校验实际位移。推荐和分类刷新保留旧内容，结束时清除刷新状态。
- Refresh 包围父子滚动容器，指示器仅随实际下拉在分类 Tab 下方、推荐内容上方出现，使用 `AppColor.Brand`；拖动时显示随距离填充的进度环，真正刷新后才显示旋转 loading，短拉只回弹。未下拉时不创建指示器，指示器限制在下拉留白内。头部抵消 Refresh 的位移，只有内容下移留出空间，回弹结束后移除指示器。
- 每个推荐板块有“更多”入口。第一个板块每组纵向显示 3 条、横向滑动，右侧露出下一组；后续板块按来源布局显示。书源首页的轮播、推荐行、列表、横向书卡及分类书卡按返回图片的原始宽高比显示，使用 Contain，不拉伸或裁切；只有图片尺寸未知时采用 3:4 加载占位。首板块封面在 72×72vp 内等比例缩放，行高为 84vp；列表封面在 72×96vp 内等比例缩放；顶部轮播封面在 120×160vp 内等比例缩放。圆角统一为详情使用的 8vp，转场节点贴合真实图片尺寸。加载、失败及重试状态共用填满封面框的占位图；加载完成后更新为原图比例，并按图片地址缓存，返回首页、切换分类及重建卡片复用已知比例。
- 精品推荐现有板块下方新增“为你推荐更多精品好书”，从当前导入书源、当前频道的发现结果补充最多 50 本，排除上方预览书籍并去重；分类失败保留已有内容，不足时展示实际数量。列表按行懒加载，每本左侧为原比例封面，右侧依次为书名、作者、简介；书名最多两行，简介最多三行，缺失信息显示占位文案。可用内容宽度小于 600vp 为单列，达到 600vp 为双列；横竖屏及分屏变化重新分列，底部避让浮动导航。复用现有详情封面转场、下拉刷新及双击回顶。
- 最近更新按三条一页懒加载，横向推荐书卡使用横向 List 按可见范围懒加载，两者只预加载相邻一项；推荐列表只预加载相邻一个板块。分页和横向数据源在推荐数据返回时更新，切换入口复用，避免返回精品推荐时一次性创建整组封面。完全收起后展开时，先提交推荐节点、封面显隐和滚动占位的准备帧，布局完成后再启动原生弹簧；快速反向切换立即接续当前动画，并使旧准备回调失效。
- 推荐列表与分类列表使用独立滚动控制器，切换入口仅隐藏推荐列表，保留已创建的可见书卡与封面；隐藏列表不绘制、不接收点击。回到推荐和双击首页仍复位当前列表与头部，横向书单保留当前浏览位置，刷新通过原数据源更新内容。
- 首页分类书单不限制总本数或页数，进入时仅加载并立即展示第一页，滑到底部或点击底部入口再按源的下一页信息逐页追加，直到无下一页或无新增书籍；跨页按书籍地址去重，追加失败保留已有书籍并支持点击重试，刷新从第一页重新加载，切换分类或源后旧请求不能回写。分类结果使用 ListItem 内三列书卡，按行 LazyForEach 懒加载，末行不足三本保留等宽占位；API 20 起使用同一布局，避免将仅在 API 26 支持的 LazyVGridLayout/List 组合用于 6.0。分类切换、回到推荐与双击回顶同步复位父子滚动容器，下拉刷新仅在列表和轮播均回顶后触发。
- “分类”Tab 位于第一位并固定在左侧；右侧依次为“精品推荐”和源分类，共同横向滚动，默认选中“精品推荐”。点击分类打开可搜索的沉浸材质面板，显示分类总数和关闭按钮。优先保留书源分组；明确的“全部·大类”条目作为大类标题及组内“全部”入口，后续二级分类归入对应大类，不猜测 URL 层级。分类标签按源顺序自动换行，分组列表懒加载；搜索大类显示整组，搜索子类保留所属组标题。点击标签关闭面板并切换对应原始分类 URL，让顶部对应 Tab 可见；关闭面板保留原书单与滚动位置。切源同步更新分类，没有分类或没有搜索匹配时显示相应空态，影视过滤继续生效。
- 首页横向 Tab 的文字和选中下划线平滑变化，点击有轻微按压反馈，对应标签平滑滚动至可见位置。切换精品推荐与其他入口时，完整尺寸的轮播、分类栏和书单随内层 HdsNavigation 整体位移，使用原生 animateTo 临界阻尼弹簧（response 0.32、dampingFraction 1）同步位移与轮播淡入淡出，不挤压封面。HDS bottomBuilder 配置高度和内部布局固定，动画结束后一次性回收外层滚动占位；连续点击继承原生当前位置和速度，并用序号阻止旧完成回调改写布局。过渡期间暂停父子滚动、下拉刷新与自动轮播，分类标签仍可连续点击；收起后的轮播隐藏并停止接收点击，重新展开保留当前页。整体位移期间不叠加书单与分类卡片入场；其他分类切换保留 360ms 内容淡入、轻微上移及后续可见卡片 420ms 入场，首屏前 12 项错开 45ms、后续仅错开左右列。刷新保留当前内容和位置。
- 搜索框及首页源标签在自身 56vp 滚动行程末段渐隐，完全移出后隐藏节点并停止接收点击；有无轮播均适用，不在透明状态栏内停留搜索框底边。吸顶后仅保留分类栏和其右侧的折叠搜索按钮。无轮播页面及分类栏吸顶后，关闭外层导航的滚动模糊与背景材质，只由分类栏所在的内层导航模糊书单背景，标签文字、选中下划线和搜索按钮保持清晰。

- 发现分类／“更多”书单使用单层 `HdsNavDestination`，与搜索页共用 `HdsCompat` 的透明初态和沉浸渐变模糊，低版本沿用普通渐变磨砂；返回和视图切换按钮使用 `ImmersiveCircleButton` 的原生材质。列表的首尾留白使用 `contentStartOffset/contentEndOffset`，瀑布流使用 `WaterFlowSections` 的分组边距与独立全宽尾项，均随内容滚动；禁止把顶部导航和底部安全区放进滚动容器固定的纵向 padding。内容可绘制到标题栏和底部手势区域，最后一项仍可滚到安全区上方；窗口安全区变化同步更新留白，网格列数继续跟随实际容器宽度。验收覆盖首屏、滚动中顶栏透出、底部无固定白带、两种视图切换与分页追加。依据在线 [lang-syntax](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[hmos-arkui-knowledge-retriever](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md) 的 [List](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/03-layout/grid-list/ts-container-list.md) 与 [WaterFlow](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/03-layout/grid-list/ts-container-waterflow.md) 参考，并按 [deveco-studio-verify](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-studio-verify/SKILL.md) 检查实际显示；指南与 API 定义本身不代表设备验证已通过。

## 搜索

- 返回按钮与搜索框同一行，不额外显示页面标题；返回、输入和结果视图控制使用稳定尺寸。
- 搜索框右侧同一行提供仅图标的圆形筛选按钮，保留“筛选”无障碍标签；点击收起键盘并弹出沉浸式悬浮菜单，包含“指定源搜索”“精准搜索”“搜索作者”“仅搜索电子书”“仅搜索有声书”“仅搜索漫画”，文字左对齐、选中勾位于右侧。筛选项可独立开关，点击选项后菜单保持展开，点击菜单外关闭；菜单复用 AppMaterial.Sheet，旧系统使用磨砂回退。类型只选一项时，在请求前筛选对应书源并校验结果类型（电子书为 0/3，有声书为 1），进度总数仅统计参与源；支持“仅搜索漫画”（漫画源类型为 2），三种类型可多选，按所选类型的并集过滤；全部不选时不限类型。启用任一选项时按钮使用主题色，选项保存到本机，已有搜索时修改选项重新搜索。搜索框下方不再保留选项行或其占位。
- 有搜索结果时，网格和列表上滑均按首页方式收起搜索栏，结果筛选栏保留；回到顶部恢复搜索栏，清空输入或重新搜索时复位。
- 未搜索或清空输入时显示搜索历史与推荐书籍；没有来源或未取到推荐时显示空态。
- 推荐区展示启用导入来源的真实书籍，按来源＋书籍地址去重、稳定追加最多 5 本。优先复用五分钟内的推荐及首页预览缓存；不足时只查最多 6 个候选来源地址，再逐个按需读取规则和执行低优先级搜索，凑够即停止。搜索页不再加载整套首页发现或后续推荐分页。书源定义、启停、删除和登录状态改变时缓存失效；单源失败继续下一候选，输入、提交或离页取消后续调度与迟到回写。推荐卡片使用独立 ListItem＋LazyForEach，只创建可见项及少量缓存，封面随可见项加载。
- 搜索历史是可换行的磨砂标签，最多保存 20 条；重复关键词移到最前。点击整个标签重新搜索，不显示单条删除图标；“清空”删除全部历史。标签直接使用带沉浸材质的 Text，保留 34vp 高度、圆角与整项点击反馈，并放在导航 bottomBuilder 中悬浮显示，保持原生沉浸材质生效；标签按文字实际宽度自然换行，不按列对齐。上滑时“搜索历史”和“清空”随滚动收起，标签吸顶到搜索框下方，回到顶部时恢复；推荐列表保留完整展开高度的首项占位，避免折叠时跳动和遮挡。
- 提交后按保存的并发数搜索导入源，默认 3，完成一个立即补下一个并逐步展示结果；按 `sourceUrl + bookUrl` 去重。换关键词、清空或离页时，取消旧搜索及补封面的网络请求和后续调度，丢弃过期回调；各源自动翻页仍共用搜索并发上限并在队尾公平排队。
- 搜索缺失封面的详情补齐使用页面共享的三并发队列，跨源、跨页和连续搜索都不叠加在途上限；单本失败不阻断后续任务。结果与封面更新统一合并提交，同名分组增量维护；列表按稳定书籍身份通知新增或变化，切换类型时正常重载。大量导入源的读取分段让出事件循环，避免连续解码整份规则库。回归需覆盖搜索期间滑动和输入、连续换词、切换类型、同名角标与补封面、退出后停止请求；代码回归与构建不能替代设备帧率验证。实现参考在线 [ArkUI 性能分析](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/arkui-performance-analysis/SKILL.md)及其[高频重复工作指导](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/arkui-performance-analysis/references/component/frequent-work.md)。
- 搜索列表键由书籍身份和单项内容版本组成，追加其他书籍不改变既有键，封面替换仅递增对应书籍版本，保证 `onDataChange` 真正更新该书卡；规则见官方 [LazyForEach 更新约束](https://raw.gitcode.com/openharmony/docs/raw/master/zh-cn/application-dev/ui/rendering-control/arkts-rendering-control-lazyforeach.md)。补封面待办最多 96 项，超出时保留占位，正常进入详情仍可加载；提交搜索同时取消旧推荐中的搜索请求。
- 搜索期间，结果工具栏与首屏加载态的 loading 右侧显示已完成书源数/本轮参与搜索的书源总数（如 `4/74`）；成功、无结果或失败均计入完成数。重新搜索或清空输入时归零，旧请求不更新新一轮进度，搜索结束后随 loading 隐藏。
- 结果提供“全部 / 有声书 / 电子书”计数与网格/列表切换。单源失败不阻断其他来源。
- 搜索页不启用下拉刷新，结果末项可完整滚动到浮动底栏和系统手势区上方。
- 搜索页进入和返回均使用 HDS 原生侧滑转场，保持实时绘制，不叠加 customTransition、整页 renderGroup 离屏缓存或透明度动画。进入时不自动聚焦或弹出软键盘，用户点击输入框后再弹出；退场开始前退出输入状态并停止异步结果回写。历史标签的首次换行布局不做隐式材质动画，避免转场中出现黑色闪烁。
- 本地搜索历史在页面创建时读取，输入框和原生侧滑转场先显示；onShown 后 500ms 再构建历史材质标签，保留完整历史区域占位，并缓存同字号、缩放下的文字宽度。推荐在下一阶段按需执行，避免历史布局与推荐任务集中在同一帧。隐藏或返回时取消进场和推荐任务，快速重进只调度一次。搜索输入框使用固定构建函数，API 26 起保留输入框节点，旧系统沿用 CustomBuilder；历史和结果工具栏随结构或高度变化正常重建，避免初始空态的透明代理节点。回归需核对实际截图、输入/历史点击和推荐加载期间的滑动、返回。
- 输入、历史标签和结果控件使用沉浸材质，导航区使用 HdsNavDestination，与首页一致采用 IMMERSIVE_GRADIENT_BLUR 和透明初态，由当前推荐/结果滚动容器驱动整体渐变模糊；推荐、网格与列表使用可滚动的首尾留白，前景控件保持清晰。

## 书架与阅听记录

- 网络封面完整加载前保持静态占位，失败最多后台重试一次，连续失败地址在 5 分钟内复用占位；滑动重建不会反复闪动。预下载复用在途任务，图片报错不取消下载、不放宽统一尝试上限。空封面继续直接显示本地占位。

- 书架状态筛选、分组和阅听记录筛选使用按钮下方的原生菜单，开合动效与设置页选项统一。选项使用系统主文字色和三级背景选中态，复用 AppMaterial.Sheet，旧系统回退磨砂。选择后收起并立即筛选、保存，点击外部或切走页面关闭菜单。

- 书架右上角四个按钮复用 ImmersiveCircleButton：HDS 原生浮动材质、主题色触点光晕，API 20–22 回退磨砂；保留搜索展开转场、筛选、检查更新与视图切换行为。
- 长按菜单第二项固定为“查看详情”，网格／列表一致；菜单退场后直接进入所选书籍详情，即使该书正在播放也不跳到播放器。

- 书架顶部按“搜索 / 筛选 / 分组（已有自定义分组时） / 检查更新 / 视图切换”排列。分组使用与筛选一致的浮层选项，提供全部分组与自定义分组，选中高亮、选择后关闭；较多选项在最高 320vp 的浮层内滚动，取消整行 Select 及其占位。筛选沿用与搜索页一致的漏斗图标，提供“全部 / 连载中 / 已完结”选项。搜索默认收起，放大镜使用 24fp，顶部图标保持原有 Regular 粗细；点击后通过原生 geometryTransition 与 animateTo，在 320ms 内从按钮生长为整行输入框，位置、尺寸和圆角由共享元素自动衔接，再点反向缩回并关闭键盘。收起态按钮与输入框独占同一转场标识，展开态顶部保留独立收起入口；标题栏自定义按钮仍由 HDS 沉浸导航承载。导航及书籍占位同步动画，转场中禁止重复点击，保留关键词与过滤结果；展开或有关键词时搜索按钮高亮。搜索行与分类栏间隔 6vp，导航及列表占位随展开／收起在 98vp／48vp 间同步切换，书籍顶部额外留白为 24vp；分类栏采用半透明沉浸胶囊与浅色外描边，选中项显示独立内圈、浅色底和主题色文字，取消下划线。选择后立即更新网格与列表，并在本机保存上次选择。筛选与有声书/电子书分类、书名/作者/演播者搜索取交集；无结果显示空状态。与详情一致，状态缺失默认归入已完结。更换任一筛选或搜索词清空管理选择，全选只作用于当前可见结果。

- 书架长按菜单支持“置顶／取消置顶”，网格和列表同步显示置顶标记；新置顶排在最前，普通书保留收藏顺序，取消置顶恢复原顺序。置顶按收藏 ID 持久保存，移出书架清理标记，在线置顶随备份迁移，恢复保留本地导入书置顶。

- 书架表格视图保持三列书卡，与列表视图使用相同的原生滚动边界及首尾安全留白；空书架、单排或内容不足一屏时，上滑松手后回到安全起点，不留下额外上滑位移。回归覆盖全部/有声书/电子书筛选、视图切换和双击书架回顶。
- 书架两种视图均使用 ListItemGroup 的全宽组头预留状态栏、标题、筛选栏和 18vp 间距，顶部安全区随窗口变化更新；不依赖 contentStartOffset 避让沉浸导航，首排封面不得与筛选胶囊重叠。
- 书架顶部筛选保留官方 CapsuleSegmentButtonV2 的四项等宽切换：13fp 文字、40vp 行高、20vp 外圆角和 3vp 内边距，选中项为 34vp 高、17vp 圆角；整条胶囊采用半透明沉浸材质和浅色细描边，选中项增加独立内圈、浅色背景和主题色 Medium 文字，取消底部短横线及选中阴影。描边装饰层不参与触摸和无障碍焦点，深浅色资源分别适配，旧系统回退超薄磨砂；分类栏仍放入 HdsNavigation 的 bottomBuilder，首排书籍额外留出 18vp 间距。支持内容类型筛选及网格/列表视图，长按整张书卡打开锚定书卡的原生沉浸悬浮菜单，封面及角标显示子树不参与触摸命中，无封面占位禁用原生拖拽，由整张书卡统一响应长按；提供“仅删除书架”和“删除书架及本地”，前者保留导入文件，后者清理本地副本、下载及该书已保存的正文/音频预缓存。
- 书架网格与列表封面的“文 / 声 / 漫”类型角标统一位于右上角；网格置顶标记与批量勾选标记位于左上角，避免相互遮挡。
- 书架电子书直接进入正文并恢复位置；音频书按对应入口继续收听或查看详情。
- 书架网格和列表末尾不显示添加书籍卡片；完全没有收藏时显示“去首页添加喜欢的书籍吧”，已有收藏但分类、筛选或搜索无结果时保留筛选空状态提示。
- 书架仅由长按书卡菜单的“管理”进入多选并选中当前书，顶部不增加管理文字或图标；返回键或长按菜单的“完成”退出管理。网格封面右上角和列表行尾显示选择标记，点击整张书卡切换选择，标题实时显示已选数量。切换网格／列表保留选择，切换内容分类清空选择；全选只作用于当前分类，未选中时删除按钮不可用。
- 管理操作栏使用 ShelfBatchActions，仿照 ReaderSpeechFloating 的“听”按钮，以 HdsTabs 原生浮动栏承载沉浸光感，叠加透明交互按钮并作离屏圆角裁切，不能只给普通 Row 附加 systemMaterial。全选／删除为图标加文字，删除使用警示色，旧系统回退磨砂。通过独立全屏 Stack 的底部对齐固定在悬浮 Tab／迷你播放器上方，列表为操作栏另留 72vp；禁止将栏定位到标题／状态栏区域。删除使用原生底部确认弹层，默认仅移出书架、保留阅听记录及进度，可勾选清理导入副本和下载音频；取消保留选择，返回键先关闭确认、再退出管理。文件清理串行执行，失败项保留选中供重试；批量收藏落盘及通知仅执行一次。
- 电子书阅读进度保存后同步刷新书架网格与列表中的章节进度；从正文返回书架无需切换 Tab 或手动刷新。删除阅读进度后同步恢复未读展示。
- “阅听记录”主页展示收听统计摘要及已收藏书的阅读、收听记录，“未收藏记录”使用独立页面查看未收藏书记录。阅读按最近阅读时间合并排序，显示已读比例和章节，继续按钮进入阅读器恢复章节及字位置；删除同时移除对应阅读进度。累计时长仍只统计实际收听，不将阅读字数换算成收听时间。列表采用稳定书籍 key 的 LazyForEach，并保留下拉刷新、双击 Tab 回顶和长按/编辑选择。
- 在线电子书进入阅读时，无论是否收藏均持久保存书籍信息和目录；移出书架保留历史所需信息，200 本临时缓存淘汰不影响收藏或阅读/播放历史。旧版缺失书籍信息时，记录页先显示记录，再从内存、旧索引和正文缓存身份尝试后台恢复；单本失败不阻塞列表，不按章节名猜测书籍。
- 统计卡片下半区（连续收听、本月收听）使用深浅色资源配色：浅色保留半透明白底，深色使用低亮度暖深灰，与累计时长卡片保持柔和层次。
- 顶部累计时长和折合本数使用持久化累计值，不按天重置；每日明细的保留窗口不截断累计时长。页面先读取服务缓存，再独立加载书籍明细；初始化期间显示占位值，读取失败显示重试提示，不能把未读到数据显示成累计为零。统计写入串行执行，在 Preferences 与独立文件快照间按修订号恢复，退后台和退出前等待落盘。
- 本月收听按自然月的每日明细计算，无日期的旧累计不按最后更新时间归入本月；重新播放不能导致本月历史整笔增减。跨零点播放按实际区间分日，暂停保留不足 15 秒的尾段，缓冲等待不计时；系统校时、倍速和拖动不改变实际收听时长。统计事件立即更新顶部，不被明细加载阻塞；重新显示页面及跨日刷新月份和连续天数。
- 默认显示顶部“编辑”，点击或长按记录进入多选，提供全选、删除、取消；删除前确认。长按顶部“编辑”500ms 切换为锁定图标，关闭已展开的滑删操作并清空选择；锁定期间禁止长按多选、全选和左滑删除，点按详情、继续听书/看书保持可用。点击锁定图标只解锁并恢复编辑按钮，不直接进入多选。锁定状态通过 PreferenceService 的 `record_edit_locked` 保存在本机，首次默认为 false，重启恢复，未收藏记录页共用同一偏好；空列表仍可锁定和解锁。保存失败恢复原状态并提示。
  2026-11-06：使用在线 [lang-syntax](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[ArkUI 手势规则](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/18-arkts-rules/arkts-interaction-rules.md) 与 [设备验证指南](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-studio-verify/SKILL.md)；保持 ArkUI V2，以优先长按手势避免松手触发点击。两处 ETS 静态检查无错误，20 项统计与记录定向回归通过；Release SDK 26.0.0.105 的 Debug HAP 构建通过，包内 Release 渠道、最低 API 20／目标 API 26，已安装并启动模拟器。模拟器存在并发交互，未完成长按锁定、滑删拦截、继续阅听及重启记忆的设备验收，不能视为实机验证。
- 普通模式点击记录主体进入详情，点击右侧播放按钮从对应记录封面一镜到底打开播放器，并从上次位置继续；封面无法测量或截图时正常跳转。文本/漫画按钮仍进入阅读页。单条记录不重复显示三点菜单。
- 迷你播放器展开、Tab 栏折叠为圆形入口时，按 HDS 回调的实际 Tab 状态仅渲染图标；内容使用固有尺寸，由 HDS 内部容器双向居中，不设置百分比高度或把外层 56vp 高度套给内部内容区，也不保留隐藏文字节点或图文间距。设置或主题刷新、页面返回后位置保持居中，Tab 栏展开后恢复图标和文字，外层继续使用 HdsTabs 的沉浸材质与折叠交互。

## 详情与转场

- 分类、评分、完结状态、更新时间、体量信息分别以小胶囊展示；每项有数据才显示，全部为空时收起整行。多个分类分别展示并去重，未知状态不默认显示已完结或连载中。

- 播放页与展开的迷你播放器共用独立主题色旋转环；加载时移除播放/暂停符号子树，避免隐藏符号的替换效果与加载动画叠加。旋转使用原生属性动画，无 JS 逐帧定时器。切书进入地址解析前即同步桌面卡片，书名、章节和状态不等待封面网络下载；封面完成后补齐，过期请求不得恢复旧书或旧播放状态。慢网、连续切书、暂停和无封面通过定向回归验证；动画流畅度仍需动态设备观察。
- 首页、更多页和搜索页书卡提供封面位置与快照，用于书卡展开到详情页、返回收回的连续转场。
- 详情先使用书籍缓存展示，再刷新数据。窗口尺寸或源书卡位置失效时降级，避免飞向旧坐标。
- 详情的分类、状态和总章节标签下独立显示“最新更新时间：源返回时间”，使用次级文字、18vp 行高、最多两行；无时间时隐藏且不占位。简介清除 HTML 标签与实体残留并保留换行，旧缓存同样处理。
- 目录加载没有固定延时；搜索快照缺章节时优先恢复已存目录。网页规则批量提取静态字段，保持章节顺序、URL 去重及变量一致；回归检查上千章目录、重复进入已收藏书、播放入口和章节排序。
- 记录、下载和播放器等无源书卡节点的入口使用普通详情转场。
- 播放页、详情和设置使用共用窗口断点；高度低于 760vp 或宽度低于 360vp 时收紧布局。播放页竖屏允许纵向滚动访问全部控件；实际窗口宽大于高时切为左右布局，左侧正方形封面及来源角标，右侧章节信息、进度、播控和功能栏。封面按可用高度及右栏最小宽度收缩，右栏高度不足时独立滚动；旋转及窗口尺寸变化复用页面 onSizeChange，不改变播放状态、进度及设置。
- 播放页封面左上角展示导入书源名称，本地书显示“本地导入”，无法解析书源时显示“未知来源”；长名称单行省略。上排依次为后退 15 秒、上一章、播放/暂停、下一章、快进 15 秒；上一章/下一章图标为 36vp（紧凑窗口 32vp），快退/快进为 20vp、44vp 点击区，左侧图标左边缘及右侧图标右边缘对齐进度条端点，直播及加载期间不允许跳转进度。移除播放模式切换入口，进入播放页使用顺序播放，末章自然结束或跳过片尾后停止。底排依次为倍速、闹钟、跳过头尾、章节，图标为 25vp，倍速数值为 15fp，点击区高 44vp；启用后使用主题色，未启用为 #B3B3B3。闹钟始终保留，定时剩余时间或章数显示在右上角。章节使用系统 music_note_list。两排各内收 9vp；播放/暂停保留系统替换动画及主题色加载指示器。封面与标题间距在常规窗口为 32vp、紧凑窗口为 16vp，保留系统底部安全区；竖屏内容可同屏显示时，标题与进度条之间弹性填充剩余高度，使底排贴合底部安全区，紧凑布局也不在底排下方堆积空白；高度不足的紧凑窗口保留纵向滚动和固定内容间距。

## 播放与定时

- 播放页背景延伸至系统栏和挖孔区域，内容层左右留出 `WindowUtils` 动态计算的系统栏、摄像头挖孔及导航区域安全距离，再加页面普通边距；封面、顶部按钮、章节信息、进度及两排控件共用安全内容区域。横屏左右旋转及恢复竖屏时实时更新，封面尺寸按扣除安全距离后的可用宽度计算，不硬编码摄像头尺寸。
- 播放页封面下的章节标题使用 20fp 加粗，最多两行，超出省略。
- 播放页支持章节选择、进度拖动、0.5x–3.0x 倍速和片头片尾跳过；按书籍、章节保存进度。
- 播放页章节列表在弹层显示后定位当前章；触摸列表或通过滚轮、键盘、滚动条开始浏览时，取消尚未执行的定位及居中校正，避免快速滑动被拉回。搜索、切换目录布局及关闭弹层清理旧定位；“回到当前章节”仍可主动定位。
- 章节、倍速、跳过和定时使用原生 bindSheet 底部弹层，通过 systemMaterial 接入固定弱档（厚材质）的 AppMaterial.PlayerSheet，旧系统固定使用厚磨砂，不跟随全局材质档位；文字跟随系统主题，支持下滑、点遮罩和关闭按钮收起。章节面板为 80% 高，倍速及跳过面板为 55% 高，内部 Scroll 显式顶部对齐，标题上方仅保留 8vp 内容间距，避免内容居中产生大片顶部留白；小窗口内容可滚动，定时按内容自适应。倍速滑条左右提供减/加按钮，每次 0.05x，范围 0.5x–3.0x；片头及片尾每次 1 秒，范围 0–120 秒，边界按钮禁用。拖动结束立即保存，长按倍速恢复 1.0x，长按跳过清除设置，长按定时取消。
- 定时弹层分“按时长 / 按章节”，切换页签只浏览选项；点选预设立即生效并收起，替换另一种模式。时长支持 15/30/45/60 分钟及自定义 1–1440 分钟；章节支持播完本章、3/5/7 章和自定义 1–999 章（不超过当前目录剩余章数）。自定义原位展开数字输入，键盘“完成”校验后立即生效，无开启按钮；无效输入保留已有设置。
- 章节停止计入当前章，生效期间按目录顺序播放至目标章，不修改原播放模式；面板显示停止目标，入口显示“本章结束 / 剩余 N 章”。章尾停止先于自动下一章及循环；跳过片尾视为本章结束。手动暂停保留设置，手动切章或切书取消章节停止并提示。停止后自动清除，再次播放继续下一章（已到末章则沿用重播行为）。
- 到时仍在播放且本章剩余时长大于 0、不超过 10 分钟时，智能停止等待本章结束；剩余时长超限、无效或未在播放时直接暂停。等待期间显示“定时已到，播完本章后暂停”，可以取消；切换智能停止开关不会重新计时，关闭开关会结束正在进行的章尾等待。当前没有渐弱淡出功能入口。
- 锁屏和控制中心媒体卡片提供倍速、上一集、下一集和收藏，最左侧为倍速；倍速与 App 双向同步。
- 系统播控切书时先提交当前书籍的缓存封面或内置占位图，再异步更新实际封面；无封面、下载/解码失败及元数据重试不能沿用上一册图片。书源缓存和自定义封面的 `file://` 地址按本地文件读取，不能走 rawfile；迟到的旧封面不得覆盖新书。2026-10-23 手机验证：某导入源的书籍音频地址解析失败后切回另一册，继续播放且控制中心书名、封面一致；封面生命周期及阅读/播放同步回归通过，Release SDK 26.0.0.105 构建安装通过。依据已读取的 [ArkTS 语法规范](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[媒体图片处理指南](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/kits_media/SKILL.md)和 [AVMetadata 接口](https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/reference/apis-avsession-kit/arkts-apis-avsession-i.md)。
- 支持佩戴检测的耳机双耳摘下、蓝牙断开或有线耳机拔出导致当前输出设备不可用时暂停，保留进度；加载中收到暂停也不能在准备完成后起播。戴上续播响应耳机/系统的播放指令，依赖耳机佩戴检测设置；单纯重连不自动起播。回归检查重复播放/暂停指令、加载中摘下，以及暂停后的迟到焦点恢复事件。
- “投播”打开系统设备选择器，仅对已解析的 HTTP(S) 音频地址启用 URL 投播。连接远端后从当前进度起播并暂停本机。
- 在线音频按格式使用系统托管缓存；M4A/M4B/MP4/MOV 使用普通网络播放以支持快速读取尾部索引，HLS/直播保持在线续流。本地导入与已下载章节从沙箱文件播放。系统缓存不作为已下载章节列入下载管理。

## 小说阅读

- 替换净化规则面板支持“导入规则”：选择一个 UTF-8 JSON 文件（最大 1 MiB），预览名称列表后确认作用于当前书（默认）或全部书籍。支持规则数组、单个规则及 `{ "rules": [...] }`，读取 `name/pattern/replacement/isRegex/enabled`（兼容 `isEnabled`）；替换文本可为空，缺省正则/启用均为 true。最多保存 200 条；重复规则跳过，正则先经有界 QuickJS 批量校验，保存失败整批回滚。仅标题、特定书源、非空 scope/excludeScope 等不能直接迁移的范围显式报错，不静默扩大应用范围；不执行文件脚本。
- 覆盖翻页复用单张 PixelMap 的 Image 层，点击和松手后统一由显式 Animator 进度更新位移，避免新挂载图层仅收到属性过渡终点而直接跳页；不逐帧重绘整页 Canvas。拖动排队帧只读取最新动画进度。覆盖在准备、收尾及异步提交期间接收最近一次点击、按键或滑动；新输入将当前动画收尾缩短为 80ms，等进度与布局提交后接续，保留交接期间的滑动位置和松手状态。等待操作最多一项，取消、离页、后台、模式或窗口变化时清空，旧动画回调不能重复提交；原版 EPUB 提交完成前不准备下一页。应用排版横屏双栏仿真采用页角折叠与斜折线裁剪：中缝书脊与另一侧旧页固定，纸背显示目标内页，文字保持原比例；每帧最多四次正文图片绘制。上下页角与纵向拖动决定折线，横向页角跟随手指，松手从最后实际绘制的位置减速落页，取消还原的布局完成后再移除截图。原中央直线改为 36vp 内的渐变书缝，保留中央凹陷、侧面柔光与上下渐隐，避开页眉、页脚及阅听状态；书缝独立于正文截图，翻动纸背覆盖其上，落平末段平滑恢复。纸背轮廓先绘制不透明底色，再叠加正文和折痕光影，底页不得穿透；取消整页纸边描线，起止帧直接绘制完整截图，避免中缝上下黑线闪烁。单栏保留原柱面卷页。截图及目标布局就绪后开始，取消不提交阅读进度；快划、离页与过期完成回调受同一代次守卫。

2026-11-09：几何与真实组件回归覆盖页角跟手、书脊约束、面积与文字比例、双向纹理、松手接续、取消交接、书缝层级和资源释放。参考并实际运行 [StPageFlip 官方演示](https://nodlik.github.io/StPageFlip/)，阅读其 [FlipCalculation](https://github.com/Nodlik/StPageFlip/blob/master/src/Flip/FlipCalculation.ts) 与 [CanvasRender](https://github.com/Nodlik/StPageFlip/blob/master/src/Render/CanvasRender.ts)；采用页角反射、内外折痕与固定书缝的绘制思路，未引入第三方运行库。实现使用已读取的在线 [lang-syntax](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[ArkUI 检索技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md)及 [CanvasRenderingContext2D 指南](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/04-components/drawing/ts-canvasrenderingcontext2d.md)，构建诊断参照 [ArkTS 检查技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-syntax-checker/SKILL.md)。

本轮书缝版本已覆盖安装 HUAWEI Mate 80，并确认横屏双页静止书缝与页眉页脚留白。用户随后反馈双页纸背透字与落页中缝上下黑线，已增加纸背轮廓的独立不透明填充、移除纸边描线，并让起止帧直接绘制完整截图；相关定向回归及 Release SDK 26.0.0.105 增量 Debug 构建通过，HAP 元数据为 Release / API 20–26。ArkTS 快检引用旧 `.ts` 几何定义，实际编译通过。验证期间设备断开，最后两项修复尚待重新连接后安装及实机动态确认；没有平板实机验收结果。

- 在线小说经 `BookSourceService` 获取正文，用 `OnlineTextPaginator` 分页；保存章节与字符位置，字号或窗口变化后重新分页。
- 重新进入阅读先恢复本地目录和已读/预读正文，缺失或损坏才联网补齐。正文保存在应用持久目录，正常重启和系统普通清缓存后可复用，应用内主动删除后需重新获取；收藏不自动下载全书。回归覆盖读一章后重启断网恢复、目录重排、缓存损坏回退、字号/窗口变化后字符位置恢复。
- 在线正文通过光感分段选项切换“无效果 / 覆盖 / 仿真 / 滚动”：无效果直接提交页面，覆盖平移纸面，单栏仿真使用二维拖动驱动的斜向柱面卷页：落点上下位置决定起始折角，纵向拖动调整折线，卷曲区域分条投影正文纹理，纸背淡化反向文字并绘制随卷曲变化的投影；卷曲区最多 8 条并按条带裁取源位图，平直正背面各绘制一次；同一显示帧仅绘制最新手势位置，投影不做整页逐帧高斯模糊；仿真折线按手指横向位移的一半推进，避免反折纸边倍速退出；松手从最后已绘制的位置接续，快速划动在截图/目标页准备完成前结束时仍从原页展示完整卷起过程。单栏仿真确认收尾为 300–520ms 的 ease-in-out，回弹为 180–320ms；双栏点击为 300–600ms 的 ease-in-out，手势松开使用 160–420ms 的 ease-out，慢拖未达 28% 时回弹；覆盖普通收尾为 90–280ms，连续输入时收尾缩短为 80ms；滚动保持原有速度。轻点两侧自动翻页，短距离拖动松手回弹。目标章节先加载预览，动画完成保存新位置；退后台、离开页面或窗口/设置变化时，已确认的翻页立即完成并保存，未确认的拖动或加载失败保留原位置，系统 Cancel 不撤销已确认页。重新分页和启动时的临时布局始终保留最后确认的字符位置，不用临时页首覆盖；回归覆盖翻页后立即上滑回桌面、再次进入 App，以及反复前后台切换和字号/窗口变化后的页码恢复。
- 字号、行高、段落间距、字重滑块拖动时只刷新面板预览，松手/步进提交后正文重排一次；段落间距位于行高下方，范围为 0～2 倍字号、步长 0.1，默认 0；减号仅在 0 时禁用，加大数值后立即恢复可用，仅在自然段之间添加留白，翻页与连续滚动一致，保存设置及备份并保持字符进度；EPUB 原版主题使用书内段落间距；同宽同字体的测量结果在分页、滚动和再次进入阅读间复用，最多保留 4 份且合计不超过 16 万原文字符，系统字体变化主动失效。连续滚动合并同一轮参数/尺寸变化，相同排版不重载列表；原生绘制节点更新段落引用而不重建，保留上一份正文到新布局就绪，避免空白闪帧。
- 字体面板提供“正文对齐”：两端对齐（默认）、左对齐、居中、右对齐。完整正文的原生 Paragraph 同时用于测量和绘制，分页与连续滚动只绘制可见原生 TextLine，沿用原段落坐标并减去当前块顶部偏移，不把行切成独立 Text 重新排版；两端对齐保留段末自然收尾，跨页续行保持原排版。切换后按原字符位置重排，对齐偏好参与保存、恢复默认和备份，旧偏好及旧备份默认两端对齐。连续列表键包含排版版本，确保只改变对齐但换行位置不变时也更新显示。
- 正文每段首行统一缩进两个字宽（2em），API 26 使用原生行首边距，绘制正文中不插入缩进空格、占位或零宽字符，避免两端对齐在首字前额外分配间距；API 20–25 保留按实际字体测量并补足宽度的段首空格作为兼容排版。显示前清除段首各类 Unicode 空白。连续换行及仅含空白字符的段落在显示时合并为一次段落换行，同段跨页续行不重复缩进；缩进和空段落折叠参与分页测量，原文及缓存不变，分页与朗读高亮在原生正文、显示文本及原文字符偏移之间映射，兼容已有阅读进度和朗读定位。
- 阅读页默认常驻显示系统状态栏；阅读设置提供“始终显示状态栏”开关，关闭后跟随“章节 / 设置 / 字体”悬浮栏显隐。自定义背景和翻页纸面按整个视口绘制，图片连续延伸到顶部状态栏及底部系统区域；安全区内边距只作用于正文，不使用顶部纯色遮罩或按正文区域单独缩放背景。顶部手势保护保留；状态栏显隐、工具栏和弹层开合不改变正文高度或页码。API 22 起使用忽略显隐的系统避让区，API 20–21 保留本次阅读已测得的顶部高度；正文底部不为手势小白条预留完整手势区，只保留 8–16vp 最小避让（三键导航等实体底栏仍完整避让），翻页与滚动模式的手势留白与用户下边距取较大值，再保留已启用的页脚，避免重复叠加（实体导航栏仍单独避让），列表边缘渐隐缩短为 12vp；按正文实测区域分页，避免末行裁切。旋转或窗口尺寸变化按字符位置重新排版。离开阅读页（包括打开详情）恢复系统状态栏，返回阅读后恢复已选模式，系统栏切换不使用动画，状态栏文字颜色跟随阅读背景。退回桌面不视为离开阅读路由，返回前台保留当前阅读模式和布局；系统深浅色未变化时不重新发布配色，最小化空避让区与零尺寸不参与重排。回归需分别检查固定状态栏开/关时的整屏图片连续性、覆盖/仿真翻页和滚动阅读，以及反复从桌面返回后正文、背景和页码保持稳定。
- 点击两侧或滑动翻页时自动收起底部工具栏；状态栏在常驻模式继续显示，在跟随模式同步隐藏。
- “详情”进入书籍详情；章节和设置以底部弹窗覆盖正文。子弹窗打开时隐藏阅读悬浮栏，收起后恢复。目录与阅读设置使用原生 bindSheet，分别为系统最大高度 / 82% 高；表面使用固定弱档（厚材质）的 AppMaterial.ReaderSheetThick，旧系统固定使用厚磨砂，去除自绘深色背板，文字随系统深浅模式适配。
- 目录打开时定位当前章节，滚远后可“回到当前章节”。
- 小窗直接启动及全屏/小窗切换后重新计算安全距离。
- EPUB 导入、元数据和阅读全部使用自研实现，原版精排由本地 ArkWeb 阅读器显示，应用主题使用统一文字阅读器。旧版仅存 EPUB 路径的书籍提示重新导入。导入格式支持 TXT/EPUB/MOBI/CBA/PDF/HTML/HTM、音频和 ZIP；MOBI 保留未加密 MOBI6/PalmDOC 的元数据、目录与图片，PDF/CBA 保存为本地图像章节。

- 横屏正文、页码、顶部操作及悬浮栏动态避让左右摄像头和系统区域，左右留白同时计入分页宽度；背景保持全屏。顶部实际留白为用户上边距减 12vp（最小 0），页眉高 22vp；关闭常驻状态栏时竖屏仅为顶部挖孔留白，横屏取顶部挖孔与 16vp 最小间距的较大值，保护无摄像头一侧的页眉和页码不贴入屏幕圆角；工具栏临时显示状态栏不重排正文，旋转清除竖屏残留的顶部安全距离。
- 工具栏仅由配置为“工具栏”的区域轻点呼出；触摸曾移动 8vp、多指、取消或开始拖动/滚动后，整次手势不再视为点击。回归检查横竖屏旋转保留字符位置、往返滑动不弹栏、九宫格设置退出重进恢复。

2026-11-08 文档反馈 39–43：规则导入、翻页状态/双页几何、漫画裁剪/缩放/位置恢复、桌面歌词及 69 项朗读回归通过；已有精排跨章宿主与 Chromium 回归通过。Release SDK 26.0.0.105 Debug HAP 构建通过；独立检查 LSP 未初始化、构建 MCP 的 ohpm 批处理递归失败，使用同一 Release IDE 的 CLI 完成。无设备连接，MatePad Pro 13 模拟器启动超时，未验收实际动画帧率、裁剪视觉和系统桌面字幕。 同日随后恢复实机 VYG-AL00 的 HDC 调试连接，经 start_app 成功覆盖安装并启动上述修复版本；安装启动不等于五项交互与帧率的实机验收。

技术依据为本轮读取的在线 [ArkUI 性能分析](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/arkui-performance-analysis/SKILL.md)、[animateTo 模式](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/arkui-performance-analysis/references/animation/animateTo-patterns.md)、[ArkTS 语法检查修复](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-syntax-checker/SKILL.md)及 [Hvigor 构建](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-studio-hvigor/SKILL.md)，接口以本机 Release SDK 诊断复核。native-flow 的 harmony-build-fix 原始文档返回 403，已改读同目录索引发现的 ArkTS syntax-checker，未据此执行完整设备性能采集。

### 阅读设置

- 页眉、页脚、时间、电池轮廓及内部数字跟随阅读正文字色，包含夜晚、纯黑、自定义配色和图片主题。页眉、页脚各有整体开关，关闭后不留空行；左上、右上、左下、右下可分别选择章节名称、页码/阅读进度、章节序号、书籍名称，选中另一角已占用的内容时自动交换，两侧长文字单行省略。每种信息保留独立显示开关，电量时间保持页脚居中。位置及开关持久化并参与阅读备份，旧设置保持原位置和显示状态；恢复默认还原左上章节名称、右上页码、左下章节序号、右下书名。布局变化按字符位置重排，翻页预览同步新位置与颜色。

- 设置与字体面板的选项、数值、字体菜单和操作文字使用自适应深浅色的中性文字，不受全局主题色影响；选中档位通过中性底色和边框区分，正文及预览仍使用阅读配色。

- 正文上下左右边距滑杆两端提供“− / +”按钮，点击按 1vp 微调并保存，到达对应上下限时禁用。
- 底栏三个入口等宽平分、图标各自居中，只展示图标并保留无障碍名称，“字体”在“设置”旁边；字体面板首项为阅读主题，随后提供预览、字号、行高、连续字重、文字调色盘和 TTF/OTF 字体导入。设置面板保留翻页方式、边距、亮屏时间和状态栏/页脚开关。
- “点击区域”默认折叠为标题与箭头，点击整行展开说明、九宫格、尺寸调整和恢复默认，再次点击收起；展开状态只保存在当前面板，不写入阅读偏好。每格点击循环切换上一页／工具栏／下一页／无操作，至少保留一个工具栏入口；默认左列上一页、中列工具栏、右列下一页。左右列宽、上下行高通过百分比滑杆调整（单侧至少 5%，中间至少 10%），九宫格按实际比例预览。“上／下／左／右”横向选项 Tab 每次只显示当前方向的比例滑杆，实时显示百分比，左右提供 − / + 按钮，按 1% 微调并在边界禁用；拖动松手后保存。配置持久化并参与阅读备份，支持恢复默认；滚动模式上一页／下一页移动约 85% 屏高。
- 字体面板的章节大标题卡片直接显示“显示章节大标题”开关，去掉上方重复的小标题，保留开启后的样式和字号控制。字距与段落间距采用一致的无背景 − / + 按钮、内嵌滑条和右侧数值，范围 0–10vp、步长 0.5vp，到达边界禁用按钮，点击立即保存。
- 阅读设置提供“音量键翻页”开关（默认关闭并持久化、支持备份）：仅在工具栏隐藏的纯净阅读状态下，音量加上一页、音量减下一页，上下滚动模式每次滚动约 85% 屏；工具栏或弹层打开、开关关闭时注销音量键消费，交给系统调节声音，收起工具栏后恢复翻页。小说和漫画均遵循此规则。通过 inputConsumer.keyPressed 拦截系统音量键，不依赖正文/底部 Tab 焦点；阅读页不可见或退出时注销。回归检查按下一次只翻一页、长按不重复、工具栏展开/收起时释放/恢复订阅、首末页边界及重新进入后的开关状态。
- 分页正文更新使用 FrameNode 自绘重绘通知，覆盖/仿真/无效果均需检查正文实际前进、回退、跨章与手势回弹，而不仅检查动画和页码。
- “翻页震感”位于翻页效果下方，左侧标题、右侧下拉选项依次为无效果、强劲、中等、弱感；默认无效果，选择立即保存并反馈一次。手动分页成功、连续滚动完成后位置变化、EPUB 原版手动翻页时单次反馈；取消、边界未移动、自动翻页、恢复和重排不反馈。档位随阅读偏好及备份恢复，旧配置和旧备份均默认无效果。使用 Sensor Service Kit 的预置触觉及 API 12 强度参数，先查询效果支持，不支持时回退短时振动；设备不支持强度调节时由预置效果决定实际力度。
- “翻页效果”标题与下拉选项同一行；状态栏开关即时生效并持久化，旧设置缺省及恢复默认均为常驻显示。
- “字体主题”面板移除标题下方的正文预览，直接展示主题与字体设置。字号、行高、字重使用紧凑卡片，正文对齐位于字重下方，保留控件操作尺寸。字号范围 14–50，采用步进按钮与滑杆；行高范围 1.0–2.4，保留四档预设，左右按钮每次增减 0.1；行高、字重与字号的滑杆长度、6vp 粗细、34vp 步进按钮及数值列宽一致；系统字体字重范围 100–900，滑动按整数连续调整，加减按钮每次增减 100，到达边界禁用，选中自定义字体时隐藏字重。字体每次最多导入五个，保留历史字体并默认选中新导入的最后一个；“字体主题”面板中的自定义字体与正文对齐使用同款原生下拉选择器，标题与选项同行；每个导入字体选项内右侧显示删除按钮，无需先选中；删除非当前字体保留当前字体，删除当前字体后切回系统字体，系统字体不提供删除，导入入口保留在下方。导入字体复制到私有目录（单文件不超过 32 MiB），正文与分页测量共用字体集合，重新进入恢复选中字体。
- 行高、翻页模式与阅读主题选中态由响应式参数驱动，点击后立即更新高亮，与实际生效配置一致。
- “系统字体”使用用户当前的系统字体，正文、预览和分页测量不指定固定字体族；系统字体、字号或字重配置变化后重新排版并保持章节与字符位置，未变化的前台恢复不重复排版。导入字体继续使用已选字体。
- 页脚中间默认显示内含电量数字的电池图标和本地时间（HH:mm）；电池采用紧凑圆角镂空轮廓、透明内部及跟随阅读正文字色的电量数字，电池头弱化，时间与电池之间直接留白，未知电量显示“--”且同样跟随主题字色，无障碍仍播报电量百分比，阅读设置的“显示电量和时间”开关即时生效并持久化；恢复默认重新开启。状态独立刷新，关闭时释放电量刷新任务，开关不改变正文高度、阅读位置或系统状态栏。
- 主题分为预设（羊皮纸、夜晚、纯黑）和自定义主题。非会员可用 1 个，有效会员可用 5 个；额外主题在权益失效后保留数据，当前若使用额外主题则回退第 1 个。每个主题独立保存名称、配色、背景图、显示方式和蒙层，缩略图显示实际图片，名称最多 20 字，留空显示“自定义 N”。编辑器统一提供改名、导入/更换/移除图片和文字/背景调色，保留 HEX 输入、非法值禁止保存、对比度提示与主动推荐字色。保存并应用才生效；取消、返回和下滑关闭清理新导入的草稿图片，不改变原主题。保存失败保留草稿并可重试，图片保存成功后才清理无其他主题引用的旧文件。旧图片主题迁入自定义主题，正在使用的图片迁入免费槽位并保留配色/蒙层，未选中的旧图片不覆盖正在使用的纯色主题。主题与图片文件不进入跨设备阅读设置快照。
- 自定义图片首次点击打开相册；已有图片时直接恢复，主题内可更换图片并调节蒙层浓度（0–85%）。在线阅读正文和预览同步显示图片与蒙层；背景色和背景图变更仅刷新绘制，不重新排版滚动正文。阅读设置、章节和朗读弹层固定弱档（厚材质），保留系统深浅模式适配，不跟随全局材质档位。
- 自定义主题中的背景图支持“自适应 / 平铺 / 拉伸 / 裁剪”：分别为等比完整居中、原始尺寸从左上角重复、非等比铺满、等比居中裁剪；默认裁剪以保留旧效果。每套主题独立保存显示方式和蒙层，正文与编辑预览共用背景组件，保存主题不重新分页。在线及转换为本地章节的导入电子书支持四种模式；EPUB 原版主题保留书内背景，不显示应用背景选项。
- 阅读主题面板的预设采用等宽纸张预览卡，展示实际底色与字色，选中时显示品牌色描边和角标。自定义主题采用竖向卡片：色样在上、名称与使用状态居中、独立编辑按钮在下；按容器宽度等分三列，间距 8vp，一屏完整展示三个槽位，其余横向滑动查看，免费槽位沿用相同宽度。权益说明使用辅助字号，跟随系统开关通过细分隔线独立成行；编辑不提前应用主题。
- 相册图片复制到 `files/reader_bg`，解码验证后应用，显示时转换为文件 URI；新路径保存成功后清理上一张。取消或图片无效时保留当前主题，失败显示提示。
- 拖动时更新预览，结束后持久化；恢复默认重置设置。旧相册设置迁移为自定义图片并保留蒙层；旧纸纹、布纹及无图片的自定义色回落到预设主题，已丢失的图片路径回退为默认主题。
- 阅读位置和设置使用独立 Preferences 保存，通过 `ReadingBackupService` 的白名单加入系统、本地和云备份；恢复保留本机导入书进度和未纳入备份的自定义内容。旧快照没有阅读数据时不改动本机阅读数据。

- 上下滚动模式的正文视口上下边界均使用渐变模糊，不拦截正文触摸。
- 亮屏时间支持跟随系统、1/5/10 分钟、常亮；触摸重置计时，计时结束交还系统灭屏策略，退后台或离开阅读页面释放常亮。
- 章节目录未缓存显示云朵，已缓存显示空心圆形勾选；取消章节时长展示，下载中及失败状态仍保留。书架删除等待原生菜单退场后更新数据，避免残留点击锁/遮罩。

## 启动设置

- “设置 → 播放 → 全局默认倍速”位于播放分组首项，默认 1.0x，支持 0.5–3.0x、步进 0.05x。滑杆左右提供无背景的主题色减速、加速按钮，点击区域保持 44vp，点击立即保存，达到上下限时禁用对应按钮。滑杆复用公共 `SliderGestureModifier`，仅拖动调速，点击轨道不跳变；初始横移超过相当于 0.1x 的轨道距离才开始响应，减少上下滚动时手指轻微横移导致的误调，精细 0.05x 调节使用加减按钮。松手后保存，保存期间禁止重复提交，失败回退已保存值。仅用于没有有效单本倍速记录的有声书；已有记录（包括 1.0x）优先恢复，同书切章保持倍速，修改全局不改变正在播放的书，单本调速不回写全局。全局值随设置备份恢复，旧备份缺失时回退 1.0x；直播和 TTS 沿用各自原有行为。

- “设置 → 启动 → 打开软件自动播放”默认关闭，与“默认打开”同组。切换后持久化，下次启动生效；旧版本偏好或旧备份缺少该字段时按关闭处理。
- 开启后，应用冷启动并进入前台时，从上次章节、进度和倍速继续播放；没有播放记录或内容无法恢复时保持静默。普通后台切回不触发，已在播放或加载时不重复起播，跨设备续播与卡片控制保持其明确的播放/暂停指令。
- 回归检查开关默认值、退出重进后的保存、关闭时冷启动不播放、开启后按原进度续播及空记录启动。

## 搜索设置

- “设置 → 搜索”位于“播放”分组下方。搜索并发数默认 3，提供 3/6/9/12 下拉选项和 1–12 自定义输入；应用后持久化，下次提交搜索生效。
- 搜索并发数纳入系统、本地和云备份；旧备份缺少该字段时恢复默认 3，非法值拒绝恢复。保存失败提示并保留原设置。

## 系统设置外观

- 播放页封面保留首帧小图，高清层按实际容器尺寸分档解码，确认解码成功后才显示；失败保留搜索备用封面或原图。详情规则封面优先于后续搜索缩略图，封面来源和备用地址随书籍缓存持久化；新详情地址仍可更新旧图，同名异源书籍不混用封面。

- AI 封面超分、漫画 AI 超分、AI 翻译与 AI 着色均为有效会员权益，仍需设备支持；入口、预热、排队推理和增强缓存显示均校验权益。权益失效后取消任务并恢复原图；关闭偏好无需会员。
- “设置 → 外观 → AI 封面超分”名称右侧显示与搜索并发一致的金色 VIP 标签，标识功能权益，不依赖当前账号是否开通会员。开关默认关闭，持久化到本机偏好。仅增强播放页低清网络静态封面；API 26 以下或缺少系统视觉能力时置灰。开启后先显示原图，成功才叠加增强图，失败继续显示原图；关闭开关立即撤下增强图。切换封面、离开页面后不应用旧任务结果。
- 设置开关通过 `Binding` 读取最新状态；本地偏好加载完成后恢复可操作，保存期间临时禁用，保存失败时同步回滚开关。回归覆盖超分、启动自动播放和音频播放方式的初始值与重复切换。
- 超分使用 CoreVisionKit ImageSRAnalyzer（API 26），以书源图片请求头读取原图，串行处理 32–640 像素边长内的封面；增强缓存位于 cacheDir，最多 12 张、单张不超过 4 MiB，不替换书籍原始封面 URL。验收需覆盖开关重启保持、旧系统回退、处理失败、切书离场、缓存复用及真实设备效果。

- “设置 → 外观”包含主题模式、材质效果和主题色。材质选项为跟随系统、强、均衡、弱，默认跟随系统；手动三档分别映射薄、标准、厚材质，能力不足时四种选项均保留可见底色与磨砂，具体策略见前文；弱档保留原阅读弹窗厚材质观感。这是应用材质偏好，不修改系统光感强度；设备系统强／均衡／弱配置仍决定最终效果。设置页与阅读翻页选项使用原生 Select 下拉菜单，入口与菜单分别设置沉浸材质；外层入口采用 40vp 高胶囊和透明背景，三个“应用”按钮（预缓存、搜索并发、自定义主题色）使用 HDS 原生浮动材质保留沉浸轮廓，触点处叠加随当前主题色变化的柔和光晕，抬手或取消即消退，文字仍随深浅模式显示黑/白；宽度跟随所在行布局，旧 API 或材质能力不足时回退系统底色与磨砂，支持光感时避免实色背景遮挡，选项入口、普通项及选中项文字均随深浅模式显示黑/白字，选中背景使用中性分层色，不跟随主题色。主题色通过小尺寸原生居中弹窗提供预设和六位 HEX 自定义，宽度最多 320vp 并保留窗口左右间距，高度随内容撑开，六个预设固定三列两行。弹窗宿主直接使用原生沉浸光感材质，旧系统回退超厚磨砂，内容层不重复叠加材质；右上角关闭、点击遮罩或返回均可退出，未应用的草稿丢弃。应用后即时刷新 AppColor/HomeTheme 强调色、共享材质光感和底部导航选中态。
- 这两个入口只存在于系统设置，不添加到阅读设置。阅读纸张配色独立保存。外观偏好持久化到现有 Preferences，冷启动恢复，并纳入系统设置备份；旧备份缺少新字段时使用默认值。

## 书源管理与测试

- 书源支持轻页兼容规则与 `sourceFormat: "native"` 原生定义，沿用文件/链接/扫码导入、来源管理、单源/批量测试与 JSON 导出。原生定义通过 JSON 页签编辑；保存前保留用户输入，未保存返回确认和锁定保护继续生效。已停用格式的新导入会被拒绝，历史定义仅保留数据。
- 发现分类、搜索、详情、目录和阅读/播放统一通过轻页核心执行用户导入的定义，页面复用现有实现。回归检查导入→分类/搜索→详情→目录→播放/阅读→导出重导；主机回归不代表真机播放、下载或手表验证已完成。

- 书源页顶栏与列表按上下顺序独立布局：标题、搜索、类型及分组／状态筛选占据自身高度，列表通过 layoutWeight 使用剩余空间，滚动区域从筛选栏下方开始，避免卡片标题和操作按钮被覆盖截断。首项统计行仅保留紧凑内边距，不再通过顶栏测量高度补偿；加载、批量管理、管理子视图及窗口变化均沿用同一布局。依据已读取的 [ArkUI List 布局说明](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/03-layout/grid-list/ts-container-list.md)，保留书源排序、数据和稳定列表键。
- 入口为“我的 → 书源”，与设置同级。标题栏移除新建书源和“导入”文字；右下角 52vp 圆形加号展开本地 JSON、链接导入、NAS、扫码菜单。链接导入打开居中悬浮弹框，仅提供单行链接输入与取消/导入按钮；支持 HTTP(S) 和阅读书源分享链接。链接与 NAS 输入框统一使用加深灰底、1vp 描边和次级文字色占位提示，base/dark 配置同名颜色资源，避免与弹框材质混为一体。NAS 使用独立居中悬浮弹框；文件选择与扫码直接执行，移除原底部大导入面板。文件、链接和 NAS 处理期间均显示主题色 loading，禁用重复提交；链接和 NAS 失败保留输入，处理结束恢复操作。文件进度、结果和跳过原因留在列表中，关闭弹窗不改变列表位置。管理模式隐藏悬浮入口，批量测试期间禁用导入。
- 书源管理与设置页统一为 16vp 圆角、无描边无投影的主题表面卡片，条目间距 8vp，名称左对齐，展开箭头、更多菜单与启用开关垂直居中；默认全部折叠，保留置顶／锁定标记。展开箭头使用 22vp 图标和 40vp 方形区域，名称与箭头共用整行点击入口。点击独立展开类型、分组、地址、测试状态及操作，再次点击收起；展开信息以细分割线区分。刷新及筛选保留本次展开状态，重新进入恢复折叠。
- 顶部采用 4vp 行间距、40vp 原生圆角 Search、36vp 类型分段控件及 32vp 分组／状态筛选。类型采用书架／主题页同款 CapsuleSegmentButtonV2，背板与下拉入口使用可辨识的主题表面底色和细边界，选中项使用主题浅底与主题色文字；HDS 材质按实际高度裁剪阴影，旧系统保留磨砂回退。搜索支持输入清除，更多操作与测试图标使用次级文字色。未筛选时统计只显示总数，筛选后显示匹配数／总数。导入加号复用 ImmersiveCircleButton，保留原导入菜单及忙碌状态。
- 列表视口延伸至页面底部，安全区通过 List.contentEndOffset 留在可滚动内容末尾，避免页面底部内边距提前截断卡片。末尾留白为系统安全区与 28vp 中的较大值加导入按钮避让，最后一项可完整滚到浮动加号上方；管理模式改用较小尾部留白。管理子视图独立避让底部安全区。顶部、底部安全区随折叠展开和窗口变化更新。
- 本地 JSON 可多选：每次最多 10 个、单文件 10 MiB、总计 30 MiB、最多处理 1000 个书源；列表显示文件导入进度，完成后汇总已导入书源和跳过的书源/文件数。坏文件不影响后续文件，部分失败在列表持续显示超限、读取、格式或保存失败原因供重试。成功后清空搜索、分组和状态筛选，让新书源可见。单源原始 JSON 超过 512 KiB 时跳过。
- 多选导入的后台任务仅依赖纯 JSON 与基础库，禁止加载含 ArkUI 状态装饰器的书源模型；主线程分段恢复模型。连续读取依赖文件指针，不重复传入累计 offset。实机定向测试已覆盖 3 MiB 文件、跨 64 KiB 块中文内容、混合坏文件，以及落库后管理列表查询（2 个成功、1 个无效文件跳过）。
- 支持本地 JSON、扫码得到的单源/数组/列表外壳和 HTTP(S) 地址；链接弹框仅接受链接。系统文件管理器长按 JSON 后“使用其他应用打开”可选择简听阅读，进入书源导入；通过 `viewData`、JSON `type` 与 `FileOpen` 声明匹配。导入后显示“待测试”和能力提示。
- 连续从系统文件管理器打开 JSON 时，将已存在的书源管理页移到栈顶，不重复压栈；请求按原始授权 URI 排队，首次加载或前一个导入未完成时也不会覆盖后续文件。单文件失败不阻断后续导入，导入时列表和加号显示 loading，失败保留错误提示；不再打开导入面板，返回一次即可离开管理页。链接/NAS 弹框打开期间，外部文件继续排队，关闭后自动处理。同一文件再次主动打开仍可重导。
- 书源管理的悬浮导入加号为 25vp，批量测试闪电图标使用 20vp、36vp 外层点击区域；首页源选择统一放在首页顶部。
- 加号菜单提供“NAS”：悬浮弹框仅填写服务器根地址与访问码（可留空），验证成功后添加阅读/听书来源；访问码输入遮罩，连接按钮显示 loading，连接中禁用提交和关闭，失败保留输入并展示原因。已有 TaleBook 源的“登录”复用弹框，地址只读，只更新当前来源会话。阅读支持 EPUB 文字分页和有限大小的 TXT 单章，听书支持已发布的章节音频；发现可浏览各自书库，首页可选择有发现内容的小说或听书源。需在 NAS 开放访客阅读，IPv6-only 站点依赖设备网络可达。
2026-11-10 导入交互调整采用 UIContext 的 Builder 自定义弹窗，保持 ArkUI V2，API 26 沉浸材质经 PlatformCompat 守卫，旧系统沿用磨砂回退。参考已读取的 [ArkTS 语法技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md) 与 [ArkUI 自定义弹窗](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/08-dialog-menu/dialog/arkts-open-custom-dialog.md)。Release SDK 26.0.0.105 Debug HAP 构建通过，包内核对 Release 渠道、最低 API 20 / 目标 API 26；原导航队列回归通过，一次性真实方法回归验证文件/链接/NAS 的 loading 生命周期、重复提交互斥、取消和失败恢复。独立 ArkTS LSP 未初始化，语法校验以完整构建结果为准。已安装启动 Mate 90 Pro 模拟器，但其既有书源数据库无法解密，原数据保留；本轮未完成弹框视觉与真实 NAS 连通验证，也未完成真机验证。

- 搜索框按名称、地址、分组过滤，另有独立分组与状态筛选。支持默认顺序、名称、更新时间正序和倒序，置顶来源在前；默认顺序可在独立列表中拖动或逐项移动，持久化后重进保持顺序。
- 置顶、锁定、启停、分组和测试结果即时同步卡片与菜单；编辑保存返回立即刷新。排序列表连续上移／下移按当前行号操作，无需退出重进。
- 导入成功切回默认顺序，普通导入／重导来源按文件顺序排在未置顶分区最前面；已有置顶来源保留置顶及相对顺序，锁定来源仍跳过。
- “编辑”进入批量管理，全选作用于当前筛选结果；可批量搜索启停、发现启停、分组、导出、锁定/解锁和删除。删除需确认，同时清除对应主会话和 Cookie；锁定源在存储层拒绝修改或删除，批量操作跳过锁定项。
- 分组管理支持创建、重命名和删除，删除分组保留来源。导入多组定义按独立组名显示与筛选，改名或删除某组保留其他组；锁定源的分组不随批量设置、组改名或组删除改变，仍被锁定源引用的组继续显示。单源和批量导出保留未知规则扩展字段，排除运行时 Cookie、登录状态和脚本缓存。
- 来源卡片展示名称、类型、分组、地址、测试状态和诊断原因；底部图标按能力提供测试、主账号、网站登录、子源和删除。
- “参与搜索”按启用开关和必需搜索规则决定是否加入新搜索，测试状态不直接禁止启用。关闭后保留定义，已有收藏仍可解析。
- 校验页可选择全部、当前筛选或已选来源；搜索模式使用可编辑关键词，发现/阅读模式无需关键词。
- 单源测试有结果时继续验证详情、目录与正文/音频；普通来源正常请求但暂无匹配时保留来源并说明，不能把它当作完整内容链通过。
- 单源测试和批量搜索校验在缺少搜索规则或搜索链路失败时，自动尝试已启用的发现/阅读链路；取得公开章节正文或音频地址后显示“部分可用”并保留搜索失败原因。两条链路均失败时合并原因；不会自动启用发现，取消后不再补测。
- 批量校验最多同时运行 6 个任务，提供搜索与发现/阅读两种模式，展示总数、完成、通过、失败与保留数量。可取消、查看失败原因、重试和手动处理失败项；禁用和删除均须确认，失败默认保留。取消不覆盖尚未完成来源的旧测试状态，列表进度条可重新进入校验视图。
- 证书信任页按 HTTPS 精确主机添加或撤销信任；证书失败项可确认信任后重试。信任不延伸到子域或重定向目标，撤销后恢复系统证书校验，不迁移到其他设备。
- 来源需要主账号但尚未登录时，单源测试入口会转入账号页；批量校验记录各来源的实际失败原因，不自动批量打开登录页面。
- 导入保留脚本登录定义、类型和紧凑规则能力提示；当前不会仅因这些字段标记整源不可执行。仍须在实际请求阶段验证兼容性，非音频类型尝试文本链不代表支持漫画阅读。

### 书源编辑与调试

- 编辑页和调试页各自使用单个导航容器；标题栏独立保留状态栏高度，返回、保存和导出按钮具有完整触控区域，安全间距随窗口更新。
- 编辑页提供基本、搜索、详情、目录、正文、发现、登录、JSON 八个横向滚动页签，切换后回到表单顶部；多行脚本独立编辑。发现规则与完整 JSON 在切换或保存时校验，非法内容保留在编辑区。类型切换立即更新音频/正文字段。
- 返回时有未保存修改则弹出系统确认框，支持取消、放弃修改和保存并返回；保存期间防止重复提交。
- 调试阶段等宽排列，输入、日志和结果共用页面滚动；长日志、URL 和结果换行完整展示并可选择复制。运行期间不可切换阶段或清空日志。
- 编辑保存将字段合并到原始定义，保留未知扩展字段，随后失效来源缓存。支持导出当前书源 JSON；运行时登录信息、Cookie 和脚本缓存不合入书源定义。
- 调试实际执行搜索、发现、详情、目录、正文/音频和全链路。全链路优先复用搜索结果；搜索失败或无结果时记录警告，改从已启用的发现分类取书，继续详情、目录及公开章节正文/音频验证，成功显示“部分可用”并保留搜索错误。发现最多尝试 8 个分类；后续失败合并原因，取消不触发回退。仅搜索调试仍只验证搜索。全链路传递章节变量，未取得内容不报成功。停止操作在当前有界请求返回或下一处理边界生效。
- 调试记录请求方法、状态、规则样本和阶段结果，报告对敏感查询参数与凭据字段脱敏，通过系统文件保存选择器导出；取消选择不写入文件。
- 来源卡片可进入通用发现和登录表单。发现支持动态分类、嵌套分组、选择框标签/值、输入、开关、按钮、刷新和单源搜索；分类列表沿用书籍详情入口与去重分页。登录动作使用受限脚本，可调用登录定义中的函数、保存登录信息与请求头、进入 HTTPS 网站登录页，并执行配置的登录检查。
- 发现/登录面板、请求选项和 Header 可使用单引号、未加引号的键、注释与尾逗号等宽松 JSON 字面量；非法结构或超出预算时显示解析错误，不执行配置中的函数表达式。
- 发现分类的纯脚本入口可执行登录、刷新和单源搜索；脚本返回书单地址时进入书籍列表。输入框的规则在点击动作前提交，保留当前关键词；带分页模板的普通分类地址仍按书单加载。
- 声明网页渲染的来源可提取网站脚本生成的正文或音频；`webJs` 支持读取活动 DOM、输入、点击、事件、表单提交、滚动、等待和 HTTP(S) 跳转，包含定时回调与 async/await。脚本仍在受限 QuickJS 中执行，DOM 操作由固定原生动作实现；不执行用户提供的网页代码字符串或事件处理属性。网页登录和后台渲染不会同时占用隐私 Cookie 会话。音频地址解析成功与实际播放验证是不同的检查，调试页不会把接口错误文字当作播放地址。
- 网页交互回归：输入并触发 input/change → 连续点击 → 等待异步 DOM 更新 → 提交表单/跳转 → 提取正文或音频；检查动作不会因回放重复执行、旧页面元素不能误操作新页面、超时/失败后下一来源仍可使用浏览器。Android/Java 类导入失败应保留具体类名供调试，不将漫画作为适配目标。
- 带 JS 的章节地址在打开章节时计算，目录保留稳定标识和元素上下文，避免加载长目录时重复请求和预生成过期签名。

### 主账号与子源登录

- 聚合来源的子源页提供全部/小说/听书筛选、名称检索和状态刷新；先显示适配器目录，请求失败保留已有目录。
- 主会话与子源网站 Cookie 分开保存。子源登录进入相应官方白名单 HTTPS 页面，普通来源可使用其 HTTPS 登录地址。
- 书源卡片的登录入口与“发现”同排，显示当前登录状态；按主账号、登录面板、网站登录分派，编辑/调试操作行不再重复显示登录。
- 网页登录使用隐私 WebView，不暴露平台桥接，按来源和 origin 注入与回收 Cookie；Web 挂载后先恢复 Cookie，再发起首个网站请求，恢复失败提示准备失败。读取失败不以空值覆盖旧会话；退出时先写回 S2 加密数据库，再清理并释放 Web 会话。
- 等待式网页登录由书源脚本发起，用户完成后返回页面 HTML 并继续当前任务。带 HTML/脚本的 `showBrowser` 先通过受限渲染和 DOM 动作生成页面，再进入可见浏览页；成功完成时先写回 Cookie 并释放网页会话，再恢复脚本。返回取消或等待超时会结束等待并清理页面，清理期间不接收新的等待任务。全局同一时间只保留一个等待登录任务。
- 删除来源清除主会话与 Cookie；同 URL 重导保留尚未删除来源的登录态，删除后重导不恢复已清除凭据。

## 下载与导出

- 已完成下载的章节可以导出，进行中章节不在导出集合内。
- 导出调用系统文件保存选择器，按章节顺序复制音频，文件名使用四位序号和清理后的章节标题。
- 完成后报告成功/失败数，取消选择不报错；沙箱原件继续保留，文件管理中得到副本。
- 文件导入页支持音频、TXT/EPUB/MOBI/CBA/PDF/HTML/HTM 与 ZIP，可设置书籍信息与封面。

系统文件管理器“使用简听阅读打开”：JSON 自动进入书源导入；TXT/EPUB/MOBI/CBA/PDF/HTML/HTM 和 ZIP 自动进入本地导入页并带入文件、预览书名/作者/封面，点击“开始导入”入架，无需再次选文件。优先按文件后缀分流，无后缀 URI 使用 MIME/UTD 类型；冷启动和应用已运行时均支持，保留原始授权 URI，文件打开不触发启动自动播放。压缩包支持 ZIP 书籍集合和 CBA（ACE）漫画。

本地导入页移除顶部大块文件选择区，右下角悬浮“＋”用于首次选择与继续添加，底部固定“开始导入”；说明移至右上角圆圈感叹号，默认收起。单文件将封面、书名和作者编辑整合为一张卡片；多文件按“左封面、右书名／作者／原文件名／格式”逐条展示，支持单独移除，无封面使用各自书名和作者生成占位。列表使用 LazyForEach 与 URI 稳定键，当前容器宽度达到 AdaptiveLayout.MEDIUM_WIDTH 时并排两列，所有配置随同一列表滚动，末尾留出悬浮按钮空间。批量电子书独立使用各自元数据，不套用之前单本编辑的作者和封面；纯音频仍提供合并后的书籍信息。悬浮加号与书源页统一复用 ImmersiveCircleButton：52vp 圆形沉浸材质、25fp 主题色加号，不叠加额外底色；文件解析与导入期间禁用并降低透明度。分组、格式标签和编辑文字使用系统中性前景色；开始导入使用系统前景色作底、系统卡片背景色作字，随深浅模式反转，不取主题强调色。

2026-11-06 导入布局验证：Release SDK 26.0.0.105 的 Debug HAP 构建通过，包内 Release / API 20–26；本地导入服务定向回归通过。手机模拟器确认悬浮加号点击、连续添加三本 TXT 后独立封面／作者信息、移除一项及单本编辑，浅色黑底浅字、深色浅底黑字均已截图核对。独立 ArkTS 检查因 LSP 未初始化不可用，MCP 构建遇到 OHPM 批处理递归错误，实际使用 Release IDE Node/Hvigor --no-daemon 编译；平板双列、真机与批量内嵌封面本轮未做视觉验收。实现参考在线 [ArkTS 语法技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[ArkUI 检索技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md)、[List 多列布局](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/03-layout/grid-list/ts-container-list.md)及 [V2 属性观测](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/02-state-management/v2/arkts-new-observedV2-and-trace.md)，未运行在线检索脚本。


## 系统备份与跨设备续播

- 系统备份使用 `files/backup/listenbook_state.json` 白名单，包含在线收藏、阅听历史、阅读与播放进度、常规阅读设置、朗读进度与设置、跳过设置、统计、在线书元数据、通用设置和清洗后的书源定义。
- 在线书签、全局与在线书替换规则纳入阅读快照；旧备份没有这些字段时保留当前数据。本地导入书的书签与规则留在本机，恢复备份时保留。实际账号会话、Cookie、敏感 Header Token、原始书源 JSON、卡片 ID、缓存音频、下载、本地导入路径不进入快照。
- 清洗后的 `jsLib`、变量和登录规则定义可随来源迁移，恢复后状态回到“待测试”。
- 跨设备续播传递当前在线书、章节、原始章节地址、进度、时长、倍速和播放状态；目标设备先恢复当前章节，再补齐完整目录。

## 主题与加载

- 书源管理、成就馆、主题、日志管理、关于与设置页统一使用 `AppTheme.SettingsBackground` 作为整页及路由外层底色，卡片使用 `AppTheme.Surface`，文字、分割线和品牌按钮前景使用对应主题语义色。书源页顶部搜索/筛选、展开操作区、页内管理视图及导入弹层，以及主题图标面板与套装预览弹层同样接入主题色；应用套装后通过现有 V2 外观状态即时刷新。设置、阅听设置及其五个子页、书源管理、成就馆、主题、日志管理和关于共用 `FrostedPageHeader`：标题栏叠在滚动容器上方，通过实测高度提供首屏内容留白，滚动内容可进入标题栏背后。组件统一使用背景模糊与 72% 不透明度的主题底色叠层，透明度只影响底色，文字保持清晰；背景装饰不参与触摸，返回与操作控件保留点击，主题胶囊的 HDS 材质、阴影裁剪和触摸透传保持原有实现。关于页支持纵向滚动，日志控制区与懒加载条目在同一列表内滚动。验收包含滚动透出、返回、标题栏操作、主题切换及加载/空态。实现参照在线 [ArkUI 开发规范](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-develop-skill/SKILL.md)、[ArkTS 语法规范](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)和[设备验证技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-studio-verify/SKILL.md)。
- “我的 → 主题”分为“主题图标 / 主题套装 / Tab 图标”三个顶部 Tab，使用书架同款原生 `CapsuleSegmentButtonV2` 和描边；NavDestination 内由 `HdsTabs` 承载沉浸光感材质，并按实际高度半径进行离屏圆角裁剪，保留透视且不外溢阴影。材质层整棵子树不参与触摸命中，分段按钮负责切换。顶部“主题”标题栏使用原生磨砂并叠在滚动内容上方，卡片经过标题区域时柔化透出；胶囊标签栏没有整条不透明底板，卡片上滑后从标签后方透出。描边装饰整棵子树使用 BLOCK_DESCENDANTS 透传，避免透明子节点挡住原生按钮点击。点击与左右滑动同步选中项，各页保留独立滚动区域；标签按内容自适应高度，圆角、描边和首屏留白跟随实际高度，旧系统沿用能力守卫和薄磨砂回退。默认显示主题图标，保留图标选择和会员校验；图标卡片的名称下统一保留一行说明，首个图标显示“默认图标”，其余显示会员说明，字号与行数一致，保持卡片等高；主题套装内置“默认套装”、“纸感书房”、“雾蓝”和“墨山”，展示背景、封面和图标的局部预览。套装缩略卡固定每行三张，点击打开可滚动预览面板，展示背景、封面和图标；关闭预览不修改全局，点击“应用套装”后保存并更新现有界面。显示当前使用标记，应用期间禁用重复操作，失败提示重试。
- 标签栏实现已读取在线 [ArkTS 语法技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[ArkUI 检索技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md)及其 [SegmentButtonV2](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/04-components/advanced/ohos-arkui-advanced-SegmentButtonV2.md)、[Stack](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/03-layout/other/ts-container-stack.md)、[Tabs](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/03-layout/other/ts-container-tabs.md)参考，并核对 [HdsTabs 官方参考](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdstabs)和本机 Release SDK 声明。在线目录已刷新，未运行知识库检索脚本。
- 2026-11-07：Release SDK 26.0.0.105 的 Debug HAP 构建并安装到连接手机，包内标记 Release / API 20–26。实机确认三个页签点击切换及内容上滑；滚动截图确认胶囊后方内容经 HDS 柔化，顶部标题采用独立原生磨砂。独立 ArkTS 检查因 LSP 未初始化不可用，MCP 构建遇到 OHPM 批处理递归，实际使用 Release IDE Node/Hvigor `--no-daemon` 完成编译。深色、大字体、旧 API 回退及其他设备未做实机覆盖。触摸透传依据已读取的 [ArkUI 事件响应规则](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/18-arkts-rules/arkts-interaction-rules.md)和本机 `HitTestMode` 声明。
- 主题背景：墨山六张图片分为浅深各三张：首页及“我的”使用留白山水，书架及详情使用山水孤舟，记录使用墨竹溪石；随深浅模式选择对应资源，保留原图清晰度。详情加载和失败状态也显示书架背景；默认主题继续使用封面氛围。首页骨架仅封面、文字等局部占位着色，外层透明，不覆盖主题背景。播放页封面保留细边框，不叠加书脊（含真实封面及默认占位）。
- “我的”账号卡及各组选项卡的主题底色使用 55% 不透明度，透出页面背景；透明度仅作用于底色，文字、图标、按钮和分隔线保持原有清晰度。
- 纸感书房使用暖纸/深炭纸背景、墨绿主题色和统一细线图标，覆盖书源首页、全网榜单及主要页面底色、表面和前景。默认封面与本地无图书籍使用对应主题素材；真实书封及用户自选封面保留原图，书封框内增加细书脊和边框，紧凑封面采用细边框，不拦截点击或遮盖状态标记。首页搜索、筛选、视图切换、箭头、分类及底部导航通过功能角色选择图标。
- 墨山使用宣纸白/墨灰配色和朱砂强调色，山水背景、山水普通封面与墨竹本地封面均提供深浅变体；10 个单色矢量图标采用微不规则笔触，保留小尺寸识别性。普通书封叠加细书脊和边框，紧凑封面仅保留细边框，文字实时排版，真实书封沿用原图。
- 雾蓝使用浅冷灰蓝/深蓝灰背景、适配深浅色的蓝色强调色、线性功能图标与细书脊、边框；真实书封保留原图。首页、书架、记录、我的共用主题背景组件，书架不再单独绘制旧渐变。预览与正式页面共用强类型主题定义，新增套装在 ThemeBundles 注册一次，页面按背景、图标和封面能力呈现，不判断具体套装名称。
- 应用套装采用推荐主题色和材质，仍可在系统设置单独调整；有调整时显示“已自定义”，提供“恢复套装推荐外观”和“恢复默认套装”。浅色/深色/跟随系统、阅读纸张配色和桌面应用图标分别保存。套装使用 `app_theme_preferences` 单记录保存当前 `themeBundleId/accentColor/materialStyle`，兼容旧颜色和材质偏好，系统设置备份包含 `themeSelection`。未选择或读取未知套装时回退默认外观。
- 书源导入成功提示明确包含“导入或更新”。所有用户均可不限数量导入，按书源地址更新已有定义，写入失败时整批回滚；已有 68 条时也可继续新增第 69 条。
- 书源导入、新增和更新不查询会员权益，未登录、非会员或会员核验失败均不阻止导入。文件大小、批次内存预算及锁定书源保护继续生效。

- 主题读取 `AppColor` / `AppMaterial`，不在页面复制品牌值；V2 共享外观状态驱动主题色与材质切换。默认主题色为玫瑰红，浅深色 `app_brand` 均为 `#C4475B`；首次进入及未保存自定义色时，选色面板选中“玫瑰红”，原橙色保留为可选预设，已保存的其他主题色不变。
- 所有新增或修改的 `LoadingProgress` 显式设置 `.color(AppColor.Brand)`。
- 交互浮层使用 `AppMaterial.InteractiveThin`，播放页原生半模态弹层使用 `AppMaterial.PlayerSheet`；实际材质效果由设备系统决定。
- 首页入口和搜索输入使用透明原生沉浸光感材质，选中文字与下划线使用主题色。

- 详情页点击总集数，在原章节区域切换原列表与“1–40 / 41–80 …”横向分段标签加双列卡片，再次点击切回，不打开新页面或弹层。书籍信息中的集数与目录头部总集数使用同一切换状态，搜索词和排序保持生效。听书与阅读章节弹层默认显示列表，点击总集数切换分段目录，搜索覆盖全书；分段目录同时定位当前章所在分段和具体章节，高亮当前章，点章直接播放或跳转阅读。
- 设置页的预缓存下拉选项、0–50 章输入框和应用按钮在同一行，按比例分配宽度以加宽输入框和按钮，保留范围校验及 0 关闭预缓存的行为。
- 音频预缓存可输入 0–50 章，并按实际目录剩余章节裁剪。开启后当前章开始播放且未缓冲时，先解析并下载播放方向上紧邻的下一章，再保存当前章供回听，随后从近到远串行预取其余章节；回听优先复用完整文件，文件尚未完成时复用有效音频地址，避免重复解析书源。0 会取消在途下载并使旧解析失效；手动暂停、系统卡片暂停和定时结束只停止出声，当前章及已配置窗口的预缓存继续完成；暂停时补齐同一窗口，完成后不再扩展。下载队列独立持有 dataTransfer，与手动下载分别登记，成功/失败收尾后各自释放。实际播放发生缓冲时仍暂停预取让出带宽，暂停后的迟到缓冲事件不取消下载。退出播放服务、清理缓存、关闭预缓存仍会取消任务。切章不等待整章下载，未完成文件立即取消重复下载并交给播放器拉流；如果目标章正在预解析，保留嗅探并复用同一解析及请求头，失败再走前台解析。后台目录准备与解析受书源超时预算约束（默认 15 秒），超时后队列继续，迟到结果不写回。电子书阅读与朗读共用全局 0–50 章预加载设置，按正文顺序串行预取后续章节并写入原正文缓存；0 不追加预取，换章/离页取消旧队列，单章失败不阻塞其余章节。当前章节按需读取与连续滚动所需正文不受关闭预加载影响。
- 2026-10-07 预缓存实机验证：VYG-AL00 / API 26，Release SDK 26.0.0.105 Debug HAP，275听书《灵境行者》。日志确认落盘顺序为第 2 → 1 → 3 集；第 1→2 集、2→1 集、2→3 集从 chapter-load 到 playing 分别为 70 / 64 / 62 ms（完整文件命中，单次样本，不是旧版对照或声学延迟测量）。连续切集正常，返回第 1 集恢复 96.806 秒；第 3 集暂停 33 秒后从 31.318 秒恢复。单章下载完成 1/1（3.4 MB）；导出系统选择器可打开，未保存文件，取消时存在误报失败的提示，不能据此声明导出文件验收通过。模拟器完成搜索/详情，实机本轮通过首页推荐进入详情与播放。主机预缓存 14 组、音频命令 33 项通过。本次仅验证手机，未验证手表。技术参考：[ArkTS 语法](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[媒体能力指南](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/kits_media/SKILL.md)。
- 听书来源规则使用 `custom` 参数时，播放页顶部显示声波图标作为音色入口，不显示文字标签，无障碍名称保留“音色”。支持输入源提供的音色代码、留空恢复默认、按书记忆并从当前进度重载；清理本书临时缓存，保留已下载音频。返回键先关闭音色弹层。无此参数的来源不显示入口。
- 定时生效后，播放器按钮显示剩余时长或章数；点击遮罩仅收起，不重复弹出。

## 回归清单

书源首页在顶部频道栏“综合”左侧固定显示当前模式和下拉箭头，点击直接展开按模式、频道分组的菜单，无需打开“分类”面板；入口使用与右上角“全网榜单”相同的 InteractiveClean 沉浸材质，弹层复用 Sheet 系统材质和旧 API 模糊回退，选中对勾固定在选项右侧；原生源选项来自 `vars[].filter`，兼容源复用发现筛选项。右侧频道保持横向滚动，只有筛选项而没有多个分组时也保留此行；下方“分类”面板仅展示具体分类。选项名称、顺序和值保持书源定义，不将小说／听书／漫画写死，也不展示服务器、Token 等设置。选择后沿用书源设置保存入口，失效首页缓存、清空旧书单并刷新动态分类；保存失败恢复选中值。验证模式 → 频道 → 具体分类切换及重启恢复，并确认普通无筛选书源仍可使用原分类总览。

左上角分类下拉提供与右上角书源菜单一致的搜索、单列／双列切换和筛选按钮。布局复用首页源菜单列数偏好，一列目标宽 248vp、两列目标宽 640vp，受实际容器安全宽度限制；列表按结果数量收缩并在超出最大高度时滚动，使用稳定选项标识懒加载。搜索匹配选项名称、控件标题和书源分组，忽略英文大小写及首尾空白；分组筛选优先使用书源的 `group`，缺失时使用控件标题，按原顺序去重，提供“全部分组”，并与搜索取交集。每项保留所属控件标题，防止不同分类下同名选项混淆，选择仍提交原始 `optionValues`；每次打开清空搜索和分组，换源清空旧菜单。分类定义就绪后即可打开和选择，无需等待推荐书单完成，仅保存期间防止重复提交。回归覆盖搜索空态、搜索＋分组、单／双列切换、重复名称对应的保存值、加载中切换和失败回滚。

本轮实现参考已读取的在线 `lang-syntax`、`hmos-arkui-knowledge-retriever` 和 `hmos-arkts-syntax-checker` 技能，保留项目 ArkUI V2、API 20 回退与现有书源保存链路。来源：`https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md`、`https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/18-arkts-rules/arkts-ui-extension.md`、`https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-syntax-checker/SKILL.md`。

2026-11-06 验证：`HomePage.ets` ArkTS 检查无错误，`scripts/test-home-channels.cjs` 定向回归通过；Release SDK 26.0.0.105 Debug HAP 构建成功，包元数据为 min API 20 / target API 26 / apiReleaseType Release。已安装至平板模拟器，确认横屏分栏下单列／双列宽度、选中对勾、书源“首页”分组筛选与输入“女”后只显示“女频首页”，弹层高度随结果收缩。模拟器期间有其他页面操作，选项切换后的刷新及右侧书源菜单未完成本轮设备复核；多分组组合、重复名称、加载中切换与失败回滚由定向回归覆盖。本轮未验收实机、软键盘遮挡和完整首页滚动回归。

1. 无导入源时首页、搜索推荐和管理页显示相应空态；首页顶部选择发现源，只出现已启用且具备发现内容的小说或有声书源。切换两个不同类型的发现源后，首页名称、推荐、分类同步改变，重启保留选择；分类入口固定在首位，默认选中精品推荐，精品推荐与源分类共同横向滚动。禁用或删除所选源后不保留其旧内容。
2. 首页首屏骨架、首板块三条横滑、后续封面和“更多”正常；轮播无底部书名及书名骨架，搜索、轮播、Tab 整体等距上移，Tab 吸顶前列表首行始终位于其下方；轮播经过顶部时逐渐模糊，无硬切底色或闪白，Tab 在展开与吸顶时均保留沉浸材质；静止及普通上滑没有 loading，下拉指示器只在分类 Tab 下方出现，成功和失败后均消失。
3. 搜索入口滚动折叠、分类吸顶，四个 Tab 双击只回顶；书源首页和全网榜单分类 Tab 按文字实际宽度加左右各 12vp 内边距布局，不设统一宽度或 176vp 上限，长名称可横滑完整查看。横向列表两侧保留 24vp 原生渐隐过渡，首尾标签到达边界后完整显示；分类条不使用绘制缓存，胶囊保留沉浸材质和点击反馈，文字不随背景反色，材质容器不参与隐式尺寸动画。固定“分类”与折叠后的搜索按钮保持清晰，检查快速上下滑动、连续吸顶/回顶、横向切换及窄屏大字体下无异常变黑、残影或重叠。
4. 搜索历史最多 20 条、重复词前移、标签无 ×、点击搜索/清空正常；推荐来自真实书籍，没有来源时不显示虚构推荐。
5. 连续提交不同关键词不会混入旧结果；类型计数、网格/列表切换、来源去重和单源失败隔离正常。
6. 书架电子书直接恢复阅读；阅听记录主页与未收藏记录分开显示，阅读与收听混合排序，编辑、长按、全选、取消、确认删除及继续阅读/播放正常。
7. 书卡进出详情转场连续；窗口变化或源卡不可见时降级，无源卡入口也能正常进出。
8. 播放、暂停、拖动、切章和续播正常；两处封面静止，迷你进度圆环在换集后更新。播放错误后点击播放可重新加载并恢复当前位置，已解析地址自动重试同样保留位置；手动暂停不得被重试或迟到的焦点事件覆盖。
9. 倍速、跳过、章节和定时弹层可操作；验证时长/章节预设点选即生效、自定义键盘完成提交、非法值不替换已有设置、页签切换不改设置及长按取消。章节停止验证多章计数、片尾跳过、循环优先级、手动切章取消、暂停保留及停止后继续下一章；智能定时验证剩余不足 10 分钟、超限、暂停状态、取消等待及开关不重置倒计时。
10. 系统卡片倍速、上下集、收藏与 App 同步；在线 URL 投播连接后恢复进度并暂停本机。
11. 在线系统缓存、主动下载和本地导入分别可用；多章导出顺序正确，取消选择无错误，导出文件可打开。
12. 在线小说各段首行缩进两字，首章首屏和跨页新段落均保留缩进，同段跨页续行不重复缩进；单换行、连续换行及空白段落的书源显示间距一致，不产生额外空白行。跨章、退出重进及已有进度恢复正常，改变字号、行高和窗口尺寸后位置合理，章节定位与预取正常。
13. 阅读工具栏和弹层不遮挡正文；小窗冷启动、全屏切换、深浅色状态栏与安全区正常。底部 Tab 依次为目录、设置、字体；上方独立章节条参照轻页 ReadBook 的单项 HdsTabs，实现左右箭头与 30vp 粗滑条，API 20–22 回退普通圆角栏。拖动时显示章节标题及全书百分比，松手直接跳转，不再弹确认框；沉浸胶囊提示中的系统撤销按钮恢复本轮连续拖动前的章节与原文字符位置，工具栏收起或切换目录/设置后清除提示。提示条占有实际布局区域，按钮点击不能穿透正文。撤销提示沿用阅读底栏的 HDS 沉浸材质、胶囊圆角与离屏裁剪，仅显示系统 undo 符号及独立圆形触区，不显示“撤销”文字，保留无障碍名称。章节条遵循当前目录排序，首尾章及加载期间禁用不可用的操作。箭头切章和滑条跳转后保持工具栏显示；正文翻页或手动收起时再隐藏。回归检查拖动取消、连续跳转与撤销、首尾章、倒序目录、窄窗口和深浅主题。阅读加载圈为 48vp；圈下方“正在加载正文”和章节提示统一为 16sp，并与实际背景做差值反色，自定义图片背景需实机检查。
14. 阅读设置预览与正文同步，退出重进保持配置；失效背景图降级，恢复默认正常。正文四边边距滑杆等长；在线正文顶部状态栏与标题区域不响应点击或起始于该区域的滑动翻页，下拉状态栏及取消手势不提交翻页，其他区域翻页正常。
15. 本地 JSON、粘贴 JSON、HTTP(S) 导入成功；重导、名称/地址/分组检索、听书排序和空结果正常。
16. 单源测试和批量搜索测试展示不同验证范围；批量失败保留来源和启用状态，其他任务继续完成。
17. 测试状态和能力提示不错误锁死开关；禁用后收藏可解析，删除后明确报错而不闪退。
18. 批量启停与删除只作用于选中来源；确认删除后会话和 Cookie 清理，同 URL 重导不复活已删凭据。
19. 带 Header、Cookie、变量、紧凑规则和 QuickJS 的来源完成搜索到阅读/播放；脚本超时不阻断其他来源。
20. 系统恢复仅还原白名单，来源待测试；敏感会话与本地文件不迁移。两台设备间续播恢复章节、位置、倍速和播放状态。
21. 全部加载圈使用品牌色；播放器、详情、设置在小窗与紧凑尺寸下可完整访问。
22. 书源编辑与调试的标题、页签和操作按钮不重叠；类型切换立即生效，键盘弹出后可访问表单底部，返回时的保存/放弃/取消行为正确；调试长日志和结果可滚动复制，导出 JSON 可保存和取消。
23. 多组来源可分别被每个分组筛选；改名或删掉其中一组保留其他组，锁定源分组不变。名称/日期排序后执行置底能切回自定义顺序，重进仍保持结果。
24. 搜索关闭、发现启用的来源可完成发现到正文校验；空发现和只有付费章节不报成功，取消未完成批次保留旧测试状态。证书例外只作用于确认的精确 HTTPS 主机，撤销后恢复严格校验。
25. 等待式网页登录与 `showBrowser` 可完成并恢复原脚本；返回、取消、超时不会留下等待任务或占用网页会话。宽松 JSON 非执行性、会话 helper 状态隔离和 DES/3DES 协议向量通过对应规则测试验证，不以接口存在代替实测结论。
26. 空书架与不足一屏的网格/列表，在全部、有声书、电子书筛选下上下拖动均有边界反馈；首页、记录和搜索空态同样检查。主 Tab 首尾左右越界后回位，书架下拉仅回弹，顶部刷新入口及长按操作正常，首页进入搜索和返回保持原生左右转场。动效需通过真机连续画面或录屏判定，静态截图不能替代。


## 播放停播诊断

- 长时间使用后偶发退出：先在“我的 → 日志管理”开启“记录日志”，退出后重开并复制日志。`app.lastExit` 保存系统上次退出原因与脱敏说明，可辅助区分 JS 错误、原生崩溃、卡死及资源管控；`app.memory` 保存内存告警级别、运行秒数和前后台。系统可能返回未知原因，仍需结合故障文件判断；默认关闭、不上传，不拦截异常或强行恢复播放。

- 复现后尽快读取设备 hilog，保留停止前后完整时间段：`ListenBook_Audio`、`ListenBook_BgTask`、`ListenBook_ExtMedia`。日志属于系统缓冲区，可能被覆盖，不是应用内永久保存的诊断文件。
- `playback event=` 包含播放器状态、前后台、播放位置、加载代次、暂停来源、焦点/定时标记及后台任务运行状态；同时记录状态变化原因、错误码、缓冲开始/结束。前后台标记不等同于物理屏幕亮灭状态。
- 暂停来源为 `user`、`avsession`、`widget`、`output-device-unavailable`、`cast` 或 `speech`；定时停止单独记录 `sleep-stop`。AVSession 命令不区分锁屏控件与耳机按键，需结合系统日志判断。
- 后台任务记录申请、主动停止、系统取消/挂起/恢复和重新申请结果；外部音频监测记录启用、超时及恢复请求。诊断不强制恢复未知原因的暂停。

## 电子书朗读

- “听”字字号为 22fp，48vp 圆形入口距底部安全区 86vp；点击直接起播并进入通用播放页，不再提供长按设置入口，TTS 导入与管理从“我的 → 阅听设置”进入；朗读显示迁到其中的独立页面，提供跟随翻页、朗读标记及其自定义颜色，阅读页原快捷入口跳转阅听设置。朗读引擎选择胶囊使用适配深浅模式的实体底色、细边框和轻投影。

- 在线小说阅读页提供右侧独立“听”字沉浸圆形悬浮入口（文字随系统深浅模式适配，原生材质容器不叠加背景/边框覆盖，旧系统回退背景与边框同步适配；不占底栏 Tab，随底栏同步显隐）。首次点击从当前页起读；同书正在朗读时直接进入播放页，暂停时从当前朗读片段继续。“我的 → 阅听设置”独立页面保留引擎、音色查询/下载及自定义 TTS 导入管理，不显示播放、从当前页起读、上次续读、切章或结束朗读操作；通过统一菜单路由进入独立页面，顶部返回按钮回到“我的”。“对话高亮”与“朗读显示”使用并列卡片入口；对话高亮开关、颜色调色盘、HEX 输入、预览及跟随阅读主题开关统一放在“对话高亮”独立页面内，分页和滚动正文共用持久颜色。未选择自定义色时默认跟随当前 App 主题强调色，并解析主题套装和深浅色资源。设置页移除音量增幅，正文移除段落悬浮展示入口和宿主。“朗读显示”将跟随翻页放在标记选项上方；“更改颜色”模式下直接显示调色盘与 HEX 输入，颜色行右侧提供与对话颜色一致的“跟随阅读主题”开关。朗读标记颜色独立于对话颜色保存，分页与滚动共用，纳入阅读备份，旧配置保持主题强调色。
- 本地导入书籍未提供封面时，书架、播放页、阅读记录和底部迷你播放器共用宣纸花边占位封面，书名和作者横向排列并保持上下留白。桌面播放卡片和系统媒体面板使用同款底图生成的带书名、作者图片，经原有图片通道同步；修改书名或作者会重新生成，已有封面优先显示。生成图仅存于有界缓存，不写入用户封面字段；切书期间的旧封面结果不得覆盖新书。
- TTS 和有声书使用同一个播放页与 `MiniPlayer`，共用封面、书名、章节、暂停/继续、上下章、倍速、定时和目录界面。播放页的声波图标打开音色面板，TTS 模式可选择系统中文音色或已导入的自定义 TTS，支持导入、粘贴及删除；有声书音色按钮沿用首页右上角书源入口的右下锚定浮层（圆角、原生材质与旧系统磨砂回退），不使用底部弹框。浮层展示书源声明的音色名称，打开时自动定位到当前音色（非默认项尽量居中），选中项高亮带勾，长列表保留滑动但隐藏滚动条，点选收起并保存、按当前进度重新加载，不再输入代码或另点保存。首项可恢复书源默认；选择仅作用于当前书籍，清除本书预加载缓存，显式下载保留原音色。没有声明音色列表且没有旧音色设置时不显示入口。TTS 的定时提供 15/30/60 分钟和本章结束停止，原跳过片头片尾位置显示结束朗读；中文音色下载成功即时更新为“已选择”。
- 暂停后从当前句开头继续。切换语速和音色保留位置；加载失败停在当前章，播放按钮可重试，不自动跳过失败章节。
- 阅读正文高亮当前朗读自然段，朗读推进到下一页或下一章时自动跟随；用户确认翻页后朗读跳至新页，连续滚动停止后跳至可见内容。跳转中的旧回调和落在上一页的句首不能将新页拉回。暂停状态翻页不自动恢复。
- 离开播放页继续朗读，统一迷你栏显示当前书籍、章节和本章进度，支持暂停/继续、下一章、点击展开及上拖进入同一个播放页；锁屏和耳机支持播放/暂停与上下章。
- 系统没有精确音频时长，TTS 在播放页和迷你栏显示只读的本章字符进度，不提供时间拖动；前后跳转按朗读片段处理。不生成音频下载/导出文件。
- 回归：我的 → 阅读设置 → 导入与管理 → 返回阅读页点击“听”并进入通用播放页 → 暂停/续读 → 切换系统/自定义音色 → 倍速/目录/跨章 → 定时/本章结束停止 → 返回首页统一迷你栏 → 暂停/下一章/点击及上拖展开 → 锁屏/耳机控制 → 音频与朗读互斥 → 重启恢复。断网验证已缓存章节；缺少正文时应明确报错。

## 阅读与导入补充交互

- 详情目录支持正序/倒序，与关键词筛选组合使用；偏好按书持久化，仅影响详情/播放/阅读目录的展示和选章定位。音频、朗读、小说和漫画的上下章、自动续播、预加载及后续章节下载始终按正文顺序进行，例如倒序目录中第 10 章的下一章仍是第 11 章。无历史进度时从正文首章开始，列表循环回到正文首章；章节标识和原始阅读索引保持稳定，切换目录顺序不重置当前进度。
- 阅读目录的标题行、搜索框位置、40vp 高度、圆角及灰色背景与播放目录一致，支持章节标题搜索、无结果提示；章节项仅展示原始标题，不在标题下另列目录位置编号，保留当前章高亮和缓存状态。“回到当前章节”会清除筛选后定位。阅读页进入已有的同书详情时返回原详情，避免“详情→阅读→详情→阅读”重复压栈。
- 阅读底栏复用首页官方 HdsTabs：目录、设置、字体仅显示图标，保留无障碍名称；文字书籍的“听”按钮并排放在底栏右侧，与图标栏间隔 8vp，整组左右边缘与上方章节进度栏对齐。底栏与章节栏一样按圆角裁剪材质，不保留落在正文上的外投影；调整布局时须保留此裁剪。点击“听”打开朗读播放页，长按不再进入设置，与底栏同步显隐。API 23 起启用浮动栏及自适应系统材质，API 20–22 使用官方固定底栏回退；独立于正文布局，使用 180ms 位移/透明度收起；不调用 HDS 折叠动画，不通过切换底栏高度触发正文重排。
- 播放页头尾设置立即更新当前播放：例如 2 秒设片头 10 秒立刻跳至 10 秒，11 秒设片头 10 秒不回退；暂停时调整片头保持暂停，加载时更新待跳转位置，播放中已进入新片尾区则立即执行章节结束策略。
- 小说新增上下滑动翻页，复用前后章预加载、边界判断、翻页完成提交进度和取消回弹逻辑。
- 阅读设置增加“跟随系统深浅色”；开启后深色临时使用夜间主题，回到浅色恢复已选图片（含蒙层）或白天主题；已选夜间/纯黑主题的浅色回退为羊皮纸，手动选主题或保存自定义主题退出自动模式并提示，打开编辑与取消不影响自动模式；选中标记始终对应当前实际主题。后台返回和系统配置变化时同步颜色，不改变全 App 外观设置。
- 正文默认左右各 16vp，使用两端对齐；设置可分别调整上下左右 0–64vp。边距参与分页计算，重排按字符位置恢复，保存至 text_reading_settings。
- 书源管理点击“导入”展开面板并回到列表顶部。系统文件应用打开 JSON 可选择简听阅读导入；冷启动与已运行入口复用文件读取、大小限制、解析、锁定源保护和导入结果提示。
- 加密 rule_sources.db 增加 rule_source_login_status，保存登录校验结果。书源列表显示“已登录 / 登录已过期 / 已保存，待验证 / 未登录”；重新登录覆盖过期状态，退出登录清除有效标记，删除书源同步删除记录。网页登录保存失败不显示成功，登录校验读取有大小限制的页面快照。
- 过期以书源校验失败或服务端明确鉴权失败为依据；通用 Cookie 未提供有效期或校验规则时显示“已保存，待验证”，不推测过期时间。网络失败和普通限流不标记过期。
- 定向回归脚本：`DEVECO_HOME=<DevEco 安装目录> node scripts/test-reader-preferences.cjs`，覆盖旧偏好迁移、四边边距/上下翻页/自动配色持久化、非法值和恢复默认。

本轮验证：Release SDK（26.0.0.105）Debug HAP 构建成功，包内 apiReleaseType=Release、最低 API 20、目标 API 24；阅读偏好定向回归通过，API 26 真机安装启动成功。自动 UI 验证服务缺少配置，未完成自动交互回归；HarmonyOS 6 的动态闪烁、系统 JSON 打开方式和真实书源会话过期仍需对应设备/账号验证。

技术参考：[ArkTS 语法规则](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[ArkUI 指引](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md)、[编译诊断指引](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-syntax-checker/SKILL.md)。系统深浅色读取接口 uiAppearance.getDarkMode 的 API 20 标注已按安装的 Release SDK 核对。

### 阅读菜单、书签与替换净化规则

- 呼出阅读工具栏后，右上角“详情”独立位于四宫格左侧；点击四宫格打开添加书签、书签、替换净化规则菜单。设置仅保留底部入口。本地与在线电子书共用入口。菜单显隐采用显式状态和关闭回调，避免 bindMenu 编译后残留未定义的 $$this，导致呼出工具栏时闪退。
- “添加书签”记录当前章节和阅读位置，重复位置不重复添加；书签列表显示章节及正文预览，可点击跳回或删除，重启保留。目录重排后按章节身份定位；原章节已不存在时提示失效。EPUB 原版通过片段文字定位映射到同一章节字符坐标。
- 替换净化规则支持普通文字或正则，替换为空即删除匹配内容，可选择仅本书或全部书籍。支持新增、编辑、启停、删除和当前章预览，保存后重新排版，目录标题保持原样。弹层标题行在右侧预留 56vp 给系统关闭按钮，“新增”与关闭按钮各占独立区域，编辑状态标题也避让关闭按钮。新增、编辑、删除复用项目现有的系统原生文字按钮（ButtonStyleMode.TEXTUAL），无实心底色，保留系统尺寸、按压和禁用反馈。按钮及规则开关统一使用随系统深浅色适配的黑白中性色，书签删除图标同样使用中性色。统一文字阅读分支与朗读使用同一替换结果，EPUB 原版主题显示原始正文。
- 规则不覆盖原文；关闭规则恢复原文，阅读进度与书签按原文位置保存，改变规则长度后仍能恢复相同位置。修改规则会停止当前书的朗读，之后可从阅读位置重新起读。执行失败提示并回退原文；预览不保存草稿。
- 回归检查：添加/去重/跨章跳转/删除书签及重启恢复；单书与全局规则、捕获组替换、删除文字、失效正则、启停及预览；修改规则后阅读/朗读原文位置恢复；字体与窗口变化后位置稳定；本地/云备份恢复以及旧备份兼容。菜单和弹层打开时，音量键与键盘不触发正文翻页。

2026-10-21 阅读功能验证：分组排序保存、原目录解析（含 2200 章 EPUB）、书签/规则、阅读位置与分页、32 项朗读和备份回归通过。Release SDK 26.0.0.105 的 release HAP 构建及包内 Release/API 20–26/动态导出名检查通过。后续 Mate 80 实机复现并修复点击正文的 ReferenceError：原 bindMenu 调用中的 $$this 被原样留在编译产物中。已用用户导入的大书验证正文呼出/隐藏工具栏、菜单关闭再打开、书签与规则弹层、独立详情入口、规则新增及系统关闭按钮；返回书架后恢复相同章节与页内位置，未新增崩溃记录。布局记录确认规则“新增”按钮与关闭按钮相隔 84px，点击各自生效。分组拖动手势、跨设备窗口变化和规则全部编辑组合仍未完成设备覆盖。拖动与懒加载在线详情文档返回 403，使用已安装 Release SDK 核对 onMove 的 API 兼容性。

闪退定位参考已读取的 [ReferenceError 故障模式](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/06-solutions/stability/hmos-runtime-fix-skill/references/fault-mode-library.md) 和 [ArkUI Builder 约束](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/18-arkts-rules/arkts-ui-extension.md)，并对照设备 faultlog、Release 编译产物及安装 SDK 的 bindMenu/onDisappear 声明确认。

新增、编辑、删除的原生文字按钮已通过同一 Release SDK 构建与包校验，并覆盖安装到 Mate 80；实机截图确认黑白无底色和关闭按钮避让，新增及编辑入口、取消返回均正常。在线 Button 详细文档返回 403，样式及 API 11 起可用的兼容性依据项目既有用法和安装 SDK 的 `button.d.ts` 核对。

### 本地电子书及大包导入

- 文件选择支持 TXT/EPUB/MOBI/CBA/PDF/HTML/HTM、6 种音频及 ZIP，每次最多 500 个，支持继续添加并按 URI 去重；文件清单懒加载。书名可留空，多本电子书分别命名入架。
- TXT 默认书名使用去掉扩展名的文件名，正文中的“书名”或书名号不覆盖它；作者仍可预识别，用户手动填写的书名优先。该规则作用于新导入，已有书籍可通过书籍编辑修改名称。
- ZIP 上限 32 GiB、解压内容 64 GiB，单书最多 50000 章/集；导入前校验空间，多包逐个处理。失败显示原因和已成功数量，不将部分失败显示为全部成功。
- TXT 上限 256 MiB，HTML 32 MiB，EPUB 3 GiB（解压 6 GiB，预览与正式导入一致）；HTML 提供文字阅读；新导入 EPUB 另外支持有界章节内嵌图片，图片独占固定高度页面，沿用目录搜索、排序、分页、阅读设置、进度恢复与朗读。
- EPUB/MOBI/CBA/PDF 导入支持“自动识别 / 电子书 / 漫画”，含 ZIP 内文件。EPUB/MOBI 自动识别采用全书图片/文字比例，封面和少量插图不作为漫画判定。EPUB 按 spine、MOBI 按 recindex 引用顺序保存正文图片，过滤纯文字页，进入现有漫画阅读器并复用章节/页进度。图片累计上限 6 GiB，单张仍为 20 MiB/32M 像素；漫画图片无法提取时整书失败并清理，不静默保存缺页内容。本地正文和图片保存在 filesDir/ebooks，刷新漫画或清理在线缓存不删除原件。
- CBA 使用后台原生 ACE 1/2 解码，支持固实压缩，按文件名数字自然排序图片，默认漫画；每 50 页一节、首图作为封面。包内路径只用于排序，落盘使用生成文件名；密码、分卷、损坏图片、CRC 失败或超限会明确提示并清理整书。最大 3 GiB 压缩包、50000 个头部、单个内容 20 MiB/图片 32MP、解压总计 6 GiB、解码最长 3 分钟。保留原文件，不上传内容。说明入口与离线使用教程同步展示格式边界。
- 漫画阅读页右上角使用与阅读页一致的功能按钮，“查看详情”收进菜单，移除外部详情按钮。本地导入漫画的菜单提供“切为阅读模式”，原书切换为电子书，保留目录、正文与记录，按当前图片恢复文字阅读页位置。扫描 PDF 仍展示图片，不提供 OCR 文字转换。
- 本地电子书阅读页右上角功能菜单提供“切换为漫画阅读”：直接更新原书类型，保留书籍 ID、目录、正文、收藏和记录，不重新导入或生成副本；已有图片直接用于漫画阅读，文字位置映射至对应图片，漫画模式跳过纯文字章节。没有已保存的可读图片时提示无法切换。详情页换源入口保持原样。
- 类型切换保存后刷新书架与阅读缓存，网格/列表书卡的更新标识包含内容类型，徽标和打开入口同步更新；旧文字页面重复切换已是漫画的书也成功。进度保存失败不阻止类型修改，类型已保存但跳转失败时提示返回书架打开，避免误报修改失败。定向回归：`scripts/test-local-comic-switch.cjs`、`scripts/test-local-book-import.cjs`。
- 目录优先保留书籍自己的标题：EPUB 读取原目录并匹配正文锚点（同一个正文文件也可分出多个目录项）；HTML/HTM 优先页内目录、其次正文标题；MOBI 优先 filepos 目录、其次标题/分页标记；TXT 沿用标题识别。ZIP 中电子书采用对应格式规则。没有可用目录或标题时才使用原分段方式。EPUB 按原目录/资源边界保留完整章节，不再按 32000 字生成“续”章；单章上限 8 Mi 字符，超限明确报错并回滚。有明确标题的 TXT 同样保留完整章节，64 KiB 流式解码跨块及长段落均不生成额外“续”章，单章超过 8 Mi 字符报错并回滚；无标题长文和其他格式沿用有界分段。旧导入记录需重新导入原文件才能更新目录，避免改变旧书签与进度的章节身份。
- 验证脚本：`node scripts/test-local-book-import.cjs`（需要 DEVECO_HOME），覆盖真实导入/存储代码的编码、流式分章、HTML、EPUB 适配、重启恢复、空间失败和清理；API 26 真机已通过 LocalBookImportDevice 的真实 EPUB 解析/正文落盘用例；超大包容量与鸿蒙 6 设备仍未完成实测。3 GiB EPUB 的主机回归通过模拟元数据覆盖容量边界、预览复用、空间不足及失败回滚，不代表真实 3 GiB 文件的解析速度或内存峰值已验证。
- EPUB 大书导入复用最近一次预览解析结果，无图正文分批在后台清洗，章节最多 4 路滚动写入；目录按正文资源路径建立索引，兼容空/重复章节标识。原始资源连续 3 节读取失败后，本书优先使用系统正文接口，每 128 节探测一次是否可恢复原始读取；正文接口异常或空文本时立即完整重试当前节，读取失败不跳章。含图章节继续保留图片处理，导入中退出页面时等任务收尾后释放预览文件。主机模拟 6226 节原始资源均不可用时，失败读取尝试由 12452 次降至 108 次，逐节内容、探测恢复和异常处理回归通过；这是调用次数对照，尚未重新测量用户 80 MB 原书的优化后总耗时。

2026-11-05 MOBI/CBA 验证：用户提供的《哆啦A夢大長篇全彩》卷 01 MOBI（101.52 MiB）提取 192 张正文图片，主机独立解析的引用顺序与逐张 SHA-256 均一致；本地导入和外部打开路由回归通过。CBA 原生解码在模拟器上通过 ACE1、ACE2、固实压缩、DELTA/EXE/PIC/SOUND 样例及损坏/截断/路径隔离检查。改动 ArkTS 检查无错误，Release SDK 26.0.0.105 Debug HAP 构建、包内双 ABI 原生库和许可证检查通过，已覆盖安装到 MatePad Pro 13 模拟器（2880×1920）。应用内确认 MOBI 预览、按钮中央点击导入、192 张图片入架、封面与连续阅读，退出后重开恢复第 2/192 章；标准 CBA 三色样例导入、页序、翻页及重开页进度通过。没有用户 CBA 样本，未完成真实大 CBA 压力测试或本轮真机验收；密码/分卷 CBA、加密/HUFF-CDIC/独立 KF8 MOBI 仍明确报不支持。设备验证按已读取的[DevEco 设备验证技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-studio-verify/SKILL.md)使用 hdc/uitest 完成，自动 UI 验证服务缺少配置。

2026-10-21 EPUB 性能验证：同一台 API 26 真机、同一份生成的 5000 章中文纯文字 EPUB（压缩约 2.95 MB，每章 80 段），正文转换优化前后，预览加导入总耗时从 476.467 秒降至 31.773 秒，约快 15 倍；其中优化后预览 0.609 秒、正式导入 31.164 秒。对照版本已经包含预览复用和写入优化；该结果不是用户原文件的实测值，图片、正文体积与设备会影响耗时。真实系统解析器的定向设备测试 1 项通过，校验 5000 章数量及首/中/末章节原目录标题和正文；本次未覆盖分组拖动、阅读菜单等 UI 交互。主机本地导入完整回归通过，新增覆盖预览释放、路径读取回退、清洗兼容、滚动并发及 5000 项空/重复目录标识；Release HAP 构建及包元数据检查通过。

复现时运行 `python scripts/create-epub-benchmark.py` 生成临时测试资源，构建设备测试包后单独运行 `LocalBookImportBenchmark`，用例超时设为 600000ms；未生成资源时该用例跳过测量，不能据此认为执行过性能测试。测试读取真实系统 EPUB 解析结果并在结束时清理自身数据，生成的二进制测试资源不纳入版本控制。当前完整设备测试入口引用已删除的旧书源实现，本次只临时隔离入口执行本地导入用例，随后恢复入口，未宣称完整设备套件通过。测量结束后已覆盖安装最终 Release 包并成功启动应用。并发实现参考已读取的 [ArkTS I/O 密集型任务指引](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-knowledge-retriever/docs/ArkTS-Language-Guide/04-Concurrency/io-intensive-task-development.md)，实际效果以以上设备测量为准。

此前版本验证（不覆盖本次书签、替换规则和拖动排序新增交互）：阅读/播放/排序及导入修改已通过静态检查；17 项音频回归、阅读偏好回归、本地导入回归通过。Release SDK 主包编译并安装启动成功；设备真实 EPUB 测试 1 项通过。自动 UI 验证服务缺少配置，未声称已覆盖全部界面交互。

- 连续滚动正文上下边缘采用与首页分类标签相同的 `fadingEdge`（36vp），仅在边缘逐渐透明，不对整层正文叠加渐变模糊滤镜。
- 本地文件选中后先预解析：EPUB 读取书名、作者和封面；TXT/HTML 读取头部可识别的标题、作者，无元数据时用文件名。单文件回填导入表单并允许手动编辑；批量电子书逐本预览并保留各自元数据。封面由自研解析器按 OPF 封面声明或封面页图片读取并解码，正式导入复制到书籍私有目录，退出清理预览临时文件。
- 阅读右侧“听”使用与另一个项目 `ImmersiveBackButton` 相同的 HDS 单项浮动栏材质与透明按钮组合，文字随系统深浅模式适配，随阅读底栏显示隐藏。

- 切换字体、字号或行高时，连续阅读保留已加载的相邻章节，按当前章节和字符位置重新定位；定位完成前忽略旧列表索引回调，避免回退上一章。
- 电子书详情与有声书采用相同打开顺序：先展示缓存基础信息，书源详情返回后更新资料，目录随后异步加载。目录加载和失败状态仅作用于章节区域，可原地重试，不遮住已有详情。

- 书架单本或批量选择删除本地文件时，同步清除对应书籍及旧别名的阅读、播放、朗读位置和阅听记录；仅移出书架保留上述记录。删除正在播放的书先停止播放，避免进度回写。

- TTS 管理的朗读引擎菜单为每个导入音色提供启用开关；禁用保留配置，电子书播放页和仅选音色的面板只展示已启用项。旧配置默认启用，开关状态持久化，重复导入保留原状态；禁用当前项回退系统语音，播放中保持当前片段继续。
- 朗读面板“朗读引擎”与紧凑沉浸胶囊同行，菜单选中项使用主题色文字及小勾，不铺整行色块；首项为系统语音，导入音色可自由切换和单独删除。每次最多选择 50 个 JSON 文件（单文件 1 MiB），也可粘贴 JSON，最多保留 1000 项；重复配置更新，默认选择最后导入项，重进恢复选中项，删除当前项回退系统语音。支持轻页原生 POST 表单模板及 JSON POST 音色；无语速模板的配置使用本地倍速。配置失败显示提示，播放失败保留位置与音色供重试，播放中切换从当前朗读片段继续。同段短句合并后合成，纯标点不单独请求；片段间复用播放器，播放当前片段时串行预取后两个片段，缓冲命中的衔接不显示加载；实际等待时在播放按钮内显示指示，不改变面板高度。暂停、换音色、改语速和切章清理旧预取。验收覆盖多组导入音色、重复导入和连续切句。

阅读页和播放页右上角按钮使用与“听”字入口一致的 HDS 原生圆形浮动材质（40vp），图标随系统深浅模式适配，API 20–22 回退磨砂；保留加载禁用和原有操作。播放页右上角按“刷新图标 / 上下排列的左右箭头换源图标 / 详情图标”排序，详情位于最右侧，三个按钮使用透明背景纯图标，不应用沉浸光感材质；在线电子书阅读页显示工具栏时，右上角显示刷新、换源、四宫格菜单入口，整体左移并按页码实际宽度预留空间；书籍详情移入四宫格菜单，本地电子书也保留此菜单。底部仅保留章节、设置、字体；章节弹框使用系统最大高度，打开时保持状态栏可见并避让。正文加载失败时仍可操作顶部入口。重载重新获取当前章音频/正文并保留时间或字符位置，音频绕过预缓存和已下载文件（不删除用户下载），文字绕过内存与磁盘缓存。换源在发起请求前按当前书籍类型筛选已启用的其他导入书源：电子书仅搜索 bookSourceType=0/3，有声书仅搜索 bookSourceType=1；漫画仅搜索 bookSourceType=2，未知类型不参与，进度总数只统计匹配书源，返回结果仍校验内容类型。六个搜索位置空闲即接续，单源等待最多 30 秒；自动去除书名版本后缀，按关键词包含关系与内容类型筛选，支持修改书名、停止搜索，展示搜索进度并保留成功结果。搜索 loading 位于停止搜索按钮内，停止立即结束本轮等待并冻结结果和进度，迟到回调不再更新面板；面板标题左上对齐，文字跟随系统深浅主题；选择来源后按钮显示“正在加载章节…”，停止来源搜索并加载目录；优先按唯一同名章定位，否则按当前章节序号定位（超出新目录时定位末章），目录自动滚动并高亮该章，允许继续或手动选章。同名章可保留章内进度，按序号定位的不同版本从章首开始。先验证目标章节能解析音频地址/取得正文，再保存新书身份和替换路由；旧收藏与旧来源进度保留，不混用两来源缓存。本地导入文件不提供在线换源。

定时面板提供“自动定时”开关，默认关闭；开启后显式开始播放自动使用上次定时模式和数值（分钟或章节，未设置过为 30 分钟），播放中开启则立即补建定时。正在运行的分钟/章节定时不被覆盖，暂停恢复和自动续章不重置倒计时；取消当前定时不清除记忆时长，关闭开关仅停止后续自动创建，当前定时仍可单独取消。按章节自动设置时，剩余不足则播完剩余章节，但不覆盖记忆章数。开关、模式、分钟数和章数本地持久化，系统播控、耳机和播放页共用服务入口。

播放页定时入口采用闹钟与右上角短标签叠放：倒计时覆盖右耳区域，以图标裁切保留渐变背景；章节模式显示“5章”等短标签，智能停止等待显示“本章”，无障碍名称保留完整含义。未设置定时时显示完整闹钟，点击与长按操作沿用原逻辑。

实现参考：[ArkUI 开发指导](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-develop-skill/SKILL.md)、[Swiper / List API](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-develop-skill/references/quick-apis/01-layout.md)。沉浸材质复用项目 HdsCompat / AppMaterial 及其版本回退。

- 详情页采用沉浸式 HDS 顶栏，返回/收藏位于标题栏内并同步收藏状态。正文展示封面、信息、快捷操作、阅听进度、最新章节、标签与简介；底部提供阅读/听书或继续入口。完整目录通过独立 ChapterSheet 弹层展示，支持搜索、排序、列表/分段和定位当前章；系统返回优先关闭目录或换源弹层。点击分类标签携带关键词进入搜索。该组件目前接入详情页，播放/阅读页仍沿用各自目录实现。信息胶囊保留原生 HDS 沉浸材质；顶部使用 104vp 内容内边距避让标题栏，底部操作区占位禁止压缩，防止正文增高后侵入返回按钮区域；进入时详情路由及内容底层保持不透明，返回起始恢复路由透明，封面独立运动、裁剪圆角固定；封面动画请求 60fps，避免两页材质在整页透明度动画中叠绘。标题 24fp、作者 16fp、在读/在听进度 18fp、“标签/简介”标题 16fp、简介正文 15fp、标签和操作文字 14fp；标签和简介图标使用行内 SymbolSpan，与文字共用排版基线；简介默认六行，短简介从占位区顶部开始。底部按钮距安全区 12vp。封面预留固定高度，进度区固定为摘要与章节数两行，异步加载替换内容而不插入行。
- 详情页 HDS 标题栏的返回/收藏按钮与正文共用透明度转场，在同一个动画回调内更新；正常封面返回、无封面降级和超时收尾均同步，避免按钮在首页残留。页面隐藏后清零，重新显示详情时恢复；回归覆盖顶部返回、系统返回、连续进出及从阅读/播放页返回详情。
- 阅听记录及未收藏历史点击封面/条目进入详情，复用现有封面一镜到底：异步捕获点中条目的稳定封面节点与圆角，运动期间隐藏原封面，返回重新测量并收回原位置；连续点击去重，截图期间页面退出或进入选择模式则取消跳转。播放/继续阅读按钮保留原动作。2026-11-03：ArkTS 检查、Release SDK 构建、`test-one-shot-transition` 与现行 `test-player-transition` 回归通过，已安装 API 26 手机；实机日志确认记录页电子书及听书条目的封面进入/返回路径，返回后封面恢复。旧 `test-player-drag-transition` 仍依赖已移除的交互代理接口，本次未将其视为通过。未收藏历史及平板双栏未完成实机核验，双栏继续采用已有原生转场回退。
- 详情封面按原图宽高比完整显示：方图保持方形，竖图/横图在既有最大封面区域内等比缩放，不裁剪。首页与书卡在图片数据加载完成时缓存原图比例，详情首帧复用，转场预览使用 Contain 避免二次裁剪。书源首页轮播停稳后才发布背景封面变化，双层模糊背景先在四分之一宽高上做等比例模糊再放大，使用绘制分组缓存；轮播复用全网榜单的叠放封面绘制。背景切换在新图加载并完成布局后，通过 ArkUI V2 状态驱动两个固定背景层，以 1000ms 缓入缓出同步淡出旧图、淡入新图；背景浓度分别作用于两层，不在半透明父层下保留旧图到结束再突然隐藏。快速切换接续最新封面。
- 书源首页轮播（横/竖屏，仅当前正面封面进入详情）、推荐三行书单、列表及通用 BookCard 进入详情统一走原生 Navigation 封面一镜到底：轮播和普通书卡入口异步获取最长边不超过 600px 的封面快照，最多等待 80ms，超时正常进入详情并释放迟到快照；截图和进入详情期间暂停新的背景切换，进入详情时暂停翻牌，返回时补齐背景；详情首屏只展示基础信息与目录骨架，转场完成后再恢复目录、预热书源和加载数据。详情保持最终布局，仅封面通过固定尺寸节点的缩放和平移移动/变形，避免逐帧修改布局宽高；原封面与目标封面在运动期间隐藏，到位后交接真实图片，不叠加整页缩放。起点、目标和覆盖层统一使用包含祖先绘制变换的窗口坐标（FrameNode.getPositionToWindowWithTransform，API 12），截图完成后重取起点以跟随惯性滚动；坐标无效或截图期间窗口尺寸变化时正常降级。进入 420ms、返回 350ms，按 60–120 帧范围请求设备支持的高刷；进入时隐藏首页绘制，只移动独立封面；禁止给首页和详情同时创建整页 renderGroup 并交叉淡化，避免双页材质叠绘造成性能回退。背景柔化仅作用于详情氛围层；返回使用短暂淡出。转场期间延后绘制详情模糊氛围层和标签材质，交接完成后按帧依次恢复背景与五个标签的材质子树，氛围层另以 320ms 渐显，避免突然换底色；返回重新测量原入口并使用当前详情封面。详情遮住首页时 MainPage 使用 Hidden 保留布局并停止绘制轮播背景和材质，返回开始恢复 Visible；详情在栈期间暂停轮播以保留返回封面；入口离屏、横竖屏尺寸改变或截图失败时降级淡出，详情不再额外注册 NavDestination.customTransition，封面和无快照降级由根 Navigation 单独调度；封面到位后仅等待显隐提交便完成导航，不等待图片网络加载，不追加封面淡出；慢图由图片组件显示占位。转场期间禁用重复交互，动画完成立即释放点击锁，不等待导航延迟回调；布局同步使用连续帧而不等待空闲帧，超时恢复可见内容。全网榜单继续先匹配版本，不改变来源选择流程。首页行卡片独立持有封面实例 ID，同书多处出现也只捕获和返回点击的实例；分批插入推荐板块后按当前板块身份判断首板块，不使用 LazyForEach 缓存的旧序号，避免多个板块共用首板块书单。设备回归需覆盖封面进入/返回、网络慢图、重复书籍、快速点击及横竖屏变化。

- 通用迷你播放栏（圆形折叠态和完整展开态，包含 TTS）支持向上拖动打开现有播放页：松手达到长拖或快速上甩阈值后才压栈，从迷你栏实际矩形/圆角连续展开，封面同步放大；小幅慢拖、回拖和取消不进入 Navigation。短拖不再调用原生交互式 cancelTransition，避免实机取消后 NavBar 残留 enabled=false 导致底部 Tab/播控点击失效。点击与上拖确认后的展开、返回收起均使用 300ms FastOutSlowIn；返回按钮与系统返回共用根 Navigation 转场，按恢复布局后的底部栏实际坐标收起，不再叠加 geometryTransition。转场容器使用透明底板，避免纯黑底板被 HDS 玻璃底栏采样。根触摸 Up/Cancel 为缺失的 Pan 收尾兜底，异步回调用代次隔离，导航超时恢复显隐和点击。上拖确认前不初始化播放。API 20–22 固定迷你栏沿用同一手势，音频与 TTS 播控分派不变。回归脚本：scripts/test-player-transition.cjs。2026-11-01 手机验证覆盖短拖取消后展开 Tab/切书架/点击播控、长拖打开、页面返回及系统返回后再次点击；通过 Release SDK 26 构建及安装。尚未逐帧验收黑闪，未覆盖其他系统和设备。


播放入口补充：书架网格、列表和记录页绑定稳定封面实例 ID，续播及异步目录恢复完成后在压栈前采集实际封面位置；返回重新测量同一实例，离屏时淡出。详情页的播放/续播与选章入口同样从当前详情封面一镜到底进入播放器，返回对齐详情封面；同书同章节复用实时播放状态，指定章节保留章号与续播位置。从播放器进入详情再播放时只移除旧播放页，等待旧页释放回调后创建新页，不清空当前详情和其他导航历史，避免短暂露出首页。播放页目标封面等待布局提交后再测量，不把零尺寸作为转场终点；无法采集来源时降级淡入。所有入口由根 Navigation 统一调度，避免外部 animateTo 与禁用导航动画混用。打开/关闭统一 300ms。

手机桌面播放卡片的信息区（封面、书名、章节）只恢复应用前台，保留原页面和导航栈，不主动打开播放页；进程已结束时进入首页。新卡片发送 resume，应用也将桌面缓存旧卡片的 player 请求转为 resume，无需删除重加卡片。手机播放开关和上下章通过 call 在后台执行，不打开应用窗口；手表维持原 call 命令，阅读卡片仍恢复阅读。桌面到应用窗口的系统动画不属于应用内部转场。

该恢复行为已通过 ArkTS 检查、Release SDK 构建并安装 VYG-AL00；实际点击桌面播放卡片后回到书架，设备路由日志为 target=resume。未进行杀进程后的冷启动页面恢复测试。

2026-11-01 排查记录：提交 `7e67f2c` 为适配分栏把首页从独立 NavDestination 移入 NavBar，播放页原有 `geometryTransition('player-cover')` 配对未同步调整，这是多个入口同时异常的共同结构变更；右上角偏移与该改动的直接因果尚未完成旧版/新版实机对照。当前改为显式捕获入口坐标并由根 Navigation 控制。书架实机日志已确认不同封面的入场位置及返回时重取坐标；该证据不代替动画逐帧验收。转场修复已通过 ArkTS 检查、Release SDK 构建并安装手机，稀疏截图确认返回收向底部播控；仍不能排除未采样帧的黑闪。桌面卡片按最终产品决定取消自动打开播放页。

参考实际读取的[一镜到底指南](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-longtake-transition/SKILL.md)与 [Navigation 官方动画文档](https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/ui/arkts-navigation-animation.md)：根自定义转场优先于目的页转场，共享元素示例要求两个 NavDestination 配对且关闭系统转场。本次沿用项目协调器，未引入指南中的第三方转场库。

## HiCar 车载模式

- 入口：我的 →「HiCar 车载模式」，与设置、阅读设置、简简设置并列。未连接车机时标识「手机车载模式」；手动模式可以正常使用，连接本身不强制切换手机页面。
- 分类：最近收听、书架、已下载，只显示音频；复用书架顺序，最近收听去重。空列表按最近收听、书架、已下载给出对应操作提示，加载失败提供重试。已下载分类包括本地导入音频，不表示切换为强制离线播放。
- 点书籍进入目录，点章节按原有逐章进度播放，「继续收听」恢复该书保存的章节和位置。同书正在播放时继续当前会话。窄屏播放面板返回先回到书库，随后退出目录及车载页面；离开页面后迟到加载结果不会启动播放。
- 播控：大字书名和章节、进度、播放/暂停、上下章、前后 15 秒及倍速；直播禁用跳转和倍速。控制状态来自共享播放器。宽窗口左右分栏，窄窗口通过“书库 / 播放”切换完整面板；播放面板底部固定播放/暂停和上下章，封面、进度及辅助控制可滚动，使用实际容器尺寸和安全区。HiCar 路由不参与主导航的双栏布局。
- 自动模式：HiCar 连接且主窗口位于非默认显示屏时展示车载页面；断连或屏幕判定失败恢复原导航栈。自动模式返回根层将应用退后台。保留书源规则宿主，车载界面不显示陪伴挂件、启动动画或夜间关怀提示。
- 打开目录定位到正在播放或上次收听章节；定位按钮可再次回到对应章节，当前章节加粗并描边。点播放面板书名可返回对应目录。列表、切换与播放按钮提供清晰焦点边框；焦点接口已核对 API 20 兼容性，方向盘/旋钮仍待车机验证。
- 系统媒体队列最多显示当前章节所在的 100 章，更新当前项；换书后旧队列选章无效。TTS 接管清空音频队列，退出后由正常音频播放重新发布。

设备回归：检查“我的”独立入口、三个分类/空态/重试、选章及继续收听、暂停恢复、切章、跳转、倍速、返回与横竖窗口布局；同时检查正常播放器、下载和导出。真实车机另外验证入口可见性、连接启动/切换/断开、多屏归属、系统媒体选章、方向盘/旋钮焦点。手机验证不能替代实车验证；当前没有完成 HiCar 音频准入或实车验收。

2026-11-08 Mate 80 已验证独立入口、最近收听/书架/已下载空态、目录定位第 165 集、续播与暂停、上下章，以及车载按钮圆角；完成后恢复原书第 165 集并暂停。HiCar 专项回归和 Release SDK 26.0.0.105 的 release 构建通过。宽屏/横屏、方向盘/旋钮、实车连接投屏和下载导出全链路尚未覆盖。

本轮布局和状态管理依据在线 [ArkTS 语法](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[ArkUI 知识检索](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md)、[窗口尺寸适配](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/06-solutions/multi-device/hmos-multidevice-screen-window-size/SKILL.md)及 [编译修复](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-syntax-checker/SKILL.md)技能，按本项目 V2/API 20 约束和安装 SDK 校核接口。已读取华为 [Car Kit 开发准备](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/car-preparations)，按要求验证 release 编译模式；导航 metadata 示例不作为音频应用入口配置。用户确认目前尚未开通音频应用接入，车机入口注册及实车联调仍待对应资料。

## 标准手表独立听书

- 系统 `deviceType=wearable` 直接打开 `WearablePage`，不加载手机 `Index`。当前继续共用 entry HAP 与服务，最低 API 20；没有宣称覆盖所有 WATCH/GT 型号。
- 黑底圆屏界面按书架、搜索、目录、播放、导入、账号分屏。可滚动列表宽度为屏幕的 76%，视口使用完整屏高并按圆形边界裁剪；首尾各 18% 屏高的内容偏移随列表滚动，避免缩短视口产生底部黑色横向截断。首页不设“下载管理”入口，书籍下载操作位于详情和播放页。大列表使用 `LazyForEach` 和书籍/章节稳定 ID。
- 首次使用可导入 HTTPS 有声书源（最多 2 MiB），或在账号页从手机同账号云备份恢复。搜索只读已启用的导入有声书源，每批最多六源；失败来源不清空成功结果，返回页面后旧搜索不更新新页面。
- 目录、收藏、播放、进度、离线文件沿用现有持久化服务；下载按当前集或当前起五集加入队列，可暂停、重试和二次确认删除。书架包含已下载但未收藏的书。目录已有持久缓存时不要求联网才能打开。
- 按需挂载原规则 HTML、规则浏览器与音频提取宿主，不旁路 QuickJS 限额和源隔离。账号型/网站登录型书源尚未提供手表专用登录界面。
- 账号先校验本地缓存，再调用 Account Kit 的非强制授权请求；手机与手表必须使用同一系统账号及相匹配的应用 Client ID/签名配置。是否能免再次授权以系统返回为准，不能把手机传来的 openID 当登录证明。恢复失败不阻塞本地听书，提供重试和授权入口。
- 手机需先完成现有云备份；手表恢复前显示书籍/书源数量及替换提示，返回或退出页面取消未确认恢复。恢复在线书架、进度和设置，不传输本地音频，也不是实时双向同步。
- `liteWearable` 和 API 20 以下设备未实现：当前 SDK 的轻量能力清单不包含这套 ArkUI.Full、AVPlayer 和 RelationalStore 依赖，现有 HAP 不能通过追加该设备声明获得兼容。需要对应平台 SDK、可安装应用的目标机型以及独立实现与验收。

已做主机定向回归：搜索无源/失败隔离/去重/并发上限、离线目录免网络、导入大小和请求释放、静默账号恢复/state 校验/撤销授权、显式手机登录行为保持。此类测试不代替华为账号跨设备授权联调。 ArkTS 检查无新增错误；Release SDK 26.0.0.105 构建的 Debug HAP 已成功，包内 minimum API 20 / target API 26 / apiReleaseType=Release，deviceTypes 包含 phone、tablet、2in1、wearable，QuickJS 包含 arm64-v8a 和 x86_64 原生库。手机安装启动通过；没有手表实机或可用手表模拟器。

待手表实机检查：圆屏边缘与大字体、输入法/表冠/返回、首次无源导入、同账号静默恢复与账号切换、手机云备份恢复与取消、搜索→目录→播放、离线断网播放、息屏后台播放、蓝牙耳机中断、重启续播、下载暂停/重试/删除、低存储及网络失败。当前只有手机连接，不能将手机启动结果计为手表验收。

参考实际读取的[圆屏适配规格 SPEC-16](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/06-solutions/multi-device/hmos-multidevice-screen-window-size/references/adaptation-specification.md)、[ArkTS 语法规范](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)和 Release SDK 26.0.0.105 的 `@hms.core.authentication.d.ts` / `device-define`。在线圆屏指南建议独立 HAP；本次为保留既有单模块架构而采用同 HAP 的独立启动分支，该选择仍需手表包体与安装验证。


### 手表播放卡片

卡片初始与更新数据携带由系统设备类型生成的 `wearableLayout`，只有标准手表选择 `PlayerCard.WearableLayout`；卡片只显示书名及上一集、播放/暂停、下一集；无书时显示“简听阅读”。书名使用剩余高度、最多两行，播控保留固定高度，取消封面、作者、章节等占位。手机该标识为 false，继续使用 base 配置和原 `PlayerCard` 内容，布局不变。卡片沿用已有 FormBindingData / LocalStorage 绑定及 call/router 协议。

- 书源导入不限总数；整批回滚。已有超额来源保留并可更新/删除，不因会员失效自动删用户数据。锁定保护和单次文件/内存预算保持有效。

- 终身会员展示“长期有效”，不展示虚构到期日期或自动续费状态；已有月/年会员可在阅读升级提醒后一次性购买，提醒主动取消原订阅续费。退款/换号/查询失败按已核验权益刷新历史会员徽标。个人中心和账号页已登录账号名称分别使用月会员金色、年会员紫色、终身深金色，深色模式使用对应浅色资源；无有效权益恢复系统文字色。会员徽标使用 `.creative-design/vip-badges` 提供的横版透明素材：月度金色月牙 VIP、年度紫色钻石 VIP、终身玫瑰金无限符号 LIFE VIP；保持原图比例。“我的”和账号页在用户名下方展示纯月牙／钻石／无限符号及会员名称，高度 20vp，不显示 VIP/LIFE VIP 字样，不加背景色；会员中心保留完整横版标识，账号区高度 28vp、套餐卡片 36vp。会员标识仅在有效展示状态下出现。

### 阅听会话及设置反馈

- 设置页“音频播放方式”提供“自动恢复 / 共存播放”两项，默认自动恢复，不再暴露共享/独立焦点或单独的自动恢复开关。有声书、系统朗读和自定义 HTTP 朗读统一生效。自动恢复只续播被外部音频打断的内容，等待结束后从原时间/朗读片段继续；手动暂停、停止、定时结束、耳机断开撤销等待。设置加载及保存期间禁用重复操作，失败恢复原选项并提示。回归需覆盖切换、重启持久化、短视频结束、长时间中断、来电再次打断及耳机断开。
- 详情页仅在进入转场或尚无章节且仍在加载时，底部收听／阅读按钮显示“加载章节中”并禁用。首批章节显示后即可点选收听或阅读，底部入口同步恢复，剩余目录继续后台追加到播放／阅读页；追加不重载正文或改变当前位置。后续目录请求失败保留已加载章节可用，空目录和重复起播仍拦截。音频首批章节直接使用本轮规则上下文，不为规则校验重复等待完整目录；文本目录同样分批展示，重进或跳转复用在途请求，部分目录不覆盖持久目录。
- 历史记录页面使用单层 HdsNavDestination，移除嵌套导航与标题模糊，保持不透明背景；280ms 平移结束回调触发读取，不再固定等待 500ms；历史读取不额外保存／刷新活动会话，改用内存快照补齐当前进度。存储一次读取、每 32 条让出事件循环，列表沿用 LazyForEach 与会话 ID；离页取消待加载任务与解析，过期结果不更新页面，已载入页面返回时保留列表。
- 性能实现参考已读的 [ArkUI 主线程与渲染指导](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/14-performance/analysis/ui-performance-overview.md)。本次以主机回归和 Release SDK 编译验证逻辑，尚无连接设备，未测量实际帧率。

- 阅听记录、未收藏记录中的每本书提供时钟图标进入“历史记录”，与继续阅读/播放图标在书名右侧紧邻、顶部对齐；章节行单独占用下方宽度。历史页按时间倒序以节点、竖线和卡片展示起止时间、章节与毫秒/字位置，支持跳回开始和停留位置。使用 HDS MINI 标题、安全区避让及不透明背景，减少转场中的模糊合成开销；图标保留无障碍标签。音频显示时间进度，文字显示字位置与已知章节百分比；无历史、读取失败、章节已删除均有明确提示。
- 删除书籍、删除阅听记录及清空在线收藏只归档统计明细，累计、本月和每日收听时长保留；再次收听恢复该书明细。恢复备份按书与日期合并较大值，不降低本机累计，也不重复累加同一备份。设置页已移除“清空在线收藏与播放记录”和“清除累计收听时长”入口，保留的缓存清理入口不清零累计统计。此规则适用于应用内清理，卸载或系统清除应用数据仍受系统行为控制。
- 设置清理区按顺序仅保留“小说正文缓存”“漫画图片缓存”“音频缓存”。移除仅清 EPUB 解析器内存引用的“清除电子书缓存”入口。三项统一显示实际占用和上限，点击确认后显示释放大小、使用中保留项及失败项，再刷新占用；统计失败可点击重试。音频不再弹出预加载/离线下载二选一，只清播放预加载缓存，主动下载由下载管理删除。三项均不删除书源、收藏、阅读/播放进度、累计阅听时长或本地导入原文件。
- 小说正文、漫画图片、音频缓存上限依次为 1 GiB、5 GiB、5 GiB。正文入口同时清除内存与可清理的磁盘正文；正文/漫画自动超限清理至 90%，阅读器登记保护的文件和在途写入暂时保留，释放后重试。音频按真实的 `chap_*.mp3` 文件统计和清理，同一路径只计一次，保留当前播放和正在写入的文件，仅成功删除才累计释放空间；手动清理与自动淘汰串行，清理期间阻止新的预加载入队。回归脚本 `test-reader-cache-budget.cjs` 使用临时真实文件验证正文/漫画 LRU、重启、读写保护及目录隔离。
- 实际范围补充：正文存储也承载漫画章节图片清单，清正文会删除可清理的清单但不直接删除对应图片；保护仅针对阅读器登记的文件和在途读写。漫画图片清理使用文件名白名单，目前未包含新超分的 `sr_` 文件。音频缓存清理保留使用中文件；下载管理删除正式离线音频的旧实现仍未提供同样保护，个别文件删除失败会被忽略，完成提示不代表磁盘占用必定归零。
- 缓存验证：预算管理、正文磁盘缓存与公共书源引擎回归通过；Release SDK 增量构建 Debug HAP 并安装 Mate 80 成功。实机核对正文/漫画实际占用、上限、两类确认框及取消操作；删除和超限场景使用主机临时文件验证，未清空手机已有内容。缓存设置行直接在组件绑定中读取状态，避免按值传入通用 Builder 后停留在“正在统计”。
- 音频清理统一后的验证：`test-audio-preload.cjs` 通过，覆盖真实临时文件占用、同一路径去重、播放/在途文件及离线下载保留、删除失败、取消后的迟到完成与扫描失败重试。Release SDK 26.0.0.105 增量编译 Debug HAP 成功，包内为 Release / API 20–26。此次音频设置变更未上机验证；先前覆盖安装返回 `9568286: install provision type not same`，未为验证卸载已有应用或清除手机数据。
- 带“应用”的设置采用草稿：主题色预设/自定义色、预加载章数预设/输入、搜索并发预设/输入均不提前保存或更新运行状态，键盘完成不代替应用按钮。点击“应用”才提交；主题色关闭选色面板后未提交的选择丢弃。预缓存校验 0–50，成功后更新当前书预缓存；搜索并发校验 1–12，成功后下次搜索生效；保存失败保留实际设置，重启读取已成功应用的值。
- 回归：阅读翻页/跨章/退后台后查看历史并跳回；音频暂停/续播/切章后查看历史；TTS 从历史字位置继续。开启诊断日志，用真机锁屏至少 15 分钟，核对 `tts.audio.start`、`tts.failed`、`background.cancel` 和 `background.suspend`。模拟器通过不能替代真机锁屏结论。
- 2026-10-06 模拟器实测：用户提供的三份有声书 JSON 已导入。使用本地 `tts-stability` 文本进行系统 TTS 验证，按电源键息屏超过 12 分钟，日志持续显示 `foreground=false; bg=true` 且字符位置推进，唤醒后阅读页由 4/57 推进至 14/57；未复现约 11 分钟停止。历史页显示该次会话从第 329 字到第 4498 字，点击跳回开始后回到第 1 页。此结果不代表真机省电策略、耳机或音质已验证。
- 本轮设置验证：重装启动后搜索并发保留 3、预缓存保留 12；随后预缓存改为 2，实测显示成功提示。主机测试覆盖设置写失败回滚、冷启动读取、搜索并发 1/3/6/12，会话持久化及 PCM 校验；TTS 28 项、音频命令 31 项通过。Release SDK 26.0.0.105 增量构建 Debug HAP 并安装启动成功；独立 ArkTS 检查因 LSP 未初始化不可用，构建工具 OHPM 递归错误后使用 Release IDE CLI 编译。
- 在线有声书闭环尚未通过：其中两个导入源在本轮未取得可播放搜索结果，宿主站点访问返回 403；另一个导入源可返回搜索结果但与普通关键词不匹配。不能据此声明真实书源的边加载边播放、预缓存、下载及导出已验收。已读技术参考：[ArkTS 语法技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[ArkUI 技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md)、[系统 TTS API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/hms-ai-texttospeech)。

- 搜索并发默认 3，只有有效会员可保存并实际使用自定义 1–12。选择和输入仅编辑草稿，应用时检查当前权益；自动查询不闪烁、不阻塞普通设置。已确认会员失效回退 3，备份恢复不能绕过权益校验。

阅读页右上角四宫格菜单的弹出选项使用 `AppMaterial.Sheet` 沉浸光感材质，API 26+ 使用透明底色与原生材质，API 20–25 回退系统磨砂；菜单材质需独立于入口按钮配置，不能沿用系统默认白底。

### 沉浸控件与后台续播

- 详情页底部“开始／继续阅读”和“开始／继续收听”采用轻透玻璃胶囊主按钮：宽度随内容自适应、左右各 18vp 内边距、高 48vp；透明底叠加 12vp 自定义背景模糊、约 6% 浅色／9% 深色遮罩、细边框与轻阴影，避免系统预设材质的厚白遮罩；仅转场、无章节及起播期间禁用，保留深浅色文字适配。按钮接入全局“智感握持”：默认右下角，识别左手后靠左、右手后靠右，关闭开关恢复右侧；不支持识别时保持默认位置，详情不可见或销毁时停止监听。详情按钮使用固定布局与横向平移；阅读悬浮播放器、小说和漫画亮度条与之统一使用 `animateTo + springMotion(0.4, 1)` 换手动画，重复同侧事件不重启动画，关闭开关也平滑归位。仅握持状态变化触发动画，纵向拖动维持实时响应；HdsTabs 继续使用系统原生跟手行为。依据：[官方弹簧曲线](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-spring-curve)。连续换手手感尚待支持设备实测。
- 绿色“声波”保留翻页书本与竖条声波，灰底“夜曲”保留白色书页与彩色声波；两款主体均居中放大约 15%，原背景不变，分层前景和选择页预览同步更新。
- 小组件、系统播控与页面的明确播放操作允许重新申请被系统取消／挂起的后台任务；自动预缓存不自行解除系统阻挡。跨章播放保留后台资格直到下一章完成加载，下一章出声后推进预缓存窗口；真正末章、定时停止或续播失败释放音频任务，有限下载队列继续由独立 dataTransfer 持有。
- 定向回归覆盖任务取消／挂起后恢复、缓存章到网络章接续、滚动预缓存、末章和失败释放；实机需覆盖长时间后台后小组件恢复及缓存耗尽边界，不能用模拟回归代替实机结论。
- 锁屏或卡片恢复先完成媒体会话初始化及后台任务申请，再起播；重复播放不重载章节，等待期间的暂停优先。即使播放器仍报告 playing，明确播放也应补申请已经丢失的后台任务。旧任务的取消／挂起／激活回调及迟到申请结果不能覆盖新任务，手动暂停须释放已挂起任务。
- 排查随机后台停播时先区分进程退出和播放中断：手动开启诊断日志，复现后保留 `audio.event`、`widget.command`、`background.start/cancel/suspend/active`、`app.destroy/lastExit` 及发生时间。音频记录包含焦点提示、耳机路由变化、暂停来源和前后台状态，不记录书名、音频地址或凭据；API 26 的后台详细取消原因有版本判断，较低版本保留通用原因。回归脚本为 `test-background-playback.cjs`、`test-audio-commands.cjs` 和 `test-audio-preload.cjs`。

### 搜索、目录和个人设置交互补充

- 阅听统计只保留“累计阅听 X时Y分”和“连续阅听 X天”，两个原生胶囊形沉浸光感框同排，间距 8vp。标签和数值均为 12fp，以当前 UIContext 实测文字宽高加内边距决定框尺寸，不写死宽度、不均分整行；超宽时横滑。材质与顶部圆形按钮统一使用 `HdsTabs.barFloatingStyle` + `HdsCompat.material`，最外层以实际高度一半为圆角，使用 `RenderStrategy.OFFSCREEN` + `clip(true)` 裁掉 HDS 内部外溢阴影和矩形底角，保留胶囊内沉浸光感，不叠加边框；旧系统使用普通圆角裁剪与胶囊形磨砂回退。此裁剪不可删除，验收须检查实机胶囊下缘无阴影块。数字与图标沿用当前主题颜色，底色不另作修改。本月统计不再显示，但统计口径和持久化保持原状。

- 阅听记录顶部统计卡片采用纯文字展示，移除右侧收音机插画，累计时长区域使用卡片完整可用宽度。
- 统计上方展示“简听一语”，仅记录主页显示，未收藏记录页不显示。内置 1365 条不重复的古诗词摘句，附作者和篇名，使用古代原文，不含现代译文。纯本地随机洗牌，无在线接口和句子缓存：每次完整进入记录页、跨日或下拉刷新时换一条，每轮 1365 条不重复，下一轮重新洗牌，轮次交界不连续重复同一句；重启进程重新随机。按实测文字宽度排列，能同行时正文居左、作者靠右，放不下时作者另起一行靠右；紧凑间距，不显示服务商/时光副标题。诗句区域无底色、无磨砂背景，直接展示在页面主题背景上；标题保持次级文字色，不跟随强调色，不阻塞记录骨架与刷新。验收覆盖离线切页换句、循环轮换、深浅色与窄窗口、长按选择及双击回顶。

- 阅听记录处于编辑状态时，侧滑返回、系统返回及页内返回先退出编辑并清空勾选，停留当前页面；正常浏览时才执行页面原有返回。适用于记录 Tab、独立统计页和未收藏历史页，隐藏记录 Tab 后不得拦截“我的”页返回。

- 阅听记录（含未收藏历史）每行左滑露出 22vp 红色垃圾桶图标，透明背景、44vp 点击区域，侧滑操作区宽 52vp，不显示大红色块和“删除”文字；点击后二次确认，普通左滑不直接删除。确认后清除该书及合并别名的记录和阅读/播放进度，累计与每日阅听时长、书架书籍及本地文件保留。编辑状态禁用行侧滑，继续支持批量确认删除；取消保留记录和勾选。删除期间锁定重复操作并使旧明细加载失效。
- 单条删除使用 `RecordDissolveEffect`：截图按随机矩形切分，波前从右上角传向左下角，原色碎片向右上飘散约 1100ms，再以 180ms 收起行间距。首帧提交后才隐藏原内容。改编自 [Petrel 原生渲染器](https://github.com/miramira8295/Petrel/blob/ed218f4559cf083b51b08c5bf0bb27ea6215cbb9/entry/src/main/cpp/shatter_renderer.cpp)，不是系统预置删除动画。截图最长边限制 720px，单条颗粒最多 6000；NAPI 后台准备像素/切块，透明 XComponent TEXTURE 合成，NativeVSync 在原生线程驱动 OpenGL ES 3，每帧两批实例化绘制，ArkTS 不参与逐帧运算。截图/渲染失败只退为轻量淡出，离页、超时和尺寸变化释放本行资源，迟到的准备结果关闭后再释放 PixelMap。原生完成日志记录绘制提交耗时与间隔，不能当作实际显示帧率。
- 实现依据本轮在线读取的 [ArkUI 开发技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-develop-skill/SKILL.md)、[ArkTS 编译修复技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-syntax-checker/SKILL.md)、[废弃接口检查技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-deprecated-interface-checker/SKILL.md)，具体签名以本机 Release API26 SDK 为准。
- 截图 ID 必须从页面模式与稳定 bookId 生成；禁止在组件字段初始化中用 `getUniqueId()`，实机此时返回 `-1`，多行 ID 冲突会截到另一本书。2026-11-06 在 VYG-AL00 真机通过临时 TXT 记录验证过左滑、取消、目标书截图及删除后补位，累计阅听时长不变；该次使用旧 Canvas 后端，不代表此次 GPU 后端的实机性能已验收。18 项统计与删除定向回归通过。
- 书架网格和列表的单本删除保留 GPU 消散，多本删除使用短淡出。先等待菜单／确认面板退场，动画结束后立即从展示数据源移除目标书卡，让剩余书籍补位，再执行收藏保存与可选文件、记录清理；原书单和别名保留到保存成功，失败时恢复条目及批量选择。慢磁盘写入、文件清理不再让透明书卡占位。自动高度书卡在挂载粒子层时锁住原高度，离屏书不创建动画，动画期间变为离屏的书卡立即解除等待；删除期间禁用滚动和重复操作。成功后复用已加载书单，仅有并发收藏集合变化时重新加载，离页和超时解除动画等待。
- 2026-11-07 补位时序定向回归通过：慢文件清理、慢收藏落盘期间已提交剩余书单，部分文件失败和单本保存失败恢复原位，离屏节点不拖住动画完成。ArkTS 检查无错误；Release SDK 26.0.0.105 增量构建 Debug HAP 成功，包内 Release / API 20–26，已覆盖安装并启动 VYG-AL00 真机。本轮未执行实机删除耗时验证，主机回归不代表设备视觉验收。
- 2026-11-06 GPU 版本使用 Release SDK 26.0.0.105 构建 Debug HAP，包内 `apiReleaseType: Release` / minimum API 20 / target API 26，已安装模拟器。临时 TXT 测试书实测书架列表单本删除、网格管理模式删除（勾选 1 本），确认原色颗粒出现、目标书移除、其他书正常补位，未观察到串图；多本同时动画的等待和离页收尾由 `scripts/test-shelf-batch-delete.cjs` 定向回归覆盖，尚未做多本同时消散的设备视觉验收。
- 性能尚未验收通过：模拟器上不连续截图的单行样本，平均绘制提交 87.67ms，其中 `eglSwapBuffers` 占 87.52ms；网格截图验证样本平均提交 67.38ms，其中交换缓冲占 67.13ms。截图会干扰性能，两组不能用于比较优化幅度；提交间隔也不是屏幕显示帧率。旧 ArkTS 密集 Canvas 绘制已移除，但当前模拟器仍存在交换缓冲阻塞，需连接真机继续测量 GPU 版本，不能据此宣称 60/120fps 或卡顿已解决。实现参考已读的 [ArkUI 性能分析技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/arkui-performance-analysis/SKILL.md)。尚无此次 GPU 后端的真机、平板、PC 或手表性能验证。

- 分组管理中每个自定义组支持删除，二次确认后仅移除分组并将组内书籍归入“未分组”，不删除收藏或本地文件。删除当前选中组后切换到“未分组”；取消或保存失败保留原分组。

- 书架顶部文件夹按钮：点击切换分组，长按打开分组管理；筛选弹层也提供“分组管理”入口。支持创建空分组和重命名自定义分组，重命名同步迁移书籍归属并保持当前选中组；空名称、保留名称及重复名称不可保存，保存失败保留输入供重试。自定义分组可长按行拖动排序，松开即保存，重启保留；保存失败恢复原顺序，拖动不改变书籍归属及当前选中组。

- 搜索自动按源逐页获取并持续追加结果，不再显示“加载更多”或占据底部空间。下一页回到队尾，优先让尚未搜索的源返回首页；所有页共用搜索并发上限，顶部按已完成书源计数。空页、完全重复页或失败停止该源，筛选后为空仍继续翻页。修改关键词后提交、修改搜索条件或清空搜索会重置分页，旧请求不得回写新结果。

- 搜索列表／网格按钮位于顶部筛选右侧；结果类型标签可横向滚动，窄屏时不挤占进度。
- 搜索“同名书籍来源”弹层在书名与来源之间展示当前结果的分类标签，复用详情页的元数据清理和分类拆分规则；空标签不占行，多个胶囊随可用宽度换行。最新章节位于来源下方，避免挤压书名和标签。此标签行仅用于同名来源弹层。
- 2026-11-06 标签行验证：独立 ArkTS 检查修复圆角常量后服务超时，MCP 构建遇到 OHPM 批处理递归错误；改用 Release IDE 的 Node/Hvigor `--no-daemon` 完成 Debug HAP 构建，包内为 Release / API 20–26。设备列表为空，尚未验证弹层实景。实现已读取在线 [ArkTS 语法技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[ArkUI 检索技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md)及其 [Flex 布局参考](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/03-layout/linear/ts-container-flex.md)，并以本机 SDK 声明核对。
- 播放页、阅读页章节弹窗使用文字排序胶囊切换正序／倒序，回到顶部和底部合并为一组图标按钮；沿用每本书目录顺序偏好，搜索、分段目录和当前章定位保持可用。跳转列表不切换正在播放或阅读的章节。阅读页当前章仅保留定位标识，列表与分段模式均不高亮背景或文字。
- 换源确认章节时，原书已收藏则弹出沉浸光感确认框（旧系统回退厚磨砂）。选择“覆盖原来源”在目标章节验证成功后替换原书架条目，保留位置和置顶；选择“取消”继续换源，同时保留旧来源并加入新来源，两本共存且不重复添加。旧来源缓存与阅听记录保留；原书未收藏时沿用原流程。
- 设置中的“全网榜单设置”默认折叠，点击整行标题展开或收起，箭头同步指示状态；标题和展开内容使用与设置页其他卡片一致的主题表面色。展开后支持显示开关、上移和下移，保存后即时影响首页，重启保留；各平台均提供 6 个榜单。番茄为热门、玄幻脑洞阅读、都市高武阅读、古风世情阅读、玄幻脑洞新书、古风世情新书榜，分类榜在本机解码官网字体混淆的元数据，未知字符不展示；飞卢为月票、月鲜花、周鲜花、周点击、月点击、月收藏榜。全部关闭时提示前往设置开启。
- 我的功能入口顺序与分组：书源管理、本地导入同卡 → 设置独立卡片 → 成就馆、主题同卡 → 使用教程、日志管理、关于同卡；书源管理只显示标题。主题入口从支持与联系移到成就馆后，沿用现有 membership 路由与主题页；支持与联系保留公众号、交流群。账号及功能卡片恢复不透明显示；墨山账号区域保留完整背景，功能入口保留分组和整体圆角，使用接近账号头部暖米色的主题纯色表面，不再绘制山水图片。强调色使用古朴黄（浅色 #80612E、深色 #D5B887），旧推荐朱砂色自动迁移，其他自定义色保留；默认、纸感书房、雾蓝各自保持独立配色。

- 阅听记录和未收藏历史通过标题栏筛选按钮下方的浮动选项菜单选择全部、有声书、电子书或漫画，弹层材质、圆角与选中态沿用书架样式；编辑入口使用右上角编辑图标，编辑中切换为完成图标，正文不常驻展示类型标签和编辑入口；切换筛选退出批量选择，取消菜单保持当前筛选。
- “设置 → 外观”提供“横滑切换底部 Tab”，默认开启，以本机 `swipe_switch_tabs` 偏好保存，重启恢复；保存失败保留旧值。开启时正文横滑切换首页／书架／记录／我的，关闭时横滑切换首页栏目或书架类型；两种模式均保留点击底部 Tab。两层手势在识别前按开关互斥，避免子手势吞掉主 Tab 横滑或一次滑动同时切换两层。HdsTabs 原生内容横滑保持关闭，主 Tab 使用 HdsTabs 原生整页横向滑动，切换时长为 350ms，不叠加透明度或短距离位移；底栏和迷你播放器保持原位。动画开始时同步目标页签与页面可见状态，点击和横滑请求交给原生控制器处理，隐藏记录时保留实际索引映射。类型模式下：首页按顶部栏目顺序切换，全网榜单为分类总览、精品推荐及已启用平台，导入源首页为分类总览、推荐及源定义分类；书架切换全部／有声书／电子书／漫画，沿用当前分组、搜索词和状态筛选。横向位移至少 48vp 且明显大于纵向位移，松手后切换，首尾不循环；短滑、纵向滚动、取消及书架批量管理不切换类型。子级横向滚动优先，顶部轮播仍只翻牌；顶部标签点击和双击底栏回顶继续保留；书架通过顶部按钮刷新，首页保留下拉刷新。定向回归：`scripts/test-startup-tab.cjs`、`scripts/test-page-type-swipe.cjs`、`scripts/test-reader-controls-preferences.cjs`。
- 阅听记录完整显示并等待 220ms 后统一刷新记录；未完整显示时不响应后台数据事件刷新列表。记录身份及顺序不变时由字段观测更新，不发送整表重载；本地封面异步加载。顶部统计胶囊继续使用 HDS 沉浸光感与原有 OFFSCREEN 圆角裁剪；统计胶囊和空态不再额外执行入场动画。验收需覆盖快速左右横滑、滑动取消、返回页面、下拉刷新、双击回顶、筛选及长按多选；编译通过不代表已验证帧率收益。
- 阅听记录及未收藏历史的条目保持无独立背景，不添加磨砂、半透明卡片、卡片圆角裁剪或额外内边距；行高 88vp、封面与文字间距 16vp、行间距 16vp，加载骨架恢复原有无背景布局。逐行实时背景模糊曾造成实机严重卡顿，不得再次给列表条目添加 backgroundBlurStyle、backdropBlur、HdsTabs 或 OFFSCREEN 材质层，外层继续保留删除消散粒子的绘制空间。
- 阅听记录列表右侧“记录 / 阅读或播放”两个按钮采用原生圆形 Button、随深浅色适配的静态半透明底色、0.5vp 细边框及系统按压反馈。条目及按钮均不创建背景模糊滤镜、HdsTabs 或 OFFSCREEN 合成层；顶部按钮和统计胶囊保留原有 HDS 沉浸材质及裁剪。列表拖动及惯性滚动中继续合并进度、统计、收藏事件，停止后刷新；已经开始的异步加载在提交前再次检查滚动状态，避免中途重排。
- 阅听记录和未收藏历史使用官方 `List.chainAnimation` 链式联动，沿用单列与 `EdgeEffect.Spring`：拖动时相邻条目随系统弹簧联动，条目自身不再额外位移、缩放或淡入。移除自定义入屏候选队列、可见比例检测、逐行坐标测量和停滚归位回调。List 显式设置 `space: 0`，由原有条目 margin 保持静止时 16vp 行间距，避免链式动效默认额外加入 20vp；行高仍为 88vp。加载、编辑多选、删除、隐藏 Tab 和播放器转场期间关闭链式联动；保留 LazyForEach 稳定 key、原生侧滑、长按选择、滚动期间合并数据刷新和删除消散粒子空间。
- 链式动效接入依据本轮在线读取的 [ArkTS 语法技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[ArkUI 检索技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md)及其 [List 参考](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/03-layout/grid-list/ts-container-list.md)，并核对 [华为 List 官方文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-list)和本机 Release SDK 的 `chainAnimation` 声明（API 7 起支持，位于项目 API 20 基线内）。在线目录已刷新，未运行知识库检索脚本。
- 2026-10-25 Mate 80 受控滑动对比：同一主题和记录列表，仅替换行内按钮。前后应用窗口 OnDraw 平均墙钟耗时约 5.58ms / 2.09ms，UIVsyncTask 平均约 2.09ms / 1.88ms。两次各采集 12 秒，旧版 Trace 环形缓冲保留末 9.29 秒，新版保留 12 秒，按单次调用均值比较而非总量；新版采样中出现系统通知，不能把全屏 RenderFrame 或含停顿的 FPS 当成纯列表指标。历史入口已实机验证，滚动与下拉刷新可用；不同主题、热状态、播放并行及其他设备未完整覆盖，不宣称所有卡顿已消除。
- 2026-10-24 按用户选择将列表按钮改为透明磨砂玻璃后，通过修改文件的 ArkTS 检查、Release SDK 26.0.0.105 构建并覆盖安装启动到手机。遵循用户停止手机测试的要求，未执行设备交互或滚动帧率复测。

### 2026-10-19 交互调整

- 首页来源菜单：全网榜单、视图切换和漏斗类型筛选同排；视图切换图标使用系统中性色，随深浅主题适配；筛选复用书架弹层样式，提供全部/有声书/电子书/漫画。搜索框与下方来源入口使用统一间距，列表为滚动条留右侧空间。
- 设置页隐藏历史记录开关；书架来源显示开关放在全网榜单设置前，复用标准分组标题、卡片及开关行。切换立即更新网格/列表来源标记，写入失败恢复原值。书籍编辑弹框选择本地或书源封面后立即预览，保存后提交，取消保留原书籍。
- 全网榜单的榜单行与查找书源弹层封面按原图比例绘制，并限制最大高度；加载完成后的占位背景与实际图片共用比例，方形封面不保留纵向矩形白底。
- 书架列表模式使用随主题适配的圆角信息卡：上方保留书脊封面、类型与来源标记，展示书名、作者、有声书播音、来源更新时间／最新章节及阅读或收听到的章节；下方展示最多两行的纯文本简介，以及真实评分、最多三个分类、已完结／连载中和字数标签。缺失与占位字段自动隐藏，标签随窗口宽度换行；进度使用已保存章节，不用章序号伪造精确阅读百分比。元数据更新后同步刷新对应卡片，沿用长按菜单、置顶、批量选择和封面转场。列表卡片与标签采用静态主题色，无逐行背景模糊；网格布局保持原样。
- 此列表实现已读取在线 [ArkTS 语法技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[ArkUI 检索技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md)及 [Flex 布局参考](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/03-layout/linear/ts-container-flex.md)，使用本机 Release SDK 声明确认标签换行与间距接口兼容 API 20。
- 2026-11-06 列表补充验证：Release SDK 26.0.0.105 的 Debug HAP 构建通过，包内标记 Release / API 20–26；手机模拟器已确认网格切换列表、作者／最新章节／已保存进度／分类／字数显示和缺失字段隐藏。现有样本未覆盖完整评分、简介与完结组合，深色、长按批量交互及真机仍待验证。独立 ArkTS LSP 检查超时，MCP 构建遇到 OHPM 批处理递归错误，实际通过 Release IDE Node/Hvigor `--no-daemon` 完成编译。
- 书架长按“封面与重命名”可改名、选择本地封面、查找书源封面或使用图片链接；分组由独立的“设置分组”入口管理。图片链接支持粘贴 HTTP/HTTPS 地址，点击“预览并使用”成功加载后替换预览，再点击“保存”持久化；地址无效、图片加载失败或 15 秒超时保留原封面并提示，取消输入或关闭面板会忽略迟到结果。普通缺失封面、网络封面加载中或加载失败时只显示无文字占位，不叠加书名或作者；仅本地导入且无封面时显示书名与作者；本地导入且没有封面的书籍使用宣纸花边底图，书名在中上部横排（最多三行）、作者在下部横排（最多两行），两者之间保留明显留白，导入预览、编辑预览、书架网格与列表保持一致；已有内嵌封面和手动替换的封面优先，不向封面字段写入占位图。书架网格与列表封面（含占位图）统一使用轻立体书本样式：左侧 14% 宽的透明明暗渐变呈现书脊与装订压痕，小圆角配合右下轻投影；类型标签向右留出书脊，选中边框跟随封面圆角。装饰层不参与触摸命中，不增加封面图片解码。设置可隐藏来源标签。
- 阅读与漫画设置可隐藏章节条；正文可长按选词并打开操作菜单。电子书正文长按菜单首项提供“从本段朗读”，从选区起点所在自然段开头连续朗读，留在阅读页，不跳播放页；复制、全选等系统菜单项已移除，改为“AI 字典”和“总结本章”。分页和连续滚动均传递所选章节与正文坐标，缩进/空行及替换规则映射回原文；暂停或未开始的朗读也可由该操作直接起读。播放页的文字书封面缩小，下方滚动显示朗读段落。音色弹层只展示已有音色，TTS 导入入口位于阅读页面设置中，管理弹层不提供倍速；音色长名称单行滚动。播放页音色按钮在播放且可见时显示循环波形律动，暂停、加载或隐藏时停止。

电子书长按 AI 工具覆盖应用排版（分页／连续滚动）及 EPUB 原版排版。字典仅发送选中文字，以中文解释含义，并按需补充读音、词性、用法与例句；选中句子时解释句意和关键词，缺少语境时列出常见义项；总结读取选区所在章节完整正文，连续模式跨章同屏时按选区章节处理。结果在阅读页弹层展示，外层复用 AppMaterial.ReaderSheetThick 固定厚沉浸材质，内容背景透明并使用系统主/次文字色，避免实色底挡住材质或浅色背景白字；API 20–25 保留磨砂回退。支持取消、失败重试和 AI 配置入口；关闭、切章、离页或进入后台取消请求并丢弃迟到结果。复用简简现有加密 AI 配置，不新增接口、数据表或聊天历史。单次字典查询最多 20,000 字符，本章总结最多 384,000 字符，超过限制明确提示；长章按最多 12,000 字符分段生成摘要，再逐层合并，清除本地图片路径标记，不静默截断正文。弹层显示期间停止自动翻页并暂停朗读位置跟随，保留阅读位置。 本轮 ArkTS 检查无错误，新增阅读 AI 回归及现有 AI／EPUB 回归通过；Release SDK 26.0.0.105 的 debug HAP 构建通过，产物标记 Release / API 20–26。2026-11-08 Mate 80 已安装复测，确认选词菜单、AI 字典和本章摘要弹层的沉浸材质及文字对比，实际查询可显示所选文字并返回释义/摘要；深色、连续模式和 EPUB 原版尚未单独完成设备覆盖。 简简聊天与阅读 AI 结果在显示时清理 Markdown 标题和加粗标记，包括跨行、嵌套、转义、未闭合和反引号包裹的连续星号；Markdown／纯文本代码框中的自然语言同样清理。保留段落、引用编号与正文中的井号，已有聊天记录同样生效。AI 请求统一要求纯文本输出，显示端仍负责清理模型残留标记。
- 搜索结果的视图切换位于搜索框右侧、筛选按钮旁，与筛选统一使用 44vp 圆形按钮、22fp 图标，搜索中隐藏；支持指定源多选、同名数量角标及聚合弹层返回。同名数量随搜索返回响应式刷新，网格和列表均显示；点击聚合弹层中的来源打开详情或播放页时关闭弹层，返回搜索不会残留。同名来源与指定源弹层同时配置背景材质和旧系统磨砂回退，避免透明底色直接透出搜索结果。历史开关关闭后隐藏记录 Tab，保留续播续读数据。
- 漫画显示整章解析实际等待秒数，超分静默且失败回退；图片有解码预算，保留滑动/点击翻页与章节位置提示。
- 漫画“阅读模式”设置在“翻页效果”下方增加“显示效果”，左侧标题、右侧原生下拉选择，全局偏好 `comic_display_mode` 持久化。选项为“原版”（沿用既有大屏舒适宽度及图片分页）、“铺满宽度”（去除文字阅读器的 760vp 限宽，按窗口安全区内全宽等比显示，长图保留上下滚动）、“完整显示”（整张图片缩放到窗口内）和“原图大小”（按原图像素换算 vp，只缩小超限图，不放大小图）。各模式不拉伸、不裁掉原图；连续模式切换/调整窗口时按当前图片和图内比例恢复位置，缩放拖动按实际窗口宽度限位。非“原版”的左右翻页只提供单图/拼接分页，避免与显示效果重复控制尺寸。
- 漫画详情页同步最新阅读进度；章节列表高亮当前章并显示“正在阅读”，打开目录、目录加载完成或当前章变化后自动定位。漫画列表有阅读记录时保留“回到当前章节”入口，正倒序按章节身份定位，搜索时不强制跳转，无阅读记录时不伪造当前章。
- 本次漫画详情修复：`test-comic-detail-progress.cjs` 定向回归通过；Release SDK 26.0.0.105 Debug HAP 构建通过，包内最低 API 20 / 目标 API 26 / Release 渠道。Mate 80 已安装，使用《硬核一中》确认目录阅读标识、定位入口及切章后的详情进度同步；手动滚动后点击定位和倒序交互尚未完成实机覆盖。
- 书源检测可离页继续并发布通知，系统中断保留部分结果；JSON 文件选择取消后恢复悬浮加号，列表底部保留避让空间。

本轮实现、回归及尚未完成的设备验收统一记录在 `REQUIREMENTS.md`，此节不代表全部验收通过。

阅读与漫画章节浮动条外层高度统一为 44vp、圆角 22vp，内部进度轨道保持 6vp、滑块保持 16vp。电子书底部章节、设置、字体及章节箭头使用系统前景色，与系统玻璃材质同步深浅色；不继承正文自定义文字色。章节进度轨道、滑块和 API 20–22 回退底板同样使用系统配色，避免自定义背景下低对比度。

漫画底部工具栏的上一话、目录、设置、下一话仅显示居中的图标，不显示文字；保留原点击区域、边界禁用反馈及无障碍名称。

漫画章节条与底部工具栏共用实际窗口宽度及对称安全区留白，外缘等宽居中；浮动材质显式指定相同宽度，旧 API 回退也沿用该宽度，章节条保留圆角离屏裁剪。

漫画设置中 AI 超分、着色、翻译的 VIP 标识紧跟功能标题，开关独立靠右；标识继续按会员功能总开关控制显示。

用户开启着色后可提前准备模型资源和 Worker，空闲最多复用 120 秒；关闭、退出阅读、后台和内存压力按生命周期释放。首次真实图片校验成功的 NPU 结果可在模型、系统及校验规则一致时复用最多 7 天，减少重启后的重复校验。

漫画 AI 翻译在阅读设置内独立开关，每次进入阅读默认关闭，与上色独立开关，可同时开启。翻译已移除在线 API、密钥、模型配置及独立“翻译为”控件。仅有“翻译方式”下拉框，顺序固定为“日文翻译中文 / 韩文翻译中文 / 英文翻译中文 / 中文翻译英文”，无“本地离线”前缀；选择本机持久化。切换方向立即取消并关闭当前翻译，重新开启后使用新方向，衍生缓存按方向隔离。着色通过独立 HAR 子包在本机处理，无在线 API 与模型配置。

翻译使用系统 OCR、按需下载并校验的 OPUS-MT 量化模型和本机画布完成全流程，不上传图片或文字。日文、韩文通过英文中转，英译中和中译英直接推理；中转可能更慢且引入语义误差。ArkWeb 固定本地资源白名单、无平台 JS 桥、Worker 禁用远端模型和 CDN，最多两套模型，空闲 60 秒、取消或关闭翻译释放。无文字页不推理。首次加载有明显等待，不能保证比在线模型更快。复杂背景、倾斜/竖排文字有回填局限；译文放不下时保留原图并提示失败。刷新旁 AI 翻译入口点击打开与阅读页右上角一致的原生材质菜单，展示全部四种翻译方式（中译英最后）及关闭/取消选项。选中后按所选方向翻译，当前开启项仅用主题色高亮，不显示对勾，按钮为主题色；关闭恢复原图。非会员选择提示会员权益；会员已有语言资源时直接开启，缺包时确认下载量后下载，显示进度并允许取消，完成自动开启。后台、退出或切换方向不迟到开启翻译；切换上色不取消翻译下载或改变翻译开关。日/韩共享英译中资源；已完整校验的文件重试时复用。运行时构建准备使用 `python scripts/prepare-comic-offline.py`，文件散列及版本固定在 `scripts/comic-offline-assets.json`。

“着色中”和“正在翻译”均显示在对应图片的左上角，距图边 8vp；连续阅读、左右翻页和渐隐模式共用此布局。提示随图片滚动，不固定在屏幕角落，不拦截图片点击、缩放或翻页手势，任务结束或取消后消失。

翻译复用本次任务已缩放解码的像素，最终图片只编码一次；本地输出不再经过远端上色图片的二次解码压缩流程。完成任务时仅记录 OCR、模型请求、图片回填的毫秒耗时，不记录原文、译文或密钥；这些分阶段日志用于定位识字、端侧推理与回填的耗时。

2026-10-25 朗读跟随翻页：主机回归覆盖确认/取消翻页、迟到回调不回拉正文、加载中替换目标、暂停与其他书籍会话隔离、连续滚动停止后仅跳读一次；34 项 TTS 回归通过。ArkTS 检查无错误，Release SDK 26.0.0.105 构建的 Debug HAP 已安装启动到 Mate 80，包内 apiReleaseType=Release、minimum API 20、target API 26。手机截图确认工具栏显示时保留暂停胶囊，隐藏工具栏后正文没有常驻胶囊；翻页后停留新页，朗读高亮在新页继续推进。实际出声起点、连续滚动和跨设备窗口变化仍待人工验收。

电子书“听”播放页的“本章朗读进度”支持拖动跳转，点击轨道不跳变，按正文字符百分比定位到对应语音片段起点，不伪造音频秒数。拖动期间仅预览百分比，松手提交一次；若拖动期间切换书籍或章节，则丢弃旧目标。播放中跳转继续播放，暂停时跳转仅更新正文、高亮与持久进度；拖到 100% 定位本章最后一段语音，不直接进入下一章。上一句/下一句按钮继续可用。36 项 TTS 主机回归及拖动提交/跨章跨书丢弃旧目标回归通过。Release SDK 构建、包内 Release/API 20–26 核验及 Mate 80 安装通过；旧版手机验证曾确认播放中点击轨道从约 56% 跳到 78%，暂停后拖至约 31% 仍保持暂停；2026-11-07 起统一禁止点击轨道跳转，该点击记录仅代表旧版行为。实际音频起点与其他设备仍待人工验收。


朗读进度拖动：目标仍在当前正在播放的音频片段内时，直接按正文比例 seek，无需重新合成；提供方没有逐字时间戳，定位为近似位置。跨片段时保留范围和文本均匹配的待播 HTTP 任务，取消其他过期任务。加载中的再次拖动采用最新目标，不再忽略操作；目标尚未合成时仍需等待。暂停拖动保持暂停。61 项朗读回归、HTTP 播放生命周期测试及 Release SDK 构建通过，2026-11-05 已覆盖安装并启动于 Mate 80；当时手机有视频小窗播放，未抢占声音进行朗读听感验证。

系统与自定义 HTTP 音色跨页衔接以当前规则为准：不按页尾拆分语音，保留自然语句连续合成与播放，避免“清｜晨”等跨页词被拆成两次发音。AVPlayer 的实际 timeUpdate/音频时长用于按片段文字比例估算跨页时机，仅越过页界时更新正文位置；不建立逐字刷新定时器，不打断或替换当前音频。系统合成接口没有逐字时间戳，因此不宣称逐字精确同步。手动从页首起读及暂停后恢复仍按指定位置切入；字体/窗口变化只更新页界映射，不丢弃可复用的完整语句音频。HTTP 音色亦使用同一条 AVPlayer 播放进度通路，不按页拆分合成请求。

系统音色在每个合成片段开始播放前提前准备下一片段，不依赖阅读页界；仅保留一份有界 PCM/音频，预取不提前播放或移动页面。尚未合成完时接管同一请求，失败时在轮到该片段后回退普通合成；暂停、跳读和换章清除旧预取。三倍速段间衔接、暂停续读、音色切换及失效请求由主机回归覆盖，实际发音和流畅度仍需手机试听。

实机链路排查确认当前实际音色为自定义“度小雯”（百度 TTS），先前仅修正系统音色不能改善此现场。HTTP 音色现同步采用跨页连续合成与播放进度映射；SpeechFlow 日志仅在跨页片段记录请求 ID、字符范围及播放时间，不记录正文或接口凭据，用于核对翻页前后保持同一音频请求。

2026-10-25 15:19 Mate 80 同段复核：长按“老汉偏是个爱面子的人…”选择从本段朗读，实际 HTTP 音频请求 tts1792912744179n22 覆盖 983–1049；播放 6670/12540ms 时页界推进到 1018，日志中 play/page 的请求 ID 相同，页面截图由 3/16 切至 4/16。验证了该页界没有重启合成或音频请求；未录制或主观试听声音，不据此保证提供方音频本身没有停顿。


### 简简 · 陪伴与 AI

我的 →「简简设置」独立页面首项提供“简简陪伴”开关，标题旁以品牌色小字显示“限时体验”，默认关闭、保存到本机。开启后在适合的页面显示，关闭后立即移除人物并停止互动动画，重启保持开关选择。`PreferenceService` 先更新共享状态并发出事件通知根页面，再异步保存；保存期间禁用重复提交，失败恢复开关并提示。

开启后根导航上方显示红色长发、红色连衣裙、手持书本的 Q 版女生简简，使用 `角色资产/简听娘-红色系列-透明底全套` 的透明 PNG 优化副本。主界面各 Tab、详情和普通设置共用一个人物；文字阅读、漫画、播放器、书源登录、AI 配置及聊天页自动隐藏并暂停动画，返回后恢复原位置。默认位于右下方并避让浮动底栏；按住即可直接拖动，无需长按等待；移动超过 5vp 后识别拖动，轻点触发互动，松手停留，切换页面保留位置，窗口缩小时约束在可见范围内。互动对话使用 24vp 圆角、随内容自适应高度的气泡和小尾巴，顶部空间不足时移到人物下方并翻转尾巴，沿用主题色和触摸透传。点击读取真实今日阅听时长、连续天数、播放与停止定时状态生成本地反馈，8 秒后恢复待机。气泡提供“和简简聊聊”“本次隐藏”；空书架且无阅听记录时提供本地导入，同时无书源时提供添加书源。本次隐藏可通过重新开关陪伴或重启恢复。全身人物不与半身素材交替闪动，拖动不弹出气泡，空白区域不阻挡页面操作。位置不跨关闭或重启持久化，不覆盖系统弹窗、系统文件选择器或应用外页面。

“我的”页新增独立“简简设置”，第一张卡片为陪伴开关、夜间关怀开关，第二张卡片为“AI 配置”“提示词设置”“和简简聊聊”；页面介绍、陪伴和夜间关怀的说明统一移入标题旁圆圈感叹号，点击以锚点浮层展示，支持关闭按钮、外部点击和系统返回收起。普通设置页移除原简简分组。AI 配置沿用现有分组卡片、标题栏、圆角、间距、主题色和说明按钮；表单从标题栏下方开始排列，短内容不垂直居中。输入服务地址及密码型 API Key，点击“获取模型列表”后保存完整模型目录，在可搜索的原生弹层中自主选择并保存；不固定模型名单、不自动选择首项。下方模型行显示全部可选模型数量，随时点击可搜索和切换，无需重新获取；重新进入配置页和重启应用后按已保存地址及 Key 恢复目录。已有目录时按钮显示“刷新模型列表”，手动刷新失败保留旧目录。修改地址或 Key 后清空当前目录和选择；旧版本仅保存模型名的配置需要成功获取一次以建立目录。清除配置需确认，同时删除加密模型缓存。

“提示词设置”分别提供“日常聊天”“书籍问答”编辑区，首次打开预填原始内置提示词，切换类型保留未保存的编辑内容；每种最多 8000 字，显示当前字数。点击保存同时持久化两种提示词，下次提问读取最新值；“恢复当前默认”只替换当前编辑区，保存后生效，留空保存也会使用内置默认内容。无需配置 AI 服务即可编辑，清除地址/Key/模型不会删除自定义提示词；加载失败可重试，保存失败保留编辑内容和上次保存值。帮助说明放入标题旁感叹号。书籍问答仍只携带已读范围内的片段；阅读页的字典和本章总结沿用各自专用提示词。

2026-11-08 修改文件 ArkTS 检查无错误，简简专项回归通过，覆盖默认值兼容、自定义保存、留空恢复、保存失败保留旧值、清除服务配置保留提示词及下一次请求采用新值。Release SDK 26.0.0.105 的 release 构建通过，最终 HAP 确认 debug=false、apiReleaseType=Release、API 20–26，并安装 Mate 80。实机已查看默认提示词编辑页及其布局；本轮按用户要求停止后续设备验证，编辑保存/恢复和说明浮层交互未完成实机覆盖。

本次依据已读取的 [ArkTS 语法技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[ArkUI 知识检索技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md)，以及 [TextArea](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/04-components/basic/ts-basic-components-textarea.md)、[菜单绑定](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/08-dialog-menu/menu/ts-universal-attributes-menu.md)说明实现，保持 ArkUI V2，复用 `SettingsHintButton` 的版本守卫。

AI 接入兼容 `GET /models` 与 `POST /chat/completions` 的服务，当前为文本聊天；模型能否用于聊天由对应服务支持情况决定。Key 随配置保存在本机独立加密数据库，不随应用导出备份。聊天页以简简头像和气泡居左、用户头像和气泡居右，气泡随文字收缩、最大宽度按当前容器约束，双方使用卡片色和主题浅色区分。输入框使用主题浅色，发送按钮始终显示主题实色，空内容点击提示输入；未配置时点击进入 AI 配置，回复中点击取消。移除大块阅听概况及阅听记录按钮，空会话只显示简短问候和发送范围说明。本地阅听反馈及空书架引导仍由浮动简简提供。只有主动发送消息才调用 AI；闲聊不附带正文或阅听数据，从文字阅读页提问则只发送当前已读边界内的本机片段，发送范围在页面说明。回复可复制，通用闲聊与每本书/书源会话分别在本机加密保存；退出可恢复，右上角垃圾桶确认后只清除当前会话。配置变化保留历史，退后台或页面隐藏取消请求并恢复待发送文字；取消和失败的半条问答不落盘。网络、鉴权、接口、限流和响应异常有对应提示，失败可重试。

发送后立即在左侧显示简简头像、名称和等待气泡；等待气泡沿用回复气泡的颜色、圆角与对齐，内部显示主题色进度和“简简正在回复…”。收到回复后替换为正文；取消或失败时移除等待气泡并恢复待发送文字。

文字阅读菜单新增“前情回顾”“问已读内容”。回顾入口预填问题，由用户发送；书籍聊天顶部沿用现有文字与主题色按钮，显示书名、截止阅读位置、可用已读章节数与发送范围。只从实际 reading/tts 会话区间取当前边界内的缓存片段，不下载全文或使用未读预取；缺失数据明确提示，不支持用纯音频书名猜剧情。回答的有效 `[编号]` 下方显示章节按钮，点按回到原文字符位置；伪造或未提供的编号不生成链接。

“夜间关怀”位于简简独立设置的开关卡片，开启简简陪伴后默认生效。本地 23:00–05:00、前台停留至少 30 秒，每晚最多一次；跨零点和重启仍视为同一晚。普通页面显示 8 秒困倦气泡，沉浸阅读/播放/聊天页面只出现 5 秒短提示，不显示浮动人物、不暂停阅读或播放。关闭开关、隐藏人物、后台及书源登录/简简设置/AI 配置页面不触发。

2026-11-07 本轮书籍会话与关怀验证：变更 ArkTS 检查无错误，`test-jianjian-reading.cjs` 验证书源隔离、会话重建恢复、单会话清除、落盘失败保留、取消后的迟到回复、已读区间与回退边界、缓存缺失、检索预算、图片路径过滤、章节引用，以及跨零点/重启提醒频率；AI 服务与贴边回归也通过。Release SDK 26.0.0.105 构建成功。手机重新连接后，已在 Mate 80 覆盖安装本轮 Debug HAP；阅读菜单、书籍范围说明、原有模型配置保留和回复等待头像已确认。夜间定时规则通过主机时间场景验证，未修改手机系统时间；夜间实机自动触发尚未验证。

2026-11-07 此前基础 AI 验证：变更 ArkTS 检查无错误，AI 服务和人物贴边两组主机回归通过；Release SDK 26.0.0.105 构建成功，Debug HAP 元数据为 Release、minimum API 20、target API 26。Mate 80 已覆盖安装，确认设置入口、配置表单顶部位置、真实服务模型列表、选择保存及重新进入后回读，并用用户已保存配置收到中文 AI 回复。首次获取模型出现连接错误，重试后成功；用户原有配置保留。自动隐藏和空书架引导通过主机策略回归，未逐一路由实机验收；平板、折叠屏、PC 和手表未验证。

同日修复陪伴人物出现后页面无法滚动：`Index` 在自定义组件上添加 `.visibility()` 后生成全屏 `__Common__` 包装节点，其默认命中模式拦截底层页面；仅设置组件内部 Stack 透传不足。最外层同步设置 `HitTestMode.Transparent`，人物按钮和气泡操作保留原响应。Mate 80 先复现设置页滑动无位移，再覆盖安装验证包装节点已透传，人物保持原位时首页列表正常滚动；底栏点击可用，拖动与贴边逻辑主机回归通过。最新包同时包含左右聊天气泡和始终着色的发送按钮，真实会话可正常显示。触摸响应规则参考 `https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/18-arkts-rules/arkts-interaction-rules.md`，命中模式及 API 9 起可用由本机 Release SDK `common.d.ts`、`enums.d.ts` 核对；首次在线读取被 429 限流，重试读取成功。

实现参考在线 `hmos-arkts-knowledge-retriever`（`https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-knowledge-retriever/SKILL.md`）及其语法约束、`hmos-arkui-knowledge-retriever`（`https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md`）及其 V2 `@Local` 指南；接口以官方文档检索返回的 Models list 和 Chat Completions create 契约为依据（`https://developers.openai.com/api/reference/resources/models/methods/list`、`https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create`）。指南读取不代表执行了上游工具流程。

人物按钮关闭默认按压反馈（`stateEffect(false)`），避免透明底色长按时出现矩形色块；拖动仅以人物轻微放大提示。

2026-10-28 全局拖动更新：组件 ArkTS 检查无诊断，Release SDK 构建及 Mate 80 安装通过。实机长按期间截图确认没有矩形按压底色，拖动松手后停留新位置；已观察首页与“我的”显示人物。全部路由、窗口缩放和其他设备尚未逐一验收。

验收关注：点击/快速连点、8 秒复位、直接拖动/轻点区分/松手/取消、四边约束、切换 Tab 和前进返回保持位置、安静路由自动隐藏/恢复、空书架引导、模型获取/搜索/选择/保存、聊天取消/失败恢复、底栏和页面滚动操作；平板/折叠屏/2in1、大字体与不同主题仍需对应设备验收。本功能未接入手表入口。

2026-10-28：新增组件 ArkTS 检查无诊断，Release SDK 26.0.0.105 Debug HAP 构建并安装到 Mate 80。实机确认首页右下人物、点击笑脸/气泡、气泡与人物分离、恢复待机及收起/展开；完整首页刷新/双击回顶回归及其他设备未覆盖。

- 搜索设置提供“搜索推荐”开关，默认开启，纳入设置备份。关闭后搜索页隐藏推荐并停止调度请求，迟到结果不回填；搜索历史和主动搜索不受影响。
本轮开发读取在线 `hmos-arkts-knowledge-retriever`（`https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-knowledge-retriever/SKILL.md`）、`hmos-arkui-knowledge-retriever`（`https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md`）、`hmos-arkts-syntax-checker` 和 `deveco-studio-verify`；按语法摘要的 Error 抛出约束修复编译，并沿用 API 20 可用的 V2 状态及既有生命周期。读取设备指南不代表已完成设备验证。

### 简简 · 原生二维网格动画

- 拖到左右边缘附近松手，人物用 220ms 动画吸附，向外偏移 40vp、绕脚底向内倾斜 42°，身体藏在窗口外、头部斜着探出；窗口内仍保留 52vp 宽的点击/拖动区。左右镜像，中间区域松手仍自由放置。
- 点击贴边人物会滑出完整身子并显示互动气泡，8 秒后收回同一侧；展开期间也可直接拖出，拖动取消自动收回。窗口尺寸变化保持停靠侧，气泡仍约束在窗口内。

- 开启“简简陪伴”后，全身人物在原有位置歪头、呼吸，手与书本一起起伏，发梢与呆毛独立错相摆动，脚底固定；眼睑跟随人物网格，不替换成半身表情帧。
- 开心/比心表情触发短暂闭眼，眨眼表情触发单眼，困倦表情期间闭眼，结束后恢复待机；气泡内容与表情由真实本地阅听和播放状态决定。
- 拖动时暂停待机动画，松手保持位置且不误弹气泡；切换应用内页面不重置人物位置。
- 回归检查：开关、点击、连续点击、拖动、旋转/窗口变化、退出再进入；重点查看眼睑对齐、气泡上下翻转和触摸透传。
- 后台/不可见/关闭时停止眨眼与呼吸；本能力为 ArkUI V2 原生二维网格动画，不加载 Web，不要求安装 Cubism；不宣称支持面部透视转头、嘴型同步或挥手。

### 全文搜索与发音人管理

- 听书与文字朗读的音量增幅分别持久化，重启后恢复，设置为 0 同样保存；文字朗读管理与播放器共享朗读增幅。听书每次播放器准备完成重新应用已记忆的增幅。
- 桌面图标在系统确认切换成功后记忆选择，覆盖更新后的首次启动及回前台校验权益后恢复。会员查询失败不重置图标；明确失效可恢复默认但保留用户选择，权益恢复后可恢复所选图标。旧版本尚未记录选择时迁移系统当前图标；若旧版本更新时系统已丢失选择，无法反推原图标，需重新选择一次。

- 统一文字阅读器的目录面板提供“全文搜索”，逐章检索原文，点击匹配跳转到原文字符位置；替换规则通过既有坐标映射定位。支持停止、读取失败计数，最多展示 500 处并提示缩小范围；关闭面板或修改关键词后不再提交旧结果。在线书籍需加载未缓存正文。
- 朗读引擎管理窗口启停、删除发音人后保持打开，列表增量更新并保留滚动位置；点击窗口外关闭。保存期间仅禁用内部操作，失败保留原配置并提示。播放器声线列表沿用导入顺序和原名称，只列已启用配置，使用同一数据源及稳定键，系统声线单独置前。
- 主机回归 `test-reader-search-voices.cjs` 覆盖跨章/分段搜索、字符位置、取消、失败与结果上限，以及发音人增量更新和启用列表顺序；`test-local-book-import.cjs` 覆盖长 EPUB 两条转换路径不拆章且正文完整。
- EPUB 除正文 img/SVG image 外，提取 body 简单标签、class、id 选择器及内联样式匹配的包内背景插图，放在对应正文开头；按 CSS 优先级选择，不执行脚本、远程加载或完整 CSS 排版。旧导入内容需重新导入才补图并应用原章节边界。
- 设置 EPUB_TEST_FILE 可用真实 EPUB ZIP 运行自研解析器与导入服务回归（Python/Pillow 独立核对原包图片，主机仅适配文件、解压和图像接口）。《花与剑与法兰西》验证 1110 章、1116 处图片引用及 21 个原版资源；《深海余烬》验证 868 章、1287 处图片引用及 86 个原版资源，CSS/字体/图片逐字节一致，全文搜索到达末章。主机结果不替代真机原生解压与精排视觉验证。
端云同步承担持久进度恢复，应用接续仅是额外入口。`LibraryCloudSync` 使用同一实例监听系统进度并触发同步，区分网络、Wi-Fi、电量、温度、存储和系统错误；回调后重新检查文件，逐文件确认才更新最近上传时间，最近检查云端另行展示。普通续听最多等待 4.5 秒检查云端，超时沿用本机位置并提示未确认；正在播放不跳转，明确选章、拖动与历史定位遵循用户指定位置。音频和文字朗读均保护已接收位置，避免旧暂停状态回写覆盖。开关只响应真实点击，取消开启不重弹，关闭直接执行。错误期间不反复重建待传文件；单轮最多尝试 64 个远端快照、同设备最多两代。验收需包含开启后取消、直接关闭、暂停后续听、离线恢复和同账号双实机；当前双设备回归采用模拟云传输，不能替代真实双机验证。

# 书架与进度自动同步（2026-11-04）

2026-11-05 单机验收：Release SDK 构建安装后，实机验证关闭直接执行、开启取消保持关闭且不重弹、重新开启只需一次确认；系统回调 COMPLETED/error=0，逐文件上传确认时间恢复更新。完成后无错误 STOPPED 视为本轮空闲。当前只有一台设备，尚未完成手机与平板之间的真实续听验收。

卡片默认折叠，与本地备份和华为云空间卡片一致。收起时显示标题、VIP 标识、单行状态及箭头；点击标题展开后展示开关、说明和同步操作，再次点击可收起。折叠只改变展示，不改变同步开关或任务状态。

入口：“我的”顶部账号行 → “书架与进度自动同步”。默认关闭，标记 VIP，登录且会员核验通过后可开启；非会员点击进入现有会员引导，订阅页权益表单独列出该功能。开启时仅一次确认当前在线书架、阅听记录及逐书历史与云端合并；确认与设置期间锁定开关，状态回写不重复触发确认。确认会员到期后关闭同步且保留数据；临时核验失败暂停、保留开关并提示，核验恢复后继续，关闭无需会员。开关和授权属于当前账号、本机设置，换账号需重新确认。卡片展示未开启、会员核验暂停、等待、正在合并、本机已保存待上传、已确认云端上传、环境不支持或失败重试；“立即检查同步”同样核验会员，不绕过系统调度，云端成功不代表另一设备已经应用。

同步范围：在线书架加入/移出、置顶、分组、阅读章节与字符位置、播放章节与时间、阅听记录列表（包含删除）、逐书历史记录的开始/结束时间和位置。历史会话按独立 ID 去重合并；本地导入书记录保留在本机，累计时长和勋章不纳入本功能。同步不传本地音频/电子书和书源定义，接收设备需已有相同书源。书架变化自动刷新；正在阅听时不跳章，继续阅读/播放会产生本机新位置，结束后合并最新位置。后台尽力提交已保存变更，重启/回前台补齐。各设备需在系统云空间开启应用同步，网络、电量、温度和云配额影响传输。旧待传文件超过五分钟且不在上传时自动重新提交最新快照；明确上传失败/停止显示失败重试，不永久伪装成等待；最近确认上传时间不会因为重复检查同一文件而刷新。

本轮验证：ArkTS 检查和 Release SDK Debug HAP 构建通过；双设备模拟覆盖离线删除与重启、重新加入、主动回看、并行改不同书、分组/置顶、正在阅读保护、下载中本机修改、账号切换、关闭、API 20 回退及短读写；64 项音频命令回归和阅读进度回归通过。真实手机/平板/PC 同账号云空间同步、系统开关、真实传输延迟及页面视觉仍待设备验收，不沿用其他功能的实测结论。

### 后台恢复补充

手机听书卡片的播放/暂停及切章通过 call 在后台执行，不打开应用窗口；只有信息区点击使用 router 进入应用。播放开关通过已注册的 toggle 回调依据进程内真实状态切换，不依赖可能陈旧的卡片 isPlaying。非暂停命令等待偏好和上次播放恢复实际完成，恢复任务合并且不覆盖用户新选的书；手表卡片维持原 call 路径。

双层迷你播放栏网络封面在挂载及回前台主动加载，不依赖滑动可见性通知；已加载封面保留，后台未完成请求可取消并在前台重试，旧结果不会覆盖新封面。普通书籍列表保持可见区域懒加载。

### 阅听设置与音色管理

阅听设置、对话高亮、朗读显示、合成配置、字体管理与音色管理的滚动视口延伸至窗口底边。底部安全区加在 Scroll 内容的末尾 padding 或 List 的 contentEndOffset 中，不加在滚动容器外层，避免卡片在手势条上方提前截断；滚到底后最后一项保留安全间距。音色管理的悬浮添加按钮单独叠加底部安全区避让。验收时同时检查滚动中的底边连续性与滚到底后的末项、按钮可见性。

2026-11-10 底部布局修复：6 个页面 ArkTS 检查无错误，Release SDK 26.0.0.105 增量 Debug HAP 构建通过，包内元数据为 Release / API 20–26，已覆盖安装并启动实机 VYG-AL00。实机滚动视觉尚未验证。实现参照本轮读取的在线 [窗口沉浸式技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/window/hmos-window-immersive/SKILL.md)和[滚动容器沉浸示例](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/window/hmos-window-immersive/references/imm-05-practical-cases.md)；本机 SDK 的 List.contentEndOffset(number) 从 API 11 支持。

对话颜色与朗读标记颜色的“跟随阅读主题”均使用开关，空颜色偏好表示开启；已有自定义颜色保持关闭。关闭跟随时固定当前预览颜色；手动操作调色盘、色相滑杆或提交 HEX 后自动关闭跟随并保存，仅聚焦或离开 HEX 输入框不改变跟随状态。重新进入页面根据已存 HEX 还原 HSV，调色盘宽度使用响应式状态，首次布局及尺寸变化后同步圆点位置。开启跟随时预览和正文使用同一个 App 主题强调色，切换主题色、套装或深浅模式会重新解析；主题色变化使已挂载的原生正文重绘，不改变自定义颜色或阅读纸张底色。

2026-11-06：改动文件 ArkTS 检查无错误，Release SDK 26.0.0.105 Debug HAP 构建与阅读偏好、原生段落绘制回归通过。平板模拟器验证手动选色自动关闭跟随、返回重进保持色值与圆点坐标、开启跟随后切换晴空蓝 `#2869B8` 同步设置预览与双栏正文中的对话。深浅资源重解析及主题单独变更触发重绘有主机回归覆盖；本轮未做手机/折叠屏真机验证。

实现依据为在线 `lang-syntax`、`hmos-arkui-knowledge-retriever` 与 `hmos-arkts-syntax-checker` 技能，相关指南：[V2 计算属性](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/02-state-management/v2/arkts-new-computed.md)、[V2 监听](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/02-state-management/v2/arkts-new-monitor.md)及[深浅色适配](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/11-theme-style/ui-dark-light-color-adaptation.md)。主题换肤总览 `theme_skinning.md` 返回 403，相关 API 以已读取的适配指南和本机 SDK 声明核对。

TTS 配置下载和合成请求在未声明 `User-Agent` 时使用兼容默认值；配置自带的 UA 与认证头优先保留，避免部分服务的客户端过滤拒绝请求。合成失败保留 HTTP 状态码用于诊断，不记录认证信息或正文。

“我的 → 阅听设置”按朗读设置、阅读显示分组；音色管理、合成配置、字体管理、朗读显示、对话高亮使用紧凑圆角卡片，单行最小 52vp、双行最小 64vp、卡片间距 8vp。“字体管理”进入独立二级页，右上角导入字体、列表查看并确认删除，展示已导入数量及空态；复用 ReaderFontService，每次最多 50 个 TTF/OTF、单个 32 MiB。阅读页字体入口继续保留，导入后在阅读页选择使用；删除当前字体后返回阅读页自动恢复系统字体。合成配置进入独立页面，各参数分卡片调节后保存。URL 与粘贴配置在屏幕中央弹窗填写，取消和返回关闭弹窗，导入期间禁止重复提交。音色管理为独立页面，展示系统音色与自定义 TTS，支持选择、下载系统音色，以及启停和删除自定义配置。右上角“试听”播放当前勾选音色的固定示例文字，系统音色和导入的 HTTP TTS 共用既有有界音频输出；试听期间按钮为“停止”，再次点击取消准备或播放。切换音色、离页、退后台或正式播放接管时取消旧试听，错误提示重试，不回退到其他音色。试听暂停原播放，但不创建书籍会话、写入试听进度或统计。右下角圆形“＋”提供本地 JSON 文件、URL 和粘贴 JSON 三种导入方式。URL 指向 HTTP/HTTPS 的音色 JSON 配置，最大 1 MiB、最多 1000 个音色（支持完整导入 189 音色目录）；HTTP/HTTPS 合成请求沿用配置声明的地址与请求头。请求和解析失败保留输入以便修正，不写入配置。复用现有 TTS 解析、去重和持久化，不新增数据表。
2026-11-10 导入专项首轮：书源、字体、TTS 的本地选择器和服务处理上限统一为每批 20 个文件。字体与 TTS 最多并行处理 4 个文件，顺序按用户选择保留；字体整批成功项一次保存目录，选中使用时再加载字体。书源后台解码、按时间分片构建模型，在同一文件事务内批量读取管理状态和写入，失败整文件回滚。主机专项覆盖 20/21 文件边界、短读、无效文件、并发顺序、锁定/启停/置顶保留和失败回滚，69 项 TTS 回归通过；Release SDK 26.0.0.105 的 Debug 包构建并安装启动成功。手机定向 `LocalRuleSourceFileImport` 用例通过（1/1），验证 3 MiB JSON、损坏文件跳过、真实 taskpool 和加密数据库；测试数据已由用例清理。原测试入口仍引用已删除的旧书源模块，本次临时限定入口运行专项并已恢复。尚未完成字体/TTS 的真机批量测速及本轮在线搜索、阅读/播放全链路验证，不宣称统一提速倍数。

# 品牌图标与开屏

- 默认主图标使用用户 PNG 原稿的“胶彩柔光”，图标库不再重复列出柔光选项，旧柔光选择迁移为默认；此前 SVG 主图标以“胶彩”保留在图标库，更早的旧主图标名称为“怀旧”；“虹彩”改名为“墨颜”并位于图标库第 4 位（含默认图标）；沿用现有会员与 API 26 备用图标限制。
- 手机、平板和 PC 的冷启动播放一次约 1.3 秒原生开屏：幻彩光晕、四色依次点亮、品牌字标与标语淡入，底部横条在约 1 秒内连续伸展，随后退场；横条只表示开屏动画进度，不等待内容加载。后台恢复不重播，首页初始化与外部路由照常进行；手表沿用独立入口。
- 开屏按实际窗口尺寸布局，使用深浅色资源。渐变图层预渲染为透明 PNG，避免设备 SVG 渐变差异。原稿和可复现生成脚本见 `docs/icon-design/splash-gel-reference.html`、`scripts/build_app_icon_gel.py`；主图标与 AGC 素材由 `scripts/build_app_icon_gelsoft.py` 生成，AGC 上传使用 `docs/icon-design/agc-icon-1024.png` 直角图标。



阅听设置中的“朗读显示”和“对话高亮”使用并列独立卡片入口。朗读显示内的跟随翻页、标记样式、标记颜色各自成组；字色、高亮和下划线均可调色，三个示例同时预览，阅读页的朗读浮层提供相同能力。对话高亮总开关点击后立即更新开关与预览，保存期间仍接收连续切换，串行保存最后一次选择；旧保存结果不得覆盖新选择，最终保存失败恢复最近成功状态并提示。对话高亮内统一设置启用状态、符号范围、颜色和预览，支持勾选中文单双引号、直单双引号、直角单双引号、【】和《》，也可添加开始/结束各一个字符的符号对，最多 16 对。默认保持原四种双引号，全部取消后不高亮；规则按整章识别再映射到翻页、双栏、连续滚动和带插图的文本片段，未闭合符号不影响后续段落。符号范围保存在原阅读 Preferences 并参与备份，旧备份沿用原四种范围。两页复用原阅读偏好，保存后同步已挂载的阅读页面，避免返回后旧值覆盖。音色管理支持名称搜索与 group / tier 筛选；显式 group 优先，旧配置的 `[Omni·定速]` 等方括号前缀用于补充分组。tier 仅展示提供方声明，不承诺特定延迟或音质，元数据更新不改变音色身份。

2026-11-06 设置入口调整验证：改动页面 ArkTS 检查无错误，阅读偏好回归和 Release SDK 26.0.0.105 的 Debug HAP 构建通过，HAP 元数据为 `apiReleaseType: Release`。平板模拟器确认并列入口、对话设置独立页面、朗读手动选色后关闭跟随及返回重进保留颜色；开启跟随恢复主题色，关闭跟随固定当前色；对话高亮总开关返回重进后保持。验证后恢复原有开关状态，本轮未进行手机真机验证。

音色管理移除右上角排序按钮及名称升降序工具，自定义音色行首常驻拖拽手柄，直接长按拖动，松手立即落位、自动保存并同步阅读和播放音色列表，失败恢复原顺序；筛选时仅调整当前结果占用的位置。右上角“批量操作 / 完成”控制多选模式，全选、启用、停用、删除四个按钮与已选数量固定在磨砂顶栏内，滚动列表时保持可用。全选仅作用于当前筛选结果，切换筛选会移除隐藏项的选择；删除前确认数量。整批保存成功后更新界面，失败保留原数据和选择；停用或删除当前音色沿用系统音色回退。搜索与分组/档位筛选压缩为两行，列表间距 6vp、音色卡片最小 56vp。系统语音位于自定义音色列表下方，不显示 zh_CN 等语言代码，仍由系统提供下载和选择，不参与自定义配置批量删除。

字体管理与音色管理使用相同的行首拖拽手柄和顶部批量操作栏，支持单项/批量启用、停用、删除和长按排序。旧目录默认启用，停用保留字体文件，目录顺序及 `enabled` 一并保存在 `reader_fonts.catalog`；阅读页只按保存顺序展示启用字体，停用或删除当前字体后重进或返回阅读页恢复系统字体。批量删除保留失败项及其选择供重试，排序/启停保存失败恢复旧状态。无新增接口或数据表。回归脚本 `scripts/test-reader-fonts.cjs` 覆盖迁移、启停、排序、写入失败及部分删除失败。

实现依据为本轮读取的在线 [ArkTS 语法规范](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[ArkUI 知识检索指引](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md)及其 [LazyForEach 文档](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/09-rendering/ts-rendering-control-lazyforeach.md)，编译诊断参照 [ArkTS 检查指引](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-syntax-checker/SKILL.md)。继续使用项目的 ArkUI V2 与原生 `onMove`，不引入新系统 API。

合成配置提供“一键应用连续朗读推荐配置”：设置段落上限 3 / 字数上限 500、并发 3，并启用“快速起读（仅首句）”。该开关默认关闭，关闭时所有请求按配置的段落数和字数上限合并；开启时仅起读首句单独请求，后续继续按用户配置合并，不再固定拆成 64/62 字符。超长句子优先在词间空白或分句标点处分块，无可用边界时才按字符兜底并保留 UTF-16 代理对；不重复首句、不改变正文坐标，替换规则扩张的单句仍按用户字数上限校验。首请求先启动，完成或 600ms 后才补充其他预取；暂停、换音色、跳读取消迟到补充。旧配置保持原值，系统音色仍遵守 300 字限制。预取不等于消除服务端慢响应或音频内静音，不做固定时长裁剪。

调度参考轻页提交 `2e10cf13bb09f68e3c0c0c5b052d64d09d0eaee9` 的 [SystemTtsReader](https://github.com/wip3l/qingye-reader/blob/2e10cf13bb09f68e3c0c0c5b052d64d09d0eaee9/entry/src/main/ets/utils/SystemTtsReader.ets)（600ms 首请求优先、结果队列）及 [TtsAvAudioPlayer](https://github.com/wip3l/qingye-reader/blob/2e10cf13bb09f68e3c0c0c5b052d64d09d0eaee9/entry/src/main/ets/utils/TtsAvAudioPlayer.ets)（驻留播放器和会话隔离）；分块长度由本项目合成配置控制。未整份替换上游播放器，也未采用其无界脚本接口。SpeechQueue 脱敏阶段日志只含任务编号、字符数、阶段、接收字节数和状态码，不记录正文、URL 或凭据。

2026-11-05 实机复核：旧策略在 12:40:45 等待下一段，重试后到 12:42:04 才拿到音频；日志确认卡在合成传输而非播放器 reset。短段版本经 65 项朗读回归、真实 HTTP 播放器模拟平台生命周期测试及 Release SDK 构建后覆盖安装。新进程 7354 首批请求仍出现零数据或部分数据后连接未结束的失败；恢复后 12:52:55–12:54:38 连续切段均命中预取。12:54:18 第 116 章自然进入第 117 章，接管 4 个已准备片段，前五段均 ready=true；随后用户拖动、切音色和连续调速另计，不当作自然衔接样本。该批共观察到 25 个片段播放完成。没有录音听感验收，不把短段队列优化描述为已消除网络传输异常或所有音色的等待。

HTTP 合成区分访问拒绝、限流、超时/网络、服务端错误、坏配置、无效音频、明确音色不可用。只对网络、408、429、5xx 按配置有限重试；不显示服务原文或认证字段。明确 voice_not_found / voice_unavailable / unsupported_voice / hd_synthesis_failed 在本次进程内记忆 5 分钟，重新选择该音色可清除；不因一般网络错误封禁音色。批量 inputs 协议及按书持久 TTS 缓存尚未接入。


朗读页章节列表复用 `ChapterCacheIndicator` 展示电子书正文缓存，TTS 与阅读器统一使用 `sourceUrl + (bookUrl || bookId) + (originSourceValue || source.value)`。正文命中不代表语音已合成；加载提示区分“读取章节正文”和“准备语音”，中间按钮在朗读加载期间可取消。HTTP TTS 使用 `requestInStream` 有界收集完整音频，每次收到非空数据刷新空闲超时；系统传输及应用总期限为配置超时的 4 倍（最大 480 秒），仍限制 8 MiB，取消/断流/超限不播放半份音频。避免原先持续传输被固定 30 秒整次期限中断后重复请求。此实现不是边下载边播放，不承诺消除服务端合成等待。


自定义 HTTP TTS 支持跨章连续预合成：本章剩余待播片段少于合成并发额度时，使用空闲请求槽准备下一章开头；完成一段后继续补充，最多保留下一章“并发数 + 1”个片段，包含短首句后的第二段，不提前播放或推进进度。“读完本章停止”不触发跨章预合成。自然跨章与从目录/下一章按钮进入相同章节均可接管已完成或进行中的同一请求；书籍/来源/章节地址、音色定义、合成参数必须匹配，阅读替换后逐段校验文本。固定合成速度的音色直接调整播放器倍速，下载中切速也使用最新倍速，不取消已合成音频；模板使用速度变量时才重新合成。暂停、换音色、改变合成速度、跳章等撤销过期预取；预取失败不打断本章，到章时按普通路径重新合成。播放器 reset/release 各有 1.5 秒等待上限，失败或超时的实例不再复用。系统音色目前仍仅预合成当前章的下一片段。语音只暂存在内存，不等同于按书离线音频下载；任意跳到未预取章节或提供方合成慢于播放消费时仍可能等待。


## EPUB 原版精排预设

新导入的文字 EPUB 自动生成当前书专属的“EPUB 原版精排”，默认使用书内字体、背景、标题、内联样式及插图。阅读页“字体 → 预设主题”显示书名和当前选中状态，选择羊皮纸、夜间、纯黑或自定义主题切换为应用排版，点击原版卡片恢复书内效果；该选择仅作用于当前书，不占自定义主题名额。原版与应用排版共用覆盖、仿真、无动画翻页以及页眉页脚、阅读状态、点击区域和按键入口；字体、字号、行距、边距等设置保留，手动调整时切换到应用排版，可随时重新选中原版主题。原版排版、分页和文字定位复用轻页 EpubOriginalScript；公共 ArkUI 翻页组件处理手势、截图动画与提交，Web 不再重复处理横向滑动和点击。分页通过视口横向滚动切换多栏，不平移 body；书内固定背景覆盖完整阅读区，页眉页脚透明叠放并采用原书字色。预览阶段不提交位置，滑动取消后恢复原页，跨章同样遵循该规则；系统主题不直接改写原书颜色。

两种排版共用原目录、章节 ID、书签、朗读和字符进度，切换先保存当前位置；窗口变化按文字定位恢复。原版支持目录跳章、横向翻页、竖向滚动及按键翻页。页眉页脚覆盖层及其全部子控件使用 API 20 的 `HitTestMode.BLOCK_DESCENDANTS` 退出触摸测试，避免全屏 `Blank` 截住正文上下滚动和点击；不能退回只排除容器自身的 `None`。背景资源不进入文字或朗读流。旧导入文件需要重新导入才生成此预设；不支持原版 Web 或加载失败时保留应用排版。验证重点为带嵌入字体和背景的实书、同章多 spine/同文件多目录锚点、主题往返和重启记忆；连续滚动须检查上下滑动、点击显隐工具栏和返回后位置恢复。

精排竖向阅读使用同一 Web 内的有界连续窗口：靠近边缘提前载入相邻片段，章末与下一章正文可同屏，连续手势和惯性可跨章，不再要求到章末后重新上拉 72px。每个片段保留独立的原书 CSS、字体和背景，最多常驻 5 个文档；上游多栏分页及文字定位继续复用。章节和进度在正文进入阅读线时提交，预加载不改进度、不提示已到书尾。前插、回收、窗口宽度变化和章末恢复保持字符位置；预加载失败保留当前正文并允许后续滚动重试。

连续模式的触摸、滚轮和惯性由浏览器原生滚动链处理；移除脚本逐帧模拟手势、每事件测量 iframe 坐标和重复调度。普通正文按内容高度展开，直接随外层滚动，不再逐帧调用内层 scrollTo；含绝对/固定/粘性定位、固定背景或高度/方向相关媒体条件的章节保留一屏高视口兼容路径。普通正文的视口单位转换为真实阅读区域的逻辑尺寸，页码也按阅读区域计算，避免 iframe 扩高改变原书排版或页数。章节位置仅在增删或尺寸变化时更新；字符定位在停滚 160ms 后回报，长时间滚动最多每秒回报一次，跨章和显式位置捕获立即报告。阅读进度与记录写盘合并，离页/后台仍立即保存最近位置。原书页内横向画廊和纵向溢出区域使用原生滚动；分页模式的页内手势仍由宿主转发。单图/SVG 封面在阅读区域内居中，保留原书明确的覆盖裁剪规则；多看画廊按页横向滚动。原书离线脚注段评使用原生列表，关闭由弹层双向绑定驱动，内容在消失后清理。

2026-11-08：真实 Chromium 布局回归覆盖跨章同屏、反向滚动、章末字符恢复、宽度变化、样式隔离及文档数量上限；通过 CDP 注入真实触摸，确认一次手势跨章，普通正文滚动中子视口 scrollTo 调用为 0，视口单位与页码按阅读区域计算，固定背景章节回退到一屏高视口。封面/画廊、翻页和进度合并/立即退出保存回归通过；Release SDK 26.0.0.105 增量 debug HAP 构建通过，包内两份滚动脚本与源码一致，最低 API 20 / 目标 API 26、Release 渠道。最终正文直接滚动版已覆盖安装 VYG-AL00；实机《十日终焉》从第 9 章连续滚到第 10 章，反向滚动正常，退出后继续阅读仍为第 10 章且首个可见段落相同。

13:01:48–13:01:54 的 SmartPerf/Trace 短采样中，持续滑动的部分样本为 117–120 帧；样本也包含手势间停顿，长帧间隔尚未逐一归因，不能据此声称所有精排书已无卡顿，也不能与不同起点的旧采样计算提升百分比。主线程仍观察到 Preferences 回调及 GC 耗时，特殊布局兼容路径未覆盖全部实书。离线段评关闭/重开、原书封面和画廊仍需补充实机验收。

2026-11-07：在手机上的《诡秘之主》原版精排复现正文滑动、点击被覆盖层拦截；修复后验证上下滚动、点击显隐工具栏，以及退出书架后恢复到同章同一段文字。Release SDK 26.0.0.105 增量 debug 构建并覆盖安装通过，最低 API 20 / 目标 API 26。依据在线 [ArkTS 语法规范](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[ArkUI 交互规则](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/18-arkts-rules/arkts-interaction-rules.md) 及 [触摸测试控制示例](https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/reference/apis-arkui/arkui-ts/ts-universal-attributes-hit-test-behavior.md)，并核对本机 SDK 枚举的 `@since 20`。

### 小说段评

书源返回明确正数段评计数的段落在末字后显示小气泡，零条及未提供计数的通用入口不显示。翻页、横屏双栏和连续滚动均使用完整正文宽度，左右边距保持对称；段尾放不下气泡时只为该段增加图标行，避免满行遮字。点击在阅读页打开可拖动弹框，评论统一使用原生头像、昵称与圆角对话气泡，回复缩进并保留回复对象；提供加载、空状态、失败重试及关闭。段评与 AI 结果弹层共用 AppMaterial.ReaderSheetThick 固定厚沉浸材质，内容及加载/空态区域保持透明，评论气泡使用约 50% 不透明度的独立背景资源（浅色为白色，深色为柔灰色）与 1vp 细描边，以轻盈底色和清晰轮廓区分沉浸底层，不逐条叠加背景模糊；标题、正文、昵称和时间使用系统分层文字色，旧系统保留磨砂回退。关闭后保留阅读位置；弹框显示期间暂停自动翻页并释放阅读翻页按键订阅。段评随章节缓存保存；更新或重启后若内存上下文恢复失败，自动通过原书源重建对应章节一次，仅在原段落入口校验通过后重新打开评论。恢复有 20 秒限时并支持取消，不清正文缓存、不移动阅读位置；旧缓存联网补齐失败仍可离线阅读；书源未提供段评时不显示入口。段评地址／脚本不进入正文、复制和朗读。

设备回归：有／无段评段落、长段跨页、末行满宽、字体或窗口改变、连续滚动相邻章节、点击后不误翻页、弹框失败重试／关闭／后台释放、章节字符位置恢复。

2026-11-08：Release SDK 26.0.0.105 增量 Debug HAP 构建与段评、正文缓存、轻页书源引擎回归通过，已覆盖安装至 HUAWEI Mate 80。《一念永恒》第 1 章实机确认正文左右边距对称，点击气泡可展示 16 条真实评论及头像、回复关系、点赞数。修复段评请求与正文变量上下文不一致导致的入口失效；秒／毫秒时间戳格式化有定向回归覆盖。连续滚动、横屏双栏和折叠屏未做本轮实机验证。

随后段评沉浸背景及评论气泡对比度调整已完成：气泡使用独立深浅色资源与 1vp 描边，并按反馈将背景不透明度从约 90% 调为约 50%，外层沉浸材质保留。修改组件的 ArkTS 检查无错误（原有 Circle.fill 版本提示仍在，本机 Release SDK 声明支持 ResourceColor），Release SDK 26.0.0.105 增量 Debug 构建通过，HAP 元数据为 Release / API 20–26。实现参照已读取的 [ArkTS 语法规范](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)和 [ArkUI 半模态参考](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/08-dialog-menu/dialog/arkts-sheet-page.md)。

同日覆盖安装后的旧章节故障，实机日志记录“评论上下文不可用，请刷新本章”；正文缓存保留段评入口，但进程内评论上下文需重新建立。本次增加首次恢复失败后的一次正常正文链重建，轻页书源引擎回归通过，约 15:35 覆盖安装至 HUAWEI Mate 80 并成功启动。用户随后确认原来打不开的章节已能显示评论。气泡最终浅色效果尚未单独完成视觉复核；不将用户确认的加载恢复扩大为全部外观或设备验收。


## 多角色朗读导入与绑定

阅读器右上角菜单提供“角色配音”，以现有 ReaderSheetThick / ReaderSheetBlur 半模态面板呈现，内容层透明且采用系统主/次文字色。“我的 → 阅听设置 → 多角色朗读”复用同一配音组件，沿用磨砂标题、AppTheme.Surface、AppRadius / AppSpace、760vp 最大宽度及底部安全区。启用开关明确为全局作用；“模型管理”紧接开关下方，进入独立二级页。无模型时展示准备模型入口；模型页提供导入/替换、复制下载地址、取消与删除确认，复制百分比只显示一个 %，模型验证单独显示等待状态。离页取消在途导入，失败或取消保留旧模型。

本书音色区显示书名、旁白、默认对白及逐步发现的人物。点击后切换为音色编辑视图，可搜索已启用音色、选择、试听，再明确确认保存；取消不改原绑定。列表懒加载并使用角色/音色 ID，滚动条隐藏。“试听当前片段”作为无背景文字按钮放在书名右侧，随角色列表滚动；独立设置页的标题和底部安全区留白使用列表内容偏移，避免外层留白提前截断卡片。编辑视图的试听和确认仍固定在列表外并避让底部安全区。试听不写入阅读进度，只恢复本次试听暂停的同一朗读会话；主动暂停、换书、后台或音频抢占撤销自动恢复。确认音色保留当前发声片段，从下一片段使用新声音。角色绑定按书保存，不改变全局音色；无当前书时给出开始朗读的提示。

2026-11-10：改动 ArkTS 检查无错误，Release SDK 26.0.0.105 Debug HAP 构建通过；78 项 TTS 回归与音色试听回归通过，覆盖下一片段生效、字符位置保留、重复关闭、连续试听与中断取消恢复。模型推理边界使用 mock。Mate 80 已安装并检查新版界面；真实模型识别质量、持续后台功耗、深色和其他窗口尺寸尚未全部验收。

## 读书摘录

- 电子书长按拖动选区后点“保存摘录”；成功、重复、失败、超出 20000 字分别提示。覆盖普通分页、连续滚动和 EPUB 原版选文。保存停止自动阅读，保留正文与阅读进度。
- “阅听记录 → 筛选旁的摘录按钮”按书归集，封面交替向左右倾斜；旋转图层保留透明边距并高质量采样，右侧圆按钮中的箭头居中。书籍卡片收紧至约 100vp 高，采用 52×72vp 封面和 10vp 列表间距，使用懒加载与分页。阅读页菜单提供“本书摘录”。
- 书籍卡片、摘录列表卡片、详情和导出分享卡片统一使用低对比的边角曲线与圆点花纹；页面由 Stack 中独立的 Image 图层显式显示花纹，SVG 不透明度为 0.22，正文、日期和出处清晰可读。
- 本书列表显示时间、原句预览和章节，点击查看全文；复制带书名作者，删除需确认，返回后刷新条数。卡片详情右上角依次放置复制、分享、删除按钮；分享菜单提供图片卡片和文字两种选项，不设置底部操作栏，内容背景自然延伸到底部安全区。卡片品牌区以圆角应用图标与深灰“简听阅读”整体居中，页面 32vp 图标采用 8vp 圆角，导出 64px 图标采用 16px 圆角；系统分享面板负责目标选择。
- 长摘录分成多张卡片，最多 60 张且不静默截字；超过上限提示文字分享。数据本机持久保存，未接入手动备份与云同步。

花纹显式图片层与品牌图标圆角调整的最终真机效果仍待验证。

开发依据（本次在线读取，按项目 ArkUI V2 规则应用）：[ArkTS 语法](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[ArkUI 检索与 V2 规则](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md)、[图片分享技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/sdk/hmos-one-sdk-skill/hmos-sdk-basic-skill/Share%20Kit(%E5%88%86%E4%BA%AB%E6%9C%8D%E5%8A%A1)/hmos-share-kit-share-image/SUB_SKILL.md)。
