# 轻页书源引擎同步

简听通过 `LocalRuleDispatcher → light/LightSourceBridge → LightSourceCore` 调用轻页的书源核心。页面仍由简听维护。轻页兼容源和轻页 `sourceFormat: native` 源走此链路；原简听规则核心、`jianting.source` 引擎及按域名分流的专用内容适配器已删除；历史定义保留为数据，停用格式不执行。

## 固定版本与维护边界

同步输入分别固定版本：

| 来源 | 仓库 | 固定提交 | 本地工作区 |
| --- | --- | --- | --- |
| 解析内核 | `wip3l/harmony-book-source-engine` 的本地分支 `codex/jianting-native-js-host` | `817b11ee7b0a4ba5b8587464499ae7af4b0441d6` | `D:\harmony-book-source-engine` |
| 应用辅助代码 | `wip3l/legado-harmony` 的共同维护分支 `codex/sourceengine-host` | `67e5f2dc99b4fb62fe714b45d7d6acc56e7afad2` | `D:\legado-harmony-sourceengine-host` |

应用辅助代码沿用迁移前的固定提交，其中末次网页等待修复仍是本地提交，不假定上游公开仓库已有该提交。精确版本、逐文件来源、原始路径和 SHA256 见 `third_party/light-source/upstream.json`（schemaVersion 2）。摘要统一按 LF 换行计算；生成文件的 upstreamSha256 对应抽取的方法或原始模板，generated 标记与 upstreamPath 共同记录出处。

- `light/upstream/`：递归迁入的规则、解析、网络、媒体和交互核心；导入方法从上游原方法抽取。勿直接修改生成文件；通用能力修改公共包，简听策略通过宿主端口注入。
- `light/LightSource*.ts`、`LightSource*.ets`：简听 JSON 模型边界、平台接口和有界 QuickJS 桥接。
- `upstream/model/data/AppDatabase.ts`：本地数据库桥接，明确排除同步覆盖。
- `scripts/sync-light-source.cjs`：检查本地改动、执行适配、更新版本清单，不修改页面。

独立仓库提供 `sourceengine` HAR，但简听继续按固定提交迁入源码：内核优先读取独立仓库的 `sourceengine/src/main/ets`，应用辅助代码只读取轻页仓库的 `entry/src/main/ets`，绝不回退到轻页旧 `sourceengine` 副本。从独立仓库 `sourceengine/Index.ts` 解析公开符号并转换包导入。搜索/发现/阅读调度、兼容源导入及音频后处理仍来自应用辅助代码。沿用既有有界 QuickJS、加密 Cookie、独占隐私 Web 和调度端口，不引入第二套运行时或修改模块签名配置。

当前独立内核已包含网页等待修复，已移除本地 `bounded-web-wait` 补丁，清单中的 `patches` 为空。等待最多 120 次并保留请求总超时；等待条件未满足时仍返回失败，但保留已加载页面与非零状态码，以便上层判断登录/验证页，不能把该结果当成成功正文。

## 更新流程

正式包必须保留属性名：原生书源 JSON、表达式和脚本桥接依赖运行时字段名，不能开启 `-enable-property-obfuscation`；顶层、文件名和导出符号仍可混淆。发布检查应向 `scripts/verify-release-package.py` 传入本次构建的 `--name-cache obfuscation-cache.json`，检查原生书源定义与桥接数据字段是否被改名。仅检查 APP 元数据或运行未混淆的 Node 回归无法覆盖此问题。

分别准备上述两个仓库的固定提交，查看差异后使用干净的 detached worktree 或已有固定分支。组织 Fork 的推送独立处理。随后在简听运行（两个参数依次是独立内核仓库、应用辅助仓库）：

```powershell
node scripts/sync-light-source.cjs D:\harmony-book-source-engine D:\legado-harmony-sourceengine-host
node scripts/sync-light-source.cjs D:\harmony-book-source-engine D:\legado-harmony-sourceengine-host --check
node scripts/test-light-source-engine.cjs
node scripts/test-comic-web-wait.cjs
node scripts/test-rule-source-export.cjs
```

指定真实原生源文件可执行 `node scripts/test-light-source-engine.cjs <源文件路径>`，使用该文件原规则核验分类、模式、持久化及阅读链路；加 `--live-menu` 请求公开分类接口，加 `--live-audio` 请求听书分类、发现及前三本详情并核对书籍 ID 和封面，其他链路使用离线响应。

测试需设置 `DEVECO_HOME` 为 Release DevEco Studio。同步前本地迁入文件必须与旧清单一致，两个输入仓库相关源码必须干净；检查失败不会覆盖本地引擎。`--check` 不写入文件，核对两个版本、生成结果、兼容补丁及 LICENSE/NOTICE。上游方法或依赖变化需先调整脚本，再同步。随后执行相关静态检查、Release SDK 增量构建，以及设备导入→测试→搜索→详情→阅读/播放验证。对比通过后提交升级；Git 提交可用于回退。此流程是维护工具，没有启用自动拉取、自动发布或后台更新。

## 能力与验证边界

### 原生 JS 宿主接入（2026-10-20）

