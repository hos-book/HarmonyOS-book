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

规则组合、CSS、XPath、JSONPath、正则、URL选项、分页、登录脚本、原生源设置、图片、音频、视频和段评动作由上游核心处理，不再使用简听旧提取器、URL分析器或按站点的内容协议适配器。脚本经 `LightSourceSandbox → LocalRuleQuickJsRuntime.execute()` 在独立 taskpool 有界 QuickJS 中执行；网络动作通过受控宿主回放，网页渲染与嗅探使用轻页宿主协议。

内容结果提供正文 `content`、原始富文本 `richContent`、图片 `imageUrls`、音频地址/请求头、视频地址及段评 `interactions`；`BookSourceService.getSourceChapterContent()` 保留完整结果，既有阅读器与播放器继续消费各自字段。没有新增漫画、视频或段评页面。

`__audioTocDefinition` 仅供 App 在书籍级别判断目录是否过期，不向规则变量或逐章结果传播，避免每章复制整份书源定义。旧目录读取按章解析并清理该冗余字段，同书并发读取复用任务；目录仍以兼容的 JSON 数组分块写入临时文件后原子替换，不截断章节或清除用户阅读进度。

## 平台与验证

书源定义、登录状态及按源+origin隔离的 Cookie 使用简听加密数据库。QuickJS保留时间、内存、栈与输入输出预算，不开放文件、数据库或无约束平台网络。网页运行使用隐私会话租约，任务结束释放；模式/筛选修改保存后通知首页刷新。

同一份规则源码不代表每个第三方源已完成真机验证；设备网页、登录、Cookie作用域、受保护图片和超过运行预算的脚本仍需具体书源验证。当前固定版本、已适配文件、回归与升级方法以同步文档和 `third_party/light-source/upstream.json` 为准。
## 加密封面

`coverDecode` 的唯一字段说明与示例见[公共规范：加密封面](https://github.com/wip3l/harmony-book-source-engine/blob/main/docs/book-source-development.md#加密封面-coverdecode)。简听已接入公共加载器，网站参数只存在于用户导入定义。

封面 URL 的 `#source-cover-v1=` 片段仅记录书源标识，不含密钥。应用按需通过已导入书源的隔离会话下载解密（单图最多 8 MiB），以 3 并发、64 待处理上限加载，并缓存到应用缓存目录（最多 64 MiB）。源定义或登录状态变化会隔离缓存；删除书源后不能继续解析加密封面。收藏和记录保留原始地址，缓存清理后可重新加载。列表、播放器、系统媒体封面共用该入口。
