# 简听主题制作器

App、网页和 Windows 使用同一份主题包与字段定义。编辑内容包括配色、通用及四个主页面背景、播放器背景、Tab 常态／选中图片、功能图标、默认书封及装饰、材质与底栏样式。阅读器继续使用独立设置。

用户操作步骤见 [主题制作说明书](../../docs/THEME_EDITOR_GUIDE.md)，包含素材编辑、浅深预览、导出分享与手机导入应用。

AI 制作主题使用 [主题 AI 制作规范](../../docs/THEME_AI_GUIDE.md)，可将该文件与风格要求一起发送给 AI，生成包含浅深配置及素材的 `.jttheme`。

网页采用 Vite 和原生 JavaScript，Windows 由 Electron 加载同一份生产页面。两个界面均支持浅深并列预览、点击预览定位字段、图片选择、主题导入及导出。App 使用 ArkUI V2 原生制作器。

## 开发与构建

需要 Node.js 22.12+。

```powershell
cd D:\HSDA\tools\theme-editor
npm install
npm run dev
npm run build
```

网页构建输出到 `dist/`，可部署到静态站点目录。开发服务默认使用本机地址。

Windows 初次准备运行时后启动或打包：

```powershell
npm run setup:desktop
npm run desktop
npm run package:win
```

`setup:desktop` 从 Electron 官方发布地址获取当前依赖版本的 Windows x64 运行时。Windows 便携版输出到 `release/JianTing-Theme-Editor-1.0.0.exe`。签名由正式发布流程配置。

## 共用契约

- 字段表：`entry/src/main/resources/rawfile/theme_editor_schema.json`。
- 文案：`entry/src/main/resources/base/element/theme_editor.json`。
- ZIP 读写：`src/package.js`。
- App 模型：`entry/src/main/ets/model/ThemeDocument.ets`。
- 包格式与接入说明：[主题套装文档](../../docs/THEME_BUNDLE_PLAN.md)。

编辑区的数据随 `.jttheme` 文件保存；再次导入即可继续编辑。会员权益在 App 保存和应用自制套装时核验。
