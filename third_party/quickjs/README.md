# QuickJS 本地 HAR

该目录只包含 `@devzeng/quickjs`、QuickJS 引擎及 HarmonyOS N-API 封装，不包含轻页的 GPL-3.0 书源实现。

当前模块在上游 `@devzeng/quickjs` 0.1.0 基础上增加了：

- 可配置 QuickJS heap 与 stack 上限；
- 使用 `JS_SetInterruptHandler` 的 `evaluateBounded`；
- pending-job 数量预算；
- 单次 `evaluateBounded` 内的 JSON 宿主回调：后台 taskpool 暂停等待主线程有界邮箱，收到响应后继续当前调用栈，不保留跨任务会话；原生计算预算扣除宿主等待，取消信号仍触发 interrupt；最多 4096 次、输入 4 MiB、返回 8 MiB、累计 64 MiB，独立总时长硬上限 16 分钟（应用另限阶段 60 秒、表达式 10 秒并扣除人工验证等待）；
- 可选的二进制输入/输出，正确处理字节视图偏移；图片任务通过共享 Int32Array 取消信号触发原生中断；
- 图片原生桥只接受 encrypt/decrypt/hash/hmac，单次 20 MiB、最多 32 次调用和累计 128 MiB；系统调用返回后检查取消及 10 秒总预算；
- 在同一超时与 pending-job 预算内取得返回 Promise 的完成值，未完成或拒绝的 Promise 返回失败；
- `arm64-v8a` 与 `x86_64` 双 ABI 构建。

使用 API 26 DevEco Studio 工具链重建并同步本地依赖；最低兼容版本为 `6.0.0(20)`，与主工程一致。更新后同时同步 HAR、SHA256 和主工程依赖锁文件：

```powershell
.\scripts\build-quickjs.ps1
```

主项目通过 `entry/libs/quickjs.har` 消费产物，不需要在根 `build-profile.json5` 注册 quickjs 模块。
业务代码只能通过 `LocalRuleQuickJsRuntime` 调用 `evaluateBounded`，不得直接调用不受限的 `evaluateScript`。

许可证和来源见根目录 `THIRD_PARTY_NOTICES.md` 及本目录的许可文件。