公共包 main 已从 `e02c5b2` 更新到 `c32c2dc`。在此基础上，本地分支增加异步表达式/阶段宿主端口、动态选项保存修复、公开端口导出、按 AST 选择 JS 执行路径和书籍字段批量求值，尚未推送；不能假定其他机器从上游 main 就能取得这些改动。应用辅助代码仍固定为 `67e5f2d`，本次同步 82 个文件。

`LightNativeScripts.ts` 接管原生 `js`、阶段 `script`、表达式函数、`optionsScript` 和交互动作。每次求值通过 `LightSourceSandbox → LocalRuleQuickJsRuntime.execute()` 在独立 taskpool 上下文执行；异步宿主调用通过有界日志回放衔接，已完成的请求、变量写入及交互动作不重复执行。时间和随机数在同次回放内固定。Cookie、网络、HTTPS 隐私浏览器仍复用既有宿主；浏览器完成后执行源声明的 `login.check`。

同步脚本将默认 `NativeJsLibrary`、`NativeScriptSessions` 平台实现替换为明确不支持的后备实现，由注入的宿主端口接管，不引入第二套 QuickJS HAR。`NativeExprProgram.ts` 由固定上游 `NativeExpr.ts` 和无平台依赖的 `JsonPathEvaluator.ts` 经 Release IDE 自带 TypeScript 编译生成，需设置 `DEVECO_HOME`（本轮为 DevEco Studio 26.0.0 Release）。JSONPath 在同一沙箱内求值，避免每个 `$.field` 都回放整个任务。生成文件仍禁止手改。

兼容边界：JS 全局变量不跨阶段、任务或批次保留，持久状态应通过 `vars` / `cache`；这与上游持久 JS 会话不完全等价。书籍列表每最多 16 项的 JS 字段合并为一次求值，详情的 JS 字段合并为一次求值，同批次可复用函数库状态，字段函数应保持纯计算。阶段计算累计预算 2 秒、总时长 60 秒；表达式（含整批字段）计算 2 秒、总时长 10 秒，回放计算也计入预算，人工浏览器等待扣除。最多 256 次宿主调用；交换日志、单请求和输出字符串分别按 16×1024²、4×1024²、8×1024² 字符限制，源 JS 上限 512 Ki 字符；底层 QuickJS 的输入、堆、栈和 pending-job 限制继续生效。导入检查定义结构，JS 语法和函数执行错误在运行测试时报告。

发现面板不预先运行变量 `optionsScript`；点击动态选项时才加载对应脚本，保存时只验证实际修改的变量。静态标题和仅使用内置函数的表达式不启动 QuickJS，由 AST 检查函数及 lib 依赖后选择路径，不先执行再回退。此修复处理番茄源数百个菜单/字段重复启动任务，以及服务器选项探测阻塞发现页的问题。

验证：同步 `--check`、简听引擎回归、书源导入导出、漫画网页等待均通过；上游原生源 243 项、JS 库 34 项、脚本阶段 58 项通过。新增主机回归覆盖异步阶段、表达式/模板/crypto、动作只执行一次、隔离、取消/超时、搜索→详情→目录→正文、动态选项和浏览器受控桥；763 个静态/普通动态菜单不启动 QuickJS，30 本书的 JS/JSONPath 字段仅运行 2 个任务并保持跨批次序号与字段正确，详情 JS 字段运行 1 个任务。主机测试以 VM 模拟 QuickJS，不替代真机。

Release SDK 26.0.0.105 增量 debug HAP 构建并安装 Mate 80 成功（本轮构建 52.288 秒），产物元数据为 Release、最低 API 20、目标 API 26。MCP 静态检查因 LSP 未初始化不可用，MCP 构建因本机 ohpm 批处理递归失败，实际构建使用 Release IDE CLI。

真机用户操作与日志核验（2026-10-20 17:45—17:46，进程 56893）：第一个「番茄小说（原生脚本）」的 363 个静态菜单解析 2 毫秒，分类 30 本书端到端加载 742 毫秒；分类规则实际只产生 3 次 QuickJS 任务（失败检测 1 次、字段批次 2 次），修复前同类书单触发数百次任务。「乡村神医」详情含 3603 章目录加载成功，耗时 5449 毫秒；进入阅读后 3 次正文加载为 955、782、1397 毫秒，其中 HTTP 为 897、716、1309 毫秒。第四个「小六番茄（原生脚本）」184 个含远程分类的菜单加载 3046 毫秒，30 本书加载 2043 毫秒，详情含 1395 章目录加载 5035 毫秒；用户确认书单正常显示。菜单计时不含 ArkUI 绘制，分类计时包含网络和规则解析；目录数字是详情整体耗时，不能全部归因于服务器。第一源此前搜索接口返回的服务端 Java/Xposed 异常是独立问题，不宣称被此次 App 修复解决。未完成真实账号登录、音频播放、下载导出或手表验证。

