# 书源规则

书源格式、字段、表达式和选择器统一参考[公共书源规则开发文档](https://github.com/wip3l/harmony-book-source-engine/blob/main/docs/book-source-development.md)，与轻页共用同一份规范。本文件仅记录简听的宿主接入和限制，不维护第二套规则语法。公共规范已合并到 main。固定引擎提交和同步步骤见[引擎同步](LIGHT_SOURCE_SYNC.md)。

## 支持的定义

- 轻页兼容 JSON：`bookSourceUrl`、`bookSourceName`、`searchUrl`、`exploreUrl`、`ruleSearch`、`ruleExplore`、`ruleBookInfo`、`ruleToc`、`ruleContent`，以及轻页支持的登录、变量、脚本和媒体字段。完整原始定义保留在加密书源库，执行前由轻页原导入方法规范化。
- 轻页原生 JSON：`sourceFormat: "native"`，使用轻页 `NativeSourceSpec` / `NativeSourceService` 的定义和解析逻辑。`vars`、静态/动态菜单、模式/频道、搜索、详情、目录、正文、媒体和交互配置按轻页语义执行。设置和登录状态单独保存在加密运行状态中。
- 当前 `sourceengine` 原生定义支持 `login.form/submit/sendCode` 表单登录及验证码请求、`actions` 设置动作、`content.mediaHeaders` 媒体请求头，以及对象形式 `webView: { waitFor, timeout }`。登录控件使用现有面板，密码等输入不持久化，仅保存登录返回的凭据；网页入口保持 HTTPS-only。等待元素的请求仍遵循书源限流、播放优先级、取消和响应大小限制。
- 文件使用 UTF-8 JSON，可导入单个定义、数组或当前导入器支持的列表包装对象。单文件/订阅最大 25 MiB；不按 1000 个定义截断。本地最多 10 文件，合计 250 MiB。

原简听 `format: "jianting.source"` / `engine: "native-v1"` 格式及其请求/算子引擎已移除，新导入明确拒绝。数据库中的历史定义不自动改写、不删除用户收藏；需换成轻页支持的定义才能解析。

兼容规则源（内部标记 `engine: light`）和原生源（`light-native`）均支持基本、搜索、详情、目录、正文、发现、登录及 JSON 编辑页。原生表单直接编辑原始定义；请求头、提取字段、变量、菜单等字段组与列表可逐层进入、增删和修改，保留原始值类型及未编辑的扩展字段。已有书源的标识地址及格式版本只读；保存和 JSON 切回表单时使用当前导入器校验，不依赖旧引擎的 `nativeRulesValid` 标志。历史停用格式仍仅展示 JSON，不作为可执行源恢复。

## 执行链

`LocalRuleSourceImportParser → LocalRuleSourceRepository → BookSourceService / LocalRulePanelService → LocalRuleDispatcher / LightSourceBridge → LightSourceCore → 轻页原规则核心`

规则组合、CSS、XPath、JSONPath、正则、URL选项、分页、登录脚本、原生源设置、图片、音频、视频和段评动作由上游核心处理，不再使用简听旧提取器、URL分析器或按站点的内容协议适配器。脚本经 `LightSourceSandbox → LocalRuleQuickJsRuntime.execute()` 在独立 taskpool 有界 QuickJS 中执行；原生 JS 的宿主调用通过 JSON 邮箱暂停、响应后继续，兼容源仍沿用阶段回放，网页渲染与嗅探使用轻页宿主协议。

内容结果提供正文 `content`、原始富文本 `richContent`、图片 `imageUrls`、音频地址/请求头、视频地址及段评 `interactions`；`BookSourceService.getSourceChapterContent()` 保留完整结果，既有阅读器与播放器继续消费各自字段。没有新增漫画、视频或段评页面。

`__audioTocDefinition` 仅供 App 在书籍级别判断目录是否过期，不向规则变量或逐章结果传播，避免每章复制整份书源定义。旧目录读取按章解析并清理该冗余字段，同书并发读取复用任务；目录仍以兼容的 JSON 数组分块写入临时文件后原子替换，不截断章节或清除用户阅读进度。

## 平台与验证

原生定义支持顶层 `js` 函数库、阶段 `script`、表达式/模板调用 JS 函数、变量 `optionsScript` 动态选项，以及脚本 `ui.toast`、`ui.refreshExplore` 和受控浏览器交互。动态选项点击时才运行对应脚本，打开面板不预先探测服务器，保存只验证已修改变量；浏览器仅允许 HTTPS，沿用隐私会话与 Cookie 隔离，完成后执行声明的 `login.check`。可参考离线样例 `scripts/fixtures/native-js-host-smoke.json`。

简听每次原生 JS 阶段使用独立有界 QuickJS 上下文；宿主调用保留当前调用栈，等待响应后继续执行，不再从头回放脚本。JS 全局变量不跨阶段、任务或批次保留；需要跨调用保存的状态使用 `vars` / `cache`。书籍列表每最多 16 项的 JS 字段合并求值，详情的 JS 字段合并求值，同批次复用函数库，字段函数应保持纯计算。普通表达式无需进入 JS，JSONPath 和纯转换在 JS 任务内本地执行。阶段计算 2 秒/总时长 60 秒，表达式（含整批字段）计算 2 秒/总时长 10 秒；宿主等待不计入原生计算预算，人工浏览器等待从活动总时长中扣除。每次任务最多 4096 次宿主调用，UTF-8 输入 4 MiB、返回邮箱 8 MiB、累计交换 64 MiB；原生独立硬上限 16 分钟，单次宿主等待上限 15 分钟。`scriptLimits.requests` 仍只控制网络请求（最多 100 次）。源 JS 最多 512 Ki 字符，输入 12 Mi 字符、输出 8 Mi 字符、堆 64 MiB、栈 1 MiB、pending jobs 32。任务完成、取消或失败均释放上下文和邮箱；不向脚本暴露平台对象。导入只做同步结构检查，不执行 JS；语法和函数错误需通过运行测试发现。

书源定义、登录状态及按源+origin隔离的 Cookie 使用简听加密数据库。QuickJS保留时间、内存、栈与输入输出预算，不开放文件、数据库或无约束平台网络。网页运行使用隐私会话租约，任务结束释放；模式/筛选修改保存后通知首页刷新。

同一份规则源码不代表每个第三方源已完成真机验证；设备网页、登录、Cookie作用域、受保护图片和超过运行预算的脚本仍需具体书源验证。当前固定版本、已适配文件、回归与升级方法以同步文档和 `third_party/light-source/upstream.json` 为准。
## 加密封面

`coverDecode` 的唯一字段说明与示例见[公共规范：加密封面](https://github.com/wip3l/harmony-book-source-engine/blob/main/docs/book-source-development.md#加密封面-coverdecode)。简听已接入公共加载器，网站参数只存在于用户导入定义。

封面 URL 的 `#source-cover-v1=` 片段仅记录书源标识，不含密钥。应用按需通过已导入书源的隔离会话下载解密（单图最多 8 MiB），以 3 并发、64 待处理上限加载，并缓存到应用缓存目录（最多 64 MiB）。源定义或登录状态变化会隔离缓存；删除书源后不能继续解析加密封面。收藏和记录保留原始地址，缓存清理后可重新加载。列表、播放器、系统媒体封面共用该入口。

## 漫画图片脚本

漫画阅读请求由可信宿主通过接口参数 `deferReaderImages` 显式开启按需图片模式，公共核心先返回图片清单和完整的 URL 选项；图片进入可见区后再通过 `ComicImageLoader → BookSourceService.cacheComicImages → ComicImagePipeline` 下载和解密/重排。列表预建的离屏节点保留占位，不抢先发起远程图片请求。总并发最多 6，后台最多占 2 个位置，可见图片优先；同源同图合并任务，所有消费者取消后才取消共享请求。单图完成即交给 UI 显示，不等待本章其他图片；UI 只显示已处理的本地地址，解码失败显示单页重试，不回退显示未排正的原图。逐页保存本地结果，只有整章文件齐全且有效才计为离线缓存。此开关不属于书源字段、不暴露给脚本；小说带图、下载和导出仍使用默认完整物化流程。

`content.imageDecode` 已完整接入公共包的标准解密及 `script` 路径；字段语义以公共规范为准。函数从顶层 `js` 取得，收到 `Uint8Array` 和 `{url,index,params}`，其中 index 是原始图片列表的零基序号。支持字节数组、ArrayBuffer 和在 pending-job 预算内完成的 Promise；普通图片默认跳过脚本，`processPlainImages: true` 时也会处理。标准解密支持 `keyEncoding` 与每张图前 16 字节 IV。

图片脚本在后台独立有界 QuickJS 中执行，提供 `image.decrypt/encrypt/hash/hmac/reorderStrips`；不开放网络、Cookie、文件或数据库。单图输入/输出各最多 20 MiB、JS 内存 96 MiB、计算 2 秒、总时长 10 秒；最多 32 次图片宿主调用和累计 128 MiB 字节。运行与等待共最多 6 项、一次执行 1 项、排队最多 30 秒；取消会通知原生中断。系统加密和图片编解码调用无法在中途抢占，返回后检查取消及总时长。解码失败不写入图片缓存，变更请求头、参数、序号或函数库后使用不同缓存身份。

`image.reorderStrips(bytes, {count, order?, remainder?, format?, quality?})` 将静态图片按水平条带重排。默认按倒序输出，`order` 可指定从零开始的完整排列；`remainder` 指输入图中承载高度余数的条带，默认 `last`，也可用 `first`。默认输出 PNG，另支持 JPEG/WebP 和 0～100 的质量值。条带数 1～256，重排图像最多 4 Mi 像素、宽高各不超过 16384；条带数为 1 时直接返回原字节。动图不做重排。通用参数和示例在公共规范维护，网站阈值、MD5 段数规则仍由导入源的图片脚本声明。

简听通过现有 QuickJS 原生二进制宿主调用 ImageKit NDK，像素不进入 JS；解码前检查尺寸与帧数，按真实行跨度读取，输出保持原宽高。实现同时处理高度余数和行填充，并在成功、失败或取消后释放资源。普通可解码图片也需重排时，源必须显式声明 `processPlainImages: true`；已经由中转排正的图片应在脚本中跳过，避免重复翻转。
