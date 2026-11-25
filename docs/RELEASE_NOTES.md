# 1.1.20 更新日志（2026-11-25）

1. 新增漫画智能去水印，支持导入本地图像模型，在设备内处理页面水印。
2. 多角色朗读接入已有 AI 配置，结合对白上下文识别人物，并根据人物特征匹配音色。
3. 新增逐个人物“AI 重新配音”，支持试听与确认保存；角色声音保持稳定，手动选择优先。
4. 新增“杏笺书斋”主题，提供深浅色背景、书封与个人卡片，切换主题时保留用户材质选择。

## 发布配置

- 版本代码：1030001，沿用现有发布签名与会员权益配置。
- 邀请测试覆盖当前全部测试组：简听外部体验（275 人）、内测组（1 人）；开启测试通知，关闭上架自检，测试期截至 2026-12-25 23:59:59（北京时间）。
- 发布归档目录：`artifacts/releases/1.1.20-1030001/`。

## 构建与邀测记录

- Release SDK 26.0.0.105 的发布签名 APP 构建成功；包内元数据为 1.1.20 / 1030001、release 模式、debug=false、最低 API 20、目标 API 26。发布包、混淆映射、更新说明与回执已归档。
- 2026-11-25 邀测提交返回 `ret.code=0`，版本 ID：`2091535054395148288`，软件包 ID：`2091536767290224384`。提交后回读状态码为 7，后续开放时间由平台处理结果决定。
- 两组均已绑定（`bind=1`），测试通知开启（`needNotify=1`）；测试期为 2026-11-25 18:31:21 至 2026-12-25 23:59:59（北京时间）。通知送达由 AGC 执行。
- 创建时明确关闭上架自检（`onshelfSelfDetect=0`），提交前查询确认无自检任务。
- 具体回执见 `artifacts/releases/1.1.20-1030001/release-progress.json`。本轮沿用 [AGC 发布技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/05-launch-and-distribute/hmos-connect-api-cli-skill/SKILL.md)及[邀测流程](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/05-launch-and-distribute/hmos-connect-api-cli-skill/references/workflows.md)，字段依据[测试版本更新接口](https://developer.huawei.com/consumer/cn/doc/doccenter-connect-api/agc-help-test-api-modify-test-version-0000002271160657)和[测试通知说明](https://developer.huawei.com/consumer/cn/doc/doccenter-connect-api/agc-help-test-api-data-testtaskinfo-0000002272455649)。

---

# 1.1.19 更新日志（2026-11-24）

1. 优化本地多角色朗读识别与音色衔接，按设备能力优先使用 NNRT 加速，并支持 CPU 执行。
2. 新增音频共存设置，可按需让有声书与文字朗读和其他应用音频同时播放。
3. 优化搜索选项与文字匹配，支持简繁同搜，并改善精确搜索和作者搜索操作。
4. 优化作品切换后的结果展示与复用，缩短重复检索等待。
5. 优化迷你播放器展开、拖动、封面衔接及章节开头朗读体验。

## 发布配置

- 版本代码：1029001；邀测与正式版沿用现有发布签名和会员权益配置。
- 邀请测试覆盖当前全部测试组：简听外部体验（270 人）、内测组（1 人）；开启测试通知，关闭上架自检与自检报告通知，即刻生效，测试期 30 天。
- 正式版本选择全网发布，审核通过后立即上架。

## 构建与发布记录

- 使用 Release SDK 26.0.0.105 与发布签名完成 APP 构建；包内元数据确认版本 1.1.19 / 1029001、Release 模式、debug=false、最低 API 20、目标 API 26。签名包与元数据归档于 `artifacts/releases/1.1.19-1029001/`。
- 2026-11-24 邀请测试提交成功，版本 ID：`2090552872465860608`，软件包 ID：`2090558844030737472`；AGC 查询状态码为 4。简听外部体验（270 人）与内测组（1 人）均已绑定，测试通知开启（`needNotify=1`），测试期为 2026-11-24 09:57:47 至 2026-12-24 23:59:59（北京时间）。
- 上架自检与自检报告通知均关闭（`onshelfSelfDetect=0`、`onshelfSelfDetectNotice=0`）；自检任务查询结果为空。
- 2026-11-24 正式版提交接口返回 `ret.code=0`。正式版本 ID：`2090552313675570240`，软件包 ID：`2090560580707462912`；AGC 回查状态码为 12。版本选择全网发布（`releaseType=1`），审核通过后立即上架。
- 邀测与正式版回执归档于 `artifacts/releases/1.1.19-1029001/release-progress.json` 和 `formal-release-receipt.json`。正式版更新说明归档为 `formal-whatsnew.txt`。
- 本轮完成 Release 构建、邀测与正式版 AGC 提交及代码交付；实机安装安排在独立设备操作中。
- 发布流程参照 [AGC 提交应用审核接口](https://developer.huawei.com/consumer/cn/doc/App/agc-help-publish-api-app-submit-0000002271160585)、[AGC 发布技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/05-launch-and-distribute/hmos-connect-api-cli-skill/SKILL.md)及[发布流程](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/05-launch-and-distribute/hmos-connect-api-cli-skill/references/workflows.md)。

---

# 1.1.18 更新日志（2026-11-21）

1. 优化本地 AI 字幕的识别分段、时间对齐与跨窗口拼接，改善字幕刷新及当前句定位。
2. 优化迷你播放器展开、收起与拖动转场，完善沉浸材质及横竖布局下的播放控制衔接。
3. 优化书籍详情页的阅读与收听入口，目录加载期间可进入目标页面，并按历史位置或选中章节继续。
4. 优化主页面页签切换与书房滑动操作，提升连续浏览体验。

## 发布配置

- 版本代码：1028001；邀请测试沿用现有会员权益配置。
- 覆盖 AGC 当前全部测试组：简听外部体验（258 人）、内测组（1 人）；开启测试通知，关闭上架自检及自检报告通知。
- 测试期沿用 30 天，分发方式设为即刻生效。平台自动预审照常执行，外部组开放时间以审核结果为准。

## 构建与验包

- 使用 Release SDK 26.0.0.105 与现有发布签名完成 APP 构建；包内元数据确认版本 1.1.18 / 1028001、Release 模式、debug=false、最低 API 20、目标 API 26。
- 签名 APP 归档于 `artifacts/releases/1.1.18-1028001/Jianting-1.1.18-1028001-release.app`，包体约 56.1 MB。
- 变更 ETS 的静态检查提示 API 可用性及现有规则告警；Release ArkTS 编译、打包与签名完成。
- MCP 构建遇到 OHPM 批处理递归错误；使用 `.env` 指定的 Release IDE Hvigor CLI 与 `--no-daemon` 完成构建。构建日志另有组件 ID 与依赖资源声明提示。
- 本轮完成 Release 构建与包内元数据核对，未新增设备实机操作验证。
- 发布参考本轮读取的 [AGC 发布技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/05-launch-and-distribute/hmos-connect-api-cli-skill/SKILL.md)、[邀测流程](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/05-launch-and-distribute/hmos-connect-api-cli-skill/references/workflows.md)、[AGC 命令说明](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/05-launch-and-distribute/hmos-connect-api-cli-skill/references/commands.md)与 [Hvigor 构建技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-studio-hvigor/SKILL.md)。

## AGC 邀测提交记录

- 2026-11-21 邀请测试提交接口返回成功；版本 ID：`2088782561915481856`，软件包 ID：`2088784240677264768`。
- 已绑定当前全部测试组：简听外部体验（258 人）、内测组（1 人）；测试通知开启（`needNotify=1`），测试期为 2026-11-21 23:22:54 至 2026-12-21 23:59:59（北京时间）。
- 分发方式为即刻生效（`sendMode=0`）；上架自检与自检报告通知关闭（`onshelfSelfDetect=0`、`onshelfSelfDetectNotice=0`）。自检报告查询返回“self detect task is not exist”。
- AGC 版本列表当前返回状态码 4；平台审核与外部组开放时间以 AGC 后续状态为准。通知已配置开启，实际送达由平台执行。
- 邀测提交回执归档于 `artifacts/releases/1.1.18-1028001/release-progress.json`。

---

# 1.1.17 更新日志（2026-11-21）

1. 优化阅读排版与翻页效果，改善横屏双栏、连续翻页及阅读位置恢复体验。
2. 优化电子书导入与内容解析，完善书名、作者、封面和正文展示。
3. 优化音频播放与文字朗读，改善播放中断、进度保存、定时停止及前后台切换衔接。
4. 优化首页榜单、搜索结果与页面切换，减少重复加载，保留返回页面时的浏览位置。
5. 优化书架、书房及阅听记录布局，完善分类统计、筛选和不同窗口尺寸下的显示。
6. 优化设置页面、长文本展示及操作反馈，提升日常使用的流畅性与稳定性。

## 发布配置

- 版本代码：1027001；邀请测试与正式版共用已验证的 Release 签名 APP，沿用现有会员功能配置。
- 覆盖全部现有测试组，开启测试通知，关闭上架自检及自检报告通知，选择即刻生效。
- 正式版本：全量发布，审核通过后立即上架。正式版更新说明按用户要求仅描述体验优化，不涉及书源相关内容。

## 构建与发布记录

- 发布包、混淆映射、验包结果与邀测回执归档于 `artifacts/releases/1.1.17-1027001/`。
- 使用 Release SDK 26.0.0.105 和现有发布签名完成 APP 构建；验包确认 1.1.17 / 1027001、release 模式、debug=false、最低 API 20、目标 API 26，资源及混淆契约检查通过。
- 已执行变更 ETS 的独立静态检查；构建 MCP 遇到既有 OHPM 批处理递归错误，改用同一 Release IDE 的 Node/Hvigor CLI 完成编译与签名。
- 本次发版未新增设备功能验收；既有实机观察与待验证项见 `docs/APP_UI.md`、`docs/LIGHT_SOURCE_SYNC.md`，原生源真实登录及登录后阅读仍待验证。
- 发布参考本轮读取的 [AGC 发布技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/05-launch-and-distribute/hmos-connect-api-cli-skill/SKILL.md)、[邀测流程](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/05-launch-and-distribute/hmos-connect-api-cli-skill/references/workflows.md)与 [Hvigor 构建技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-studio-hvigor/SKILL.md)。目录 API 返回 HTTP 429，未完成目录树刷新，使用当前索引提供的技能路径。

## AGC 提交记录

- 代码提交：`3dc7ccf`，已通过 SSH 推送至 GitHub。
- 2026-11-21 邀请测试提交接口返回成功，版本 ID：`2088145811723549504`，软件包 ID：`2088147865858760512`。页面显示正在执行平台自动预审，通过后自动转交审核；外部测试组待审核通过后开放。
- 全部测试组已绑定：简听外部体验（254 人）、内测组（1 人）；测试通知开启（`needNotify=1`），实际送达由平台执行。
- 上架自检及自检报告通知均关闭（`onshelfSelfDetect=0`、`onshelfSelfDetectNotice=0`）；平台自动预审由提交审核触发，与可选上架自检分开执行。
- 分发使用即刻生效模式（`sendMode=0`），未设置延后开始。测试窗口为 2026-11-21 02:15:30 至 2026-12-21 23:59:59（北京时间）。
- [邀请测试链接](https://appgallery.huawei.com/apptest/join/76b3950e34e16d575fa92a209fc631dd)。提交回执已归档于本版本目录的 `release-progress.json`。

## 正式版提交记录

- 2026-11-21 已将原正式版草稿更新为 1.1.17（1027001），复用本版本已验证的 Release 签名 APP；正式版软件包 ID：`2088404263746173760`，版本 ID：`2087223444285455168`。
- 提交接口返回 `ret.code=0`，后台确认状态为“预审中”。选择全网发布（`releaseType=1`），审核通过立即上架（`releaseTime=0`）；实际开放时间由平台审核决定。
- 正式版更新说明已同步本页、`CHANGELOG.md` 和上架素材。六项均为体验优化表述，覆盖自线上 1.1.13 以来的阅读、导入、播放、首页、搜索和界面改进。
- 正式版说明与提交回执归档为 `formal-whatsnew.txt`、`formal-release-receipt.json`；邀测提交时的原始记录保持独立留存。
- 本轮沿用已读取的 AGC 发布技能，并读取其 [正式发布流程](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/05-launch-and-distribute/hmos-connect-api-cli-skill/references/workflows.md)；已刷新在线根目录及发布技能目录。

---

## 1.1.16 更新日志（2026-11-20）

1. 优化首页、书架、阅听记录及个人中心的页面切换，改善连续操作和返回页面时的内容衔接。
2. 优化全网榜单加载与刷新，优先展示当前浏览内容，保留返回时的轮播位置，减少重复加载。
3. 新增榜单滑动音效与触感，横向切换书籍时提供轻响和轻微振动，可在设置中统一开启或关闭。
4. 优化多书源搜索与结果列表更新，改善搜索期间的滑动、类型筛选和网格、列表切换体验。
5. 优化书源封面加载与缓存复用，减少重复读取，改善大量书籍封面同时展示时的响应。

## 发布配置

- 版本代码：1026001；本次发布渠道为邀请测试，沿用现有会员功能配置。
- 覆盖全部现有测试组，开启测试通知，关闭上架自检及自检报告通知，选择即刻生效。

## 构建与发布记录

- Release SDK 26.0.0.105 与发布签名 APP 构建通过；验包确认 1.1.16 / 1026001、release 模式、debug=false、最低 API 20、目标 API 26，资源及混淆契约校验通过。
- 独立 ArkTS 检查受 LSP 未初始化影响；构建 MCP 遇到既有 OHPM 批处理递归错误，使用同一 Release IDE 的 Node/Hvigor CLI 完成编译与签名。
- 发布包、混淆映射、验包结果和邀测回执归档于 `artifacts/releases/1.1.16-1026001/`。
- 已有实机验证记录见 `docs/APP_UI.md` 与 `docs/LIGHT_SOURCE_SYNC.md`；本次发版完成 Release 构建及验包。榜单音效强弱、振感与开关实景仍待测试组确认。
- 发布参考本轮读取的 [AGC 发布技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/05-launch-and-distribute/hmos-connect-api-cli-skill/SKILL.md)与 [Hvigor 构建技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-studio-hvigor/SKILL.md)。

---

## 1.1.15 更新日志（2026-11-19）

1. 优化 EPUB 与基础排版的仿真翻页，改善连续点击、反向滑动和跨章节切换时的画面衔接。
2. 修复部分 EPUB 横屏双栏正文裁切、多行标题重叠的问题，完善窗口变化后的重新排版与阅读位置恢复。
3. 扩展未加密 MOBI、AZW3 电子书兼容范围，新增 HUFF/CDIC 压缩内容解析，完善书名、作者、封面和正文导入。
4. 统一有声书与文字朗读的系统音频处理，优化提示音、播放中断和恢复衔接，简化相关设置。
5. 优化智控键翻页的设备能力识别，仅在支持的设备上显示入口，完善小说与漫画阅读设置。

## 正式版补充说明

正式版相对线上 1.1.13，另包含：

6. 更新阅听记录概览，以近七日柱状图展示漫画、阅读和有声书时长，完善分类统计与筛选。
7. 优化书架、书房及最近阅听布局，完善后台播放状态同步、缓冲恢复与漫画连续滚动体验。

## 发布配置

- 版本代码：1025001；邀请测试与正式版共用发布签名 APP，沿用现有会员功能配置。
- 邀请测试：绑定全部现有测试组，开启测试通知，关闭上架自检及自检报告通知，选择即刻生效。
- 正式版本：提交审核，选择审核通过后立即上架，实际开放时间以 AGC 审核为准。

## 构建与发布记录

- 发布包与混淆映射归档目录：`artifacts/releases/1.1.15-1025001/`。构建和提交结果完成后按实际回执记录。
- 本次发布使用发版开始时已有的阅读、导入与音频改动；构建期间另一任务新增的首页性能优化保留在原工作区，不纳入此版本。
- 发布操作参考本轮读取的 [AGC 发布技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/05-launch-and-distribute/hmos-connect-api-cli-skill/SKILL.md)及 [Hvigor 构建技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-studio-hvigor/SKILL.md)。
- 本轮未新增设备功能验收；已有阅读实机观察与待复核项见 `docs/APP_UI.md`，不将构建成功作为动态效果验证。

---

## 1.1.14 更新日志（2026-11-19）

1. 音频播放方式新增“暂时压低音量”，在系统允许的短暂音频提示期间降低音量并继续播放，提示结束后恢复音量。
2. 修复部分场景下文字朗读被打断后无法自动续读的问题，完善后台任务状态识别和朗读位置恢复。
3. 优化有声书后台播放与系统播控的状态同步，完善长时间缓冲后的恢复和失败提示，保留当前章节与播放进度。
4. 更新阅听记录概览，以近七日柱状图展示漫画、阅读和有声书时长，优化分类统计、筛选及深浅色显示。
5. 优化书架与书房的立体封面、分组展示和最近阅听布局，改善不同窗口尺寸下的浏览体验。
6. 完善 EPUB 原版排版、横屏双栏及含插图页面的仿真翻页，优化漫画连续滚动与阅读位置保存。
7. 新增未加密 AZW3/KF8 文件导入支持，完善正文、插图和封面解析，统一文件选择、压缩包及外部打开入口。

## 发布配置

- 版本代码：1024001；本次发布渠道为邀请测试。
- 全部现有测试组，开启测试通知，关闭上架自检及自检报告通知，选择即刻生效。
- 沿用现有会员功能配置。

## 验证记录

- 设置页面已在实机确认三种音频播放方式显示正常，TTS 已起播并连续播放下一段。
- 后台任务恢复逻辑的定向模拟验证通过；同类耳机打断后的自动续读仍待实机复测。
- 独立 ArkTS 检查受 LSP 初始化问题阻塞，构建工具受 OHPM 批处理递归问题阻塞；发布构建使用已验证可用的 Release IDE Node/Hvigor CLI。

## 构建与发布记录

- Release SDK 26.0.0.105、商店发布签名构建 APP 成功；验包确认 1.1.14 / 1024001、release 模式、debug=false、最低 API 20、目标 API 26，资源和混淆契约检查通过。
- 签名 APP、混淆映射和正式更新说明归档于 `artifacts/releases/1.1.14-1024001/`。
- AGC 邀测草稿已创建，提交完成后补充实际回执。

---

## 1.1.13 更新日志（2026-11-18）

1. 完善在线小说插图展示，支持在分页、双栏和连续滚动中按正文顺序显示书源提供的图片，保留图片比例及段评、朗读的位置对应关系。
2. 优化纯文字覆盖翻页，提前准备当前页画面，减少起拖时的截图等待；完善后台返回、快速连续翻页和取消手势时的状态衔接。
3. 播放进度新增长按轨道调节，按住后可左右拖动预览目标位置，松手完成跳转；保留滑块拖动，减少轻触误跳。
4. 统一单本书籍的分组设置与分组管理入口，支持选择归属及维护分组；书房分组弹层记住全屏或半屏显示偏好，重新打开后恢复。

## 发布配置

- 版本代码：1023001。
- 邀请测试：全部现有测试组，开启测试通知，关闭上架自检及自检报告通知，选择即刻生效。
- 正式版本：提交审核，选择审核通过后立即上架；实际开放时间由 AGC 审核决定。

## 构建记录

- 使用 Release SDK 26.0.0.105 与现有发布签名构建 APP；验包确认版本 1.1.13 / 1023001、release 模式、debug=false、最低 API 20、目标 API 26，资源及混淆导出检查通过。
- 阅读翻页、在线插图与段评、正文分页、书房及分组管理五组定向主机回归通过。
- 构建 MCP 的 OHPM 批处理递归失败，改用同一 Release IDE 的 Node/Hvigor CLI 完成构建。本次未新增设备验收；已有覆盖翻页实机记录见 `docs/APP_UI.md`。
- 修改的 ETS 独立检查完成，未阻断 Release 编译；保留现有兼容性、异常处理和样式类警告。

## AGC 提交记录

- 代码提交：`f6b9e21`，已通过 SSH 推送至 GitHub。
- 2026-11-18 邀请测试提交成功，版本 ID：`2086391563394513728`，软件包 ID：`2086393541889647872`。
- 全部测试组已绑定：简听外部体验（239 人）、内测组（2 人）；开启发送测试通知，关闭上架自检。测试开始时间为提交当日 16:16:22，结束时间为 2026-12-18 23:59:59（北京时间），未设置延后开始；外部组开放以 AGC 审核为准。
- [邀请测试链接](https://appgallery.huawei.com/apptest/join/772f49c237fd3ac5751ddd9696af3e75)。
- 正式版本提交成功，版本 ID：`2086393427217376512`，软件包 ID：`2086394443086199616`。提交后回读状态码为 12；全网发布、未设置定时发布时间，审核通过后立即发布。
- 两个版本查询均返回“self detect task is not exist”，未生成自检任务。测试通知已配置开启，实际送达由 AGC 执行。
- 签名 APP、混淆映射及提交回执归档于 `artifacts/releases/1.1.13-1023001/`。
- 发布操作依据本轮读取的 [在线 AGC 发布技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/05-launch-and-distribute/hmos-connect-api-cli-skill/SKILL.md)、[测试版本更新接口](https://developer.huawei.com/consumer/cn/doc/doccenter-connect-api/agc-help-test-api-modify-test-version-0000002271160657)及[正式提交接口](https://developer.huawei.com/consumer/cn/doc/App/agc-help-publish-api-app-submit-0000002271160585)。官方 CLI 的正式提交缺少 `appId` Query 参数，已在任务临时副本按接口规范补齐后提交，未修改项目配置。

## 正式版更新说明

正式版沿用以上四项说明，并补充自线上 1.1.10 以来的更新：

5. 完善书架分组的新增、重命名、排序与启停，以及隐藏书架的确认和后台锁定。
6. 新增“仅 Wi-Fi 缓存”设置，优化音频预加载、下载与网络切换后的任务恢复。
7. 优化 EPUB、HTML 文件排版的横屏双栏和深色显示，完善漫画逐书翻页设置、阅听记录及页面布局。

## 1.1.12 更新日志（2026-11-18）

1. 更新书架分组管理，支持在同一面板新增、重命名、排序及启停分组。停用分组不影响书籍收藏、原有归属和阅听进度。
2. 统一书房与分组管理的文件夹顺序。支持调整“未分组”和自定义分组的位置，并为文件夹提供区分清晰的浅色与深色配色。
3. 完善隐藏书架操作。单本或批量移入前新增确认；从书籍返回时保留列表，应用切至后台后需长按标题重新显示隐藏书籍。

## 构建与邀测记录

- 版本代码：1022001；代码提交：`eb55fe9`。
- 使用 Release SDK 26.0.0.105 和发布签名构建 APP，验包通过：Release 模式、最低 API 20、目标 API 26，资源和混淆检查通过。
- 书房、分组管理、隐藏书架三组定向回归通过。独立 ArkTS 检查接口超时，Release 构建已完成 ArkTS 编译；本次发布未新增实机验收。
- 2026-11-18 通过 AGC 提交邀请测试，版本 ID：`2086332985082141696`，软件包 ID：`2086334485284019200`。AGC 返回提交成功，外部组开放时间以平台审核为准。
- 全部测试组：简听外部体验（239 人）、内测组（2 人）。开启测试通知，关闭上架自检及自检报告通知，分发方式为“即刻生效”。AGC 查询确认未生成自检任务。
- 配置的测试窗口：2026-11-18 14:21:46 至 2026-12-18 23:59:59（北京时间）。签名包、混淆映射和提交回执归档于 `artifacts/releases/1.1.12-1022001/`。

## 1.1.11 更新日志（2026-11-18）

1. 新增隐藏书架，支持单本及批量移入、移回，保留收藏、分组和阅读进度；隐藏书籍同步从普通书架、搜索及阅听记录中隐藏。
2. 完善书架网格、列表和书房三种视图切换，新增书架本地导入入口，支持调整分组入口显示及书房文件夹顺序，优化宽窗口最近阅听布局。
3. 新增“仅 Wi-Fi 缓存”设置，统一管理音频预加载、章节下载及 AI 字幕的额外音频下载；网络变化时等待并恢复任务，保留手动暂停状态。
4. 完善 EPUB、HTML 文件排版的横屏双栏与深色模式，优化窗口变化后的阅读位置恢复，以及插图、SVG 和视频的尺寸与方向显示。
5. 优化漫画长按临时放大与双指缩放，翻页方式按书独立保存，改善连续阅读和页面切换体验。
6. 优化阅听记录、历史列表及统计展示，完善滚动交互、隐藏书籍筛选和删除确认，保留底层阅读时长与进度。
7. 优化分组管理、批量操作和作品匹配空状态布局，改善深浅色外观、按钮对齐与底部内容衔接。

### 构建与邀测记录

- 版本代码：1021001；代码提交：`9631c3e`。
- 使用 Release SDK 26.0.0.105 和发布签名构建 APP，验包确认 release 模式、debug=false、最低 API 20、目标 API 26，混淆导出及资源校验通过。
- 变更 ETS 静态检查无错误；隐藏书架、隐藏记录、音频缓存网络策略及漫画翻页四组定向回归通过。本次发布任务未新增设备验收。
- 2026-11-18 已通过 AGC 提交 1.1.11 邀请测试，版本 ID：2086229387618820352；平台进入自动预审，外部组需审核通过后开放。
- 全部测试组：简听外部体验（237 人）、内测组（2 人）；发送测试通知开启，上架自检与自检报告通知关闭，分发方式为即刻生效。
- 测试时间：2026-11-18 10:46:43 至 2026-12-18 23:59:59（北京时间）。
- [邀测链接](https://appgallery.huawei.com/apptest/join/cc3835a50af97943a2a7c0c868c94ad0)。
- 正式包、混淆映射、SHA-256 与提交回执归档于 `artifacts/releases/1.1.11-1021001/`。