在线依据沿用本任务已读取的 [ArkTS 语法规范](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[ArkTS 检索指引](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-knowledge-retriever/SKILL.md)、[ArkUI 检索指引](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md) 和 [HiLog 指引](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-studio-hilog/SKILL.md)。

### 公共包 main 更新（2026-10-19）

从独立仓库 `main` 拉取至 `e02c5b2`，替代此前封面扩展分支的 `2f8c4bf`，用既有同步脚本迁入 76 个文件；应用辅助代码仍固定在 `67e5f2d`。新增兼容规则选择器/属性规则缓存、原生目录字段处理让出主线程、详情附加请求、目录复用详情响应、目录与正文分页批量配置、分类请求方法与请求体，以及更严格的封面密钥和图片识别校验。公共规则文档已并入 main，规则入口改为 main。

同步 `--check` 通过；简听引擎、漫画网页等待与书源导入导出回归通过；上游原生源 235 项、兼容规则 462 项和封面解密回归通过。Release SDK 26.0.0.105 增量 debug HAP 构建成功。设备列表为空，本轮未安装或完成真实书源导入、搜索、登录、阅读/播放及下载导出验证。

本轮在线目录已刷新并读取 [ArkTS 语法规范](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md) 和 [ArkUI 检索指引](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md)，执行结果以本机回归与 Release SDK 编译为准。

### 独立内核双来源同步（2026-10-16）

迁入 73 个文件；运行时继续由简听的 `SourceEngineHost` 适配器接管。上游新增网络错误分类，原生请求超时/域名解析失败不再冒充需要登录。声明式缓存取消 Cookie 分区后，简听在原生网页登录完成检查入口显式清缓存（包括只校验 Cookie 的登录），表单登录及退出清理沿用已有路径。普通 HTTP Cookie 刷新不清声明式缓存。

主机回归已覆盖搜索/详情/目录/正文、脚本与原生源、媒体头、并发 Cookie/错误隔离、优先级取消、导入导出、Web 会话清理及漫画网页等待。新增回归确认 Cookie 刷新复用缓存、浏览器换账号和退出登录清理缓存。此处平台调用为模拟实现，不等同于真实网站账号和设备验证。

双来源 `--check` 通过。Release SDK 26.0.0.105 增量 debug 构建成功，签名 HAP 的 apiReleaseType=Release、最低 API 20、目标 API 26，NOTICE 已随包保留。已覆盖安装手机 `62T0225B13006276` 并成功启动；本轮尚未完成真实书源的导入、登录、搜索、阅读/播放、下载和导出设备全链路验证。

源码依据：[独立仓库接入说明](https://github.com/wip3l/harmony-book-source-engine/blob/1eb86df3e38189fee400ca5982f07e3dc4501d51/README.md)、[宿主端口说明](https://github.com/wip3l/harmony-book-source-engine/blob/1eb86df3e38189fee400ca5982f07e3dc4501d51/sourceengine/README.md)。在线规则参考：[ArkTS 规则](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/references/arkts-rules.md)。

### sourceengine 公共包接入（2026-10-15）

本次同步 71 个引擎/适配文件，保留简听有界 QuickJS taskpool、按源 Cookie 隔离及属性持久化、独占隐私 Web 租约、任务错误隔离、变量增量合并、播放优先调度与取消、计时诊断。新增 `BookSourceRuntimeStore.forSource(source)` 宿主适配，按执行实例绑定 `LightSourceDatabase`，不以全局可变“当前源”代替并发上下文。

上游原生搜索新增 debugContext 参数，适配器保留其位置并在后面传入简听页码。新增 WebView `waitFor` 请求经 `AnalyzeUrl.fetchPrepared` 进入既有限流、重试、重定向和取消路径，同时传递响应大小限制；不会直接绕过调度发送 HTTP。公共包新增 `NativeSourceImport`，`LightNativeImport` 仅作兼容别名；定义解析不清理缓存、不加载 HTTP、ArkWeb 或 QuickJS 宿主。原生缓存按定义、登录信息及登录站点 Cookie 隔离，实际导入仍清理源缓存。

原生源 `login.form/submit/sendCode` 接到现有面板，仅持久化返回的 token/user；密码等表单值不写入状态。`actions` 与正文请求动作由原生服务执行，网页入口维持 HTTPS-only。`content.mediaHeaders` 沿既有音频地址/请求头链路输出。原有章节变量瘦身、目录压缩、预加载接管和书籍身份逻辑保留。

验证：引擎回归、导入导出、音频预加载、音频书籍身份及目录缓存回归通过；新增覆盖原生搜索第三页、媒体头、表单登录/验证码、登录失败保持已有凭据、动作、注销及 waitFor 限流/取消。Node 使用模拟 HTTP 和 VM，不能代替设备 QuickJS 或真实账号验证。MCP 构建遇到本机 ohpm 批处理递归错误，改用已验证 Release SDK 26.0.0.105 的 IDE CLI（--no-daemon）增量 debug 构建成功；签名 HAP 元数据为 apiReleaseType=Release、min API=20、target API=26。设备列表为空，未安装或执行本轮实机播放、下载、导出验证。

源码依据：[公共包说明](https://github.com/wip3l/legado-harmony/blob/fc1f3b25861965a698f824679e7ebbc7130ae393/sourceengine/README.md)、[公开入口](https://github.com/wip3l/legado-harmony/blob/fc1f3b25861965a698f824679e7ebbc7130ae393/sourceengine/Index.ts)、[双目录加载参考](https://github.com/wip3l/legado-harmony/blob/fc1f3b25861965a698f824679e7ebbc7130ae393/scripts/lib/ets-module-staging.mjs)。在线技能已刷新目录并读取 [ArkTS 检索指南](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-knowledge-retriever/SKILL.md) 与其 [linter 实现约束摘要](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-knowledge-retriever/docs/linter/ArkTS_Syntax_Knowledge_From_Linter.md)；编译结论以本机 Release SDK 为准。

### 两项目共用宿主接口（2026-10-15）

公共包新增 `SourceEngineHost.install(adapter)`：Cookie、运行时持久化、有界脚本执行器、Web 会话、优先级/取消调度、执行错误与耗时诊断均通过可选端口注入。轻页不安装适配器时保持原 CookieStore、已安装数据库和 ArkWeb 串行行为；简听在 `LightSourceRuntime.ts` 初始化时安装宿主，只有独立有界 QuickJS 执行器声明允许并发。

同步脚本已移除运行时、并发隔离、调度及计时的字符串替换补丁。仍保留包路径转换、隐私 Cookie 语义辅助类生成、兼容源导入和音频页面方法提取；搜索/发现/阅读编排仍来自 entry，尚未把整套应用搬入 HAR。简听仍采用固定源码同步，没有增加第二套 QuickJS 二进制或改动模块签名配置。

验证：公共包宿主回归覆盖默认串行、注入并发、Cookie/持久化及取消，定义转换与缓存隔离回归通过；原生源 181 项、脚本运行时 46 项及中立性检查通过。简听引擎、导入导出、预加载、书籍身份和章节缓存回归通过。Release SDK 26.0.0.105 公共 HAR、简听签名 debug HAP 构建通过；轻页应用编译和打包通过，签名因上游配置引用的本机不存在证书而失败，已生成未签名 HAP。两个应用产物元数据均为 Release、最低 API 20、目标 API 26。设备列表为空，本轮未执行设备验证。

### 通用边界

书籍变量含 `tones` 时，播放器将其逗号分隔的音色 ID 与源声明 `voices` 取交集，不把全源音色都当成当前书可用。`real` 非空时保留声明中的 `0`（真人原声），菜单始终提供“默认”。显式空 `tones` 不展示合成音色；未提供 `tones` 的源仍使用原声明列表。此筛选只依据源返回的元数据，不代表每个章节的音频请求必定成功。

播放器通过 `LightSourceBridge.voices()` 读取原生源声明的 `voices: [{id, name}]`，名称展示给用户、id 写入当前书籍的 `custom` / `__audioSourceVoice`。音色列表采用 ArkUI V2 和 LazyForEach（按音色 id 去重并生成稳定 key），参考在线 [ArkUI 检索技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md) 与 [LazyForEach 指南](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/09-rendering/arkts-rendering-control-lazyforeach.md)。不按域名硬编码音色，也不要求用户输入编号；可选音色与最终回退行为仍由导入书源决定。

章节上下文通过 `ChapterRuleContext` 跨 JSON 边界保留：新目录保存规则原始标题 `chapterName` 和零基 `chapterIndex`；播放、投播、预加载及下载遇到旧目录时，用本地 `Chapter.title` 和 `Chapter.index - 1` 补齐，不改写原变量。否则依赖 `chapter.title` 匹配真人目录的原生音频源会误走合成回退。此适配留在简听，不修改公共包或书源。回归覆盖缺标题回退、新旧目录补齐、原标题保留、预加载实际参数，以及既有播放控制；Release SDK 签名构建和手机覆盖安装通过。《狩猎北大荒》首章实机重新解析播放后，地址从 `v26-fq-tts.fqnovelvod.com` 变为 `v3-novelapp.fqnovelvod.com`，显示时长 7:33；下一章预加载解析成功。此次未实测投播、显式下载和导出。

迁入核心覆盖 CSS/JSONPath/XPath、正则与替换、规则组合、脚本宿主动作回放、搜索/发现/详情/目录/正文，以及图片标记、图片请求选项/解码、音频/视频地址和段评动作标记。正文输出保留 `richContent`，同时提供 `imageUrls`、`videoUrl`、`interactions` 等结构数据；没有新增漫画、视频或段评页面。轻页原生源的 `vars` 设置、模式/频道切换、静态/动态发现分类和登录声明由 `LocalRulePanelService → LightSourceBridge` 连接到既有面板；设置保存到加密脚本状态，并使首页内容缓存失效、通知首页刷新。选项操作只更新当前变量，避免其他控件的旧值阻止模式切换。

脚本使用简听 taskpool 的独立有界 QuickJS，保留时间、堆、栈、输入和输出限制；数据库与 Cookie 仍按简听加密及按源隔离。普通 HTTP 与脚本任务各自持有执行上下文，可以并行执行；Cookie 内存按导入源隔离，错误按任务隔离，不再整项持有全局队列或 Web 租约。仅实际网页抓取、音频嗅探使用全局隐私 Web 会话，完成或失败后回收 Cookie 并释放。变量和脚本缓存按实际修改项合并，数据库只在状态或 Cookie 有变化时写回；同源短状态事务串行，网络请求不进入该队列。

搜索/发现结果的书籍元数据通过桥接快照保留，详情、目录及正文恢复同一个上游 Book 上下文；详情以点击地址为准，完成后更新快照和规范地址。上游原生详情会优先保留发现封面，但标题可替换为接口返回的原著名称。简听听书展示保留用户点击的有声版名称，缺失时才用详情补齐；规则解析仍返回原始详情名称，不修改上游规则。新听书发现结果不受旧详情封面缓存覆盖，恢复目录时保留新结果的变量。

规则源码与声明字段统一使用轻页核心。平台适配保留独立有界 QuickJS、加密存储及按源隔离 Cookie；HTTP Set-Cookie 的 Domain、Path、Secure、HttpOnly、SameSite 和绝对过期时间按源持久化，Max-Age 转绝对时间防止重启延长寿命。ArkWeb 只能读取 Cookie header，未知网页登录 Cookie 的原始属性不能完整反向枚举，采用 origin/Path=/ 恢复；不能据此宣称浏览器会话完全等价。

TextDecoder 使用系统编码器的数据桥，支持系统编码（含 GBK）与连续字节流；登录 HTML 编解码仅调用固定 DOM 表达式，书源任意脚本仍在 QuickJS 内。WebView/webJs 与媒体嗅探使用迁入核心和隐藏宿主。时间、内存、回放和输出预算仍有效；任意 DOM 和平台对象不对书源开放。网页登录保持 HTTPS-only。Node 回归不能代替原生 QuickJS、真实账号、人机验证、受保护图片和媒体嗅探实机测试。

## 许可证

迁入代码遵循 GPL-3.0，全文见 `third_party/light-source/LICENSE`，组合应用分发需遵循相应 GPL 条款并提供对应源码。原独立组件的版权和许可证继续保留；详见 `THIRD_PARTY_NOTICES.md`。

## 本次验证（2026-10-14）

- `test-light-source-engine.cjs`：通用 HTML/JSON、搜索/详情/目录/正文、媒体/段评标记、阶段脚本回放、登录状态及 Cookie 删除/替换通过。Node VM 代替设备 QuickJS。
- 用户提供的番茄原生源：六个模式选项、单变量修改、保存后重载、分页发现、详情、目录、正文及本章说标记通过离线响应回归；公开分类接口实测解析出 179 个分类入口。
- `test-rule-source-export.cjs`：原始字段与扩展字段保留、五次往返稳定、编辑及敏感会话字段排除通过。
- `test-source-health.cjs` 与 `test-text-to-speech.cjs` 通过，后者包括 28 项既有朗读回归。
- 模式修正版 Release SDK 增量 debug HAP 构建并覆盖安装完成，用户确认模式切换已生效。`@Trace` 控件通过普通数据快照序列化，避免 `__ob_value` 导致选项值丢失；导出同样显式读取观察属性。
- 听书公开接口复现相同书籍 ID 对应不同的有声版/原著名称和封面；补齐桥接上下文后，三本公开听书的详情 ID 与发现一致，详情封面保留发现封面。`test-audio-source-identity.cjs` 验证展示名称、旧封面缓存、目录变量、逐批更新及持久化。修正版已通过 ArkTS 检查及 Release SDK 增量 debug HAP 构建，覆盖安装到手机并强制停止后冷启动，用户反馈已测试。登录与媒体嗅探仍待专项实机验证。

## 导入、解析与登录补齐（2026-10-14）

本轮已接入之前识别出的链路差距，保留简听页面和其他业务：

| 能力 | 当前实现 |
| --- | --- |
| 登录入口 | 统一解析 loginUrl/loginUi；脚本式 loginUrl 无控件时生成入口，使用轻页入口解析方法。独立主账号不变。 |
| 等待网页登录 | 等待页面完成返回 HTML 后继续同一脚本；脚本任务不占 Web 租约，实际网页登录由既有登录协调器独立持有。支持连续等待和取消，人工交互不占脚本时间预算。 |
| 登录校验/退出 | 网页完成调用规则校验；原生 login.check 执行声明接口，无 check 则判断声明 Cookie；退出清理 Cookie、登录头/信息及待续状态。 |
| Cookie 语义 | 迁入删除墓碑、空值替换和过期 JWT 过滤；隐私容器读写一致。属性记录与 header 分开落盘，已删/过期记录不回流。 |
| 订阅取数 | 应用 HTTP、系统 HTTP、原始 HTTP、ArkWeb 页面/下载、系统下载依次兜底；临时文件退出时清理。 |
| 导入容量 | 单文件/订阅 25 MiB，最多 10 文件/250 MiB；移除 1000 源数量截断及旧单源 512 KiB 限制；保留锁定保护，当前免费版本不限制书源总数。 |
| 编码与 HTML | GBK 等系统编码、streaming TextDecoder 和固定 HTML 编解码桥；仍使用有界 QuickJS。 |

专项回归覆盖连续网页等待、取消、原生校验成功/失败、Cookie 声明判断、路径/过期恢复、注销不复活、GBK/流式解码、真实定义的模式和解析、订阅兜底及 1201 源导入。真实账号、验证码与媒体嗅探仍需相同账号和源条件下的实机专项验证，不以源码迁入或模拟响应替代。

平台依据：本任务已读取 ArkTS/ArkUI 和 SDK 指引；实现及结论来自两侧代码与已安装 Release SDK：

- https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkts/hmos-arkts-knowledge-retriever/SKILL.md
- https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/SKILL.md
- https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/sdk/hmos-one-sdk-skill/SKILL.md

本轮落地验证：引擎/真实番茄定义回归、订阅取数回归、多文件导入回归全部通过；ETS 静态检查后使用 Release IDE CLI 完整增量构建成功。HAP 元数据 apiReleaseType=Release、min API=20、target API=26，已覆盖安装到设备 62T0225B13006276 并冷启动成功，现有数据保留。此处仅记录构建、安装和启动证据，不代表真实账号专项登录或手表验证。

本轮手机 smoke：现有番茄源的听书首页加载成功，点击《我丈夫的情人》后详情保持同名，作者/简介及 297 集目录信息正常展示。未使用真实账号执行验证码登录。

## 听书分类返回正文（2026-10-14）

使用用户提供的番茄原生源，公开接口复现：全部分类样本返回 audio；都市、穿越、现代言情的发现记录按听书模式解析为 audio，详情却返回原著 book_type=3，规则映射为 text，且 content.url 的普通分支保留 tab=novel，导致无音频地址。同一章节改为 tab=audio 时服务返回 content_type=audio 和有效音频/代理地址。此差异由当前 JSON 的两处规则触发，未证明轻页实机能播放相同样本。

修正版仅调整 detail.fields.type（听书模式明确采用 audio，包括旧缓存上下文）和 content.url（audio 使用 tab=audio，video 和 text 维持原分支），原文件不覆盖、不提交用户源定义。两边导入相同修正版即可使用相同声明；不在应用核心注入站点地址或 URL 改写。公开接口回归覆盖全部/都市/穿越/现代言情的发现→详情→目录→正文，四类均返回 audioUrl；新增 --live-audio-categories 可对指定源执行该验证。实际播放器和完整音频文件下载需另行验证。

修正版已通过 hdc 写入简听自己的 filesDir，再由原有 viewData 文件导入入口重新导入同 URL 书源，未改 App 解析核心。手机随后位于另一个源的阅读页，停止继续点按；本轮尚未获得修正版在 AVPlayer 实际播放的证据。

## 有听网音频与旧目录迁移（2026-10-14）

《无敌剑域》的设备日志暴露两处接入差距：音频规则核心返回结果后，简听遗漏了轻页 AudioBook 页的 JSON/HTML 地址提取与书源媒体请求头；旧引擎生成的 `__genericTocFallback` 网页目录又被当作当前定义缓存复用，将 HTML 交给 JSON 音频规则。

同步脚本现在从同一固定上游提交的 `AudioBook.ets` 提取七个通用解析/请求头方法到 `upstream/LightAudioSupport.ts`，不迁入页面。`LightSourceCore` 使用原方法还原 JSON/Unicode 地址、保留源声明 Referer/User-Agent 和显式媒体请求头，同时保留跨站凭据隔离。目录签名加入轻页引擎版本，旧定义目录和带 fallback 标记的章节在播放前按当前源规则刷新；保留章节 ID，原进度及下载身份不重建。不添加域名专用适配、不修改用户定义。

主机定向验证：引擎回归覆盖 BOM/Unicode、嵌套媒体值、显式请求头与跨站凭据隔离；目录迁移回归覆盖旧网页地址更新、ID 保留及新目录复用。使用手机保存的 www.ting15.com 源定义和《无敌剑域》2117 号书公开接口，解析 3977 个有效章节，前两集音频 Range 请求均为 HTTP 206 / audio/x-m4a，携带声明 Referer。这些请求结果不替代手机实际播放验证。

设备验证：修正版 debug HAP 覆盖安装并冷启动后，设备 62T0225B13006276 日志在 14:38:57 确认刷新 3977 章，14:39:01 确认《无敌剑域》第1集进入 playing，时长 951740ms；用户暂停时进度为 1561ms。此次旧目录迁移耗时约 15 秒，新签名目录后续直接复用。未将其他书的播放证据计入本书，也未声称本轮完成音频导出或手表验证。

本轮在线技术参考：已读取 [ArkTS 语法指南](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md)、[ArkUI V2 观察](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/02-state-management/v2/arkts-new-observedV2-and-trace.md) 和 [hilog 指引](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-studio-hilog/SKILL.md)。运行结果来自实际设备日志及本机 Release SDK 编译，不以指南存在代替验证。

## 解析接入与业务调度边界（2026-10-14）

本轮保留固定上游版本、原有播放器、预加载、下载与目录迁移策略，只调整解析适配层：普通 HTTP 不初始化或清空 ArkWeb Cookie，会话只在实际 Web 请求期间申请；有界 QuickJS 的阶段请求使用独立执行实例，不再由上游页面级脚本队列串行阻塞。请求显式携带书源 Cookie 作用域，网页登录返回值更新已有 Cookie 时保留已知 Domain/Path 等属性。未变更的运行状态不重复落盘；历史脚本缓存字段的首次清理仍属于实际变更。

引擎回归新增并通过：慢脚本不阻塞另一解析任务、同域名不同源 Cookie 隔离、同源并发变量修改合并、任务错误隔离、无变更状态不写入、实际 HttpClient 请求头及 Set-Cookie 路径处理、Web 会话独占及失败释放。测试中的网络/ArkWeb/QuickJS 平台接口使用模拟实现，不作为手机起播耗时证据。

修正版已通过 Release SDK 增量 debug HAP 构建，产物元数据为 apiReleaseType=Release、min API=20、target API=26。已覆盖安装到手机 62T0225B13006276，未卸载或清理应用数据；强制停止后启动 EntryAbility 成功。本轮尚未测得点击章节到开始播放的实机耗时，不能据此认定已恢复到 1.85 秒。

在线语法依据：本轮已读取 [ArkTS 语法规范](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md) 及其规则参考，保留项目 ArkUI V2 和 API 20 基线。

## 起播分段计时（2026-10-14）

仅补充解析适配层诊断，不改变播放器、缓存、预加载或书源限流策略。每次 content 解析分配数字编号；复制的源对象继承编号，HTTP、限流及脚本执行显式关联该编号，不使用全局当前任务。日志不包含地址、书名、脚本内容、响应内容或凭据。

计时覆盖 JSON 桥序列化/反序列化、源定义解析、状态读取、Cookie 恢复/回写、状态事务等待/写回、书源限流等待、HTTP 总耗时、响应 Cookie/字符解码、规则处理、媒体地址提取，以及阶段脚本构建和回放、QuickJS 往返与原生执行时间。QuickJS 往返包含调度、上下文创建/释放、执行和结果传输，不能直接当作纯队列等待。嵌套阶段不可重复求和。

普通 HTTP 记录 API 11 起提供的 performanceTiming 累计里程碑（毫秒）：DNS 完成、TCP 完成、TLS 完成、首次发送、首字节、响应完成、重定向完成及 SDK 总耗时；这些值不可相加。流式 API 不返回该对象，保持原有限流和响应大小保护，仅补响应头/首块数据/传输完成计时。技术依据为本机 Release SDK 的 @ohos.net.http.d.ts 和已读取的 [hilog 技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-studio-hilog/SKILL.md) 及其 references/hilog.md。

引擎回归通过；MCP 静态检查因 LSP 未初始化不可用，MCP 构建因本机 ohpm 批处理递归失败，改用 Release IDE CLI 增量 debug 构建成功（1 分 14 秒）。已覆盖安装手机 62T0225B13006276 并启动，用户随后手动切章，进程 32457 的 17:33:18～17:34:16 日志得到以下结果：

| 播放代次 | 解析编号 | 书源限流等待 | HTTP 总耗时 | 地址解析总耗时 | 装载到 playing |
| --- | --- | --- | --- | --- | --- |
| 1 | 1 | 611ms | 401ms | 1019ms | 2464ms |
| 2 | 3 | 834ms | 251ms | 1098ms | 3119ms |
| 3 | 5 | 0ms | 312ms | 323ms | 2077ms |
| 4 | 7 | 0ms | 205ms | 220ms | 1841ms |
| 5 | 9 | 586ms | 290ms | 894ms | 2159ms |
| 6 | 11 | 836ms | 294ms | 1143ms | 2711ms |

六次均记录 cache=network，目录准备 0～1ms。HTTP 之外的地址解析处理仅数毫秒至约 20ms；本批未出现 QuickJS 阶段调用。播放器 initialized→prepared 为 835～1877ms，prepared→playing 为 65～570ms。源定义/状态读取及 Cookie 回写均不是本批秒级耗时来源。不能据此把所有书源的脚本成本视为零。

播放后独立解析编号 6（未计入上述手动播放）总计 4271ms，其中限流等待 3857ms、HTTP 353ms、状态读取 54ms；这是后台解析任务，不是一次 4.27 秒的点击起播。按源共享的 concurrentRate 窗口同时约束详情、目录、播放与预加载请求，能够解释未缓存章节解析时间随前序请求变化。本批未复现先前约 5～6 秒的手动起播，因此不能倒推出旧样本的精确分段；已确认应优先检查限流窗口的请求竞争，而非直接认定首次初始化或规则解析慢。

## 播放优先的请求调度（2026-10-14）

在用户授权后调整请求调度：AudioService 给正在播放的地址解析传高优先级请求上下文；ChapterCacheService 给预加载传低优先级上下文。上下文通过 BookSourceService、LocalRuleDispatcher 和 LightSourceBridge 显式传入解析任务，不写入书源定义、变量或数据库。源对象复制时继承同一上下文。

适配后的限流器继续使用上游 concurrentRate 解析与时间戳窗口，仅增加按源等待队列，选择优先级最高的有效任务，同级 FIFO。入队、取消、晋升和离队会唤醒等待者，不依赖轮询先后抢额度。已发出的请求仍占用窗口，不返还或额外发放额度。切章取消其他预加载的待发请求；接手目标章节时提升原预加载上下文并复用原 Promise。超时、清理缓存、关闭预加载、旧播放代次失效时，等待者退出且不消耗额度；HTTP 发送及重试前再次检查取消，脚本回放沿用取消检查。已发送的 HTTP 不强行回滚。

回归通过：引擎新增手动播放优先、同级 FIFO、频率窗口不变、在途任务晋升、取消、限流等待上限及不同源互不阻塞；真实缓存服务回归验证上下文传递、晋升后不重复解析、切章/清理/关闭后的失效、超时、下载和缓存复用；46 项播放控制与听书元数据回归通过。MCP LSP 仍不可用，使用此前已确认可用的 Release IDE CLI 编译成功（1 分 26 秒）。产物 apiReleaseType=Release、min API=20、target API=26，已覆盖安装同一手机并启动。

手机进程 45144 的日志确认播放 priority=2、预加载 priority=0，未缓存章节代次 2 地址解析 283ms、起播 2042ms，代次 3 地址解析 350ms、起播 2607ms。此样本不构成所有请求稳定降到 1.85 秒的证据。代次 1 限流等待仅 7ms，HTTP 却耗时 4924ms，SDK 首字节时间 4909ms，总起播 6728ms，说明接口首字节等待本身也是秒级波动来源。代次 6 在先前请求已消耗窗口后仍等待 1752ms，属于保留频率限制后的剩余等待。不能再把所有慢起播都归因于限流，也不能宣称此次改动消除了接口响应或播放器缓冲耗时。

测试期间还记录一次切章中的非终止 play/idle 状态错误（5400102），同一代次随后进入 playing；本轮未调整 AVPlayer 状态机，不将该记录描述为无错误的全链路验证。未执行本轮音频导出或专项账号登录实机验证。

## 快速选章与播放器回调隔离（2026-10-14）

用户继续切章后，17:46:57～17:47:39 的六次完整网络起播为 3271、3539、3090、2617、4895、3459ms；另一次被下一次点击打断，不作为完整样本。后台解析在 17:47:23.042 消耗书源额度，前台于 17:47:23.600 进入解析后仍等待 2429ms。优先级只能调整待发任务，不能收回已经消耗的限流额度。另有一次旧 prepared 回调与新 reset 交错，发生 play/idle 5400102，随后恢复。

AudioService 现在将音源归属代次与播放请求代次分开：切章先使旧音源失效，实际装载新音源时才绑定新代次；状态回调还需与 AVPlayer 当前状态一致。旧准备、进度、缓冲和错误回调在重置/解析期间不再改写新任务；准备/播放失败回调保留原代次，异步申请媒体会话及后台资格后再次检查音源归属和合法播放状态。异步文件打开或取元数据结束时也检查任务是否仍有效。朗读抢占保留已装载音源的暂停续播能力。

正常播放的预加载改为稳定播放 8 秒后启动；切章、重新缓冲、释放和清理时取消延迟任务，缓冲结束重新计时。暂停时继续保留原有限缓存队列，预加载数量、完整文件复用、下载与书源 concurrentRate 不变。因此连续选章期间较少提前占用额度，但稳定播放后已经发出的后台请求仍可能使之后的点击等待，不能承诺消除所有限流。新增 prepare-call、avsession-ready、background-ready、player-play 计时，分别定位媒体准备与起播前置操作，不记录媒体地址或凭据。

主机验证：51 项播放控制回归通过，新增覆盖旧 prepared/进度/错误在 reset 期间到达、后台资格等待中切章、过期状态事件、正确装载新音源后的正常起播，以及 8 秒稳定窗口和定时器取消；缓存/预加载和音频来源身份回归通过。平台事件为模拟实现，实机耗时须使用新安装版本重新采样。

Release IDE 增量 debug 构建成功（53.920 秒），HAP 元数据 apiReleaseType=Release、min API=20、target API=26；已覆盖安装手机 62T0225B13006276 并通过 start_app 启动，当前进程 62919。此处只确认构建、安装与启动，尚未采集该版本的实机切章起播样本。

随后手机进程 62919 的 18:02:57～18:03:12 日志记录四次完整网络起播，分别为 1720、1417、3921、1528ms。对应书源限流等待 0、5、2024、0ms，HTTP 125、138、145、120ms，prepare() 调用 978、1124、1131、1226ms，play() 调用 565、68、586、77ms；媒体会话为 0～1ms，后台资格申请为 5～7ms。无明显限流的三次为 1.42～1.72 秒；3.92 秒样本受到前一手动章节已发请求的剩余 3 秒窗口约束。另一次准备中被切章打断，不记作完整起播；首个完整文件缓存起播 708ms，不计入网络样本。连续选章期间没有后台解析抢先发送，预加载在用户 18:03:14 暂停时按原策略启动。本批未记录 play/idle 5400102；不据此承诺所有书源均达到 1.85 秒。

本轮已读取 [ArkTS 语法规范](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-native-flow/references/lang-syntax/SKILL.md) 及其规则参考、[ArkUI V2 观察指导](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/02-development/arkui/hmos-arkui-knowledge-retriever/references/knowledges/02-state-management/v2/arkts-new-observedV2-and-trace.md)、[hilog 技能](https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/04-tools/deveco/deveco-studio-hilog/SKILL.md) 和 references/hilog.md；MCP 静态检查仍提示 LSP 未初始化，使用已验证的 Release IDE CLI 编译。

### 漫画网页等待修复（2026-10-15）

上游提交 `67e5f2dc99b4fb62fe714b45d7d6acc56e7afad2` 修正 WebBookFetchRuntime 将网页等待次数截断为 20 次的问题；现在尊重请求的等待次数（上限 120），同时保留请求总超时。等待条件未满足时显式失败，不再将初始 HTML 冒充成功正文。通过 sync-light-source.cjs 同步；test-comic-web-wait.cjs 覆盖延迟出现、条件不满足和硬超时。
公共封面解密扩展已合入独立仓库 `main`，精确提交见 `third_party/light-source/upstream.json`。同步种子包含 `SourceCoverLoader.ts`；宿主只负责加载调度、缓存和 ArkUI 显示。不得直接修改同步生成的解密文件，网站密钥只保存在用户导入定义中。
