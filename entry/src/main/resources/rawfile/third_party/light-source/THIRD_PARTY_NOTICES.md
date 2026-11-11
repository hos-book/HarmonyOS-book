# 第三方开源软件声明

本项目包含下列第三方开源软件。项目自身的 GPL-3.0 许可证不替代这些组件各自的许可证、版权声明或免责声明。

## ohos_quickjs

- 组件：`@devzeng/quickjs` / `ohos_quickjs`（位于 `quickjs/` 模块）
- 上游项目：https://github.com/hhtczengjing/ohos_quickjs
- 许可证：MIT
- 版权所有：Copyright (c) 2026 zengjing

本项目对该组件进行了 HarmonyOS 集成、稳定性和能力扩展方面的修改（例如带时间与内存上限的受限执行），因此不能直接换成 ohpm 上的公开版本。原始 MIT 许可见 [quickjs/LICENSE](quickjs/LICENSE)。

## QuickJS

- 组件：QuickJS JavaScript Engine（`quickjs/libs/` 下的预编译静态库与 `quickjs/src/main/cpp/include/` 下的头文件）
- 上游项目：https://bellard.org/quickjs/
- 许可证：MIT
- 版权所有：Copyright (c) 2017-2021 Fabrice Bellard；Copyright (c) 2017-2021 Charlie Gordon

## OpenHarmony / Huawei N-API 封装代码

- 组件：带有 Huawei Device Co., Ltd. 版权头的 N-API 封装源文件
- 许可证：Apache License 2.0
- 版权所有：Copyright (c) 2021-2022 Huawei Device Co., Ltd.

本项目修改过的相关文件继续保留原始版权和许可证头；修改内容主要包括 QuickJS 运行时适配、句柄安全、受限执行和 HarmonyOS 应用集成。

## acorn

- 组件：acorn JavaScript 解析器（压缩后内置于 `sourceengine/src/main/ets/core/book/StageScriptParserSource.ts`，由 `scripts/generate-stage-script-parser.mjs` 生成）
- 上游项目：https://github.com/acornjs/acorn
- 许可证：MIT
- 版权所有：Copyright (C) 2012-2022 by various contributors

用于在分阶段运行时里解析兼容书源脚本，使脚本返回值与 Android 端 Rhino 一致。

## 完整许可文本

MIT 与 Apache-2.0 的完整许可文本见 [THIRD_PARTY_LICENSES.txt](THIRD_PARTY_LICENSES.txt)。
