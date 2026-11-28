# 简听主题制作器

App、网页和 Windows 使用同一份主题包与字段定义。编辑内容包括配色、通用及四个主页面背景、播放器背景、Tab 常态／选中图片、功能图标、默认书封及装饰。应用自制主题时，材质强度与底栏样式继续沿用 App 当前偏好；阅读器继续使用独立设置。

用户操作步骤见 [主题制作说明书](../../docs/THEME_EDITOR_GUIDE.md)，包含素材编辑、浅深预览、导出分享与手机导入应用。

AI 制作主题使用 [主题 AI 制作规范](../../docs/THEME_AI_GUIDE.md)，可从制作器顶部“AI 制作规范”打开 GitHub 文档，再将整份文档与风格要求一起发送给 AI。规范要求首页、书架、记录、我的分别设计独立背景，浅色与深色各四张，共八张成品，生成包含浅深配置及素材的 `.jttheme`。

网页采用 Vite 和原生 JavaScript，Windows 由 Electron 加载同一份生产页面。两个界面均支持浅深并列预览、点击预览定位字段、图片选择、主题导入及导出。App 使用 ArkUI V2 原生制作器。

在线入口：https://hos-book.github.io/HarmonyOS-book/theme-editor/ 。浏览器内完成编辑，导出 `.jttheme` 后传到手机，在简听阅读中导入应用。

预览分别绘制首页、书架、阅听记录、我的和播放器，沿用 App 页面结构、字号、间距、书封比例和顶部按钮尺寸。支持手机 400×880、平板 834×1112、电脑 1280×800 的窗口预设，按画布空间整体缩放；书架可查看网格、列表、书房，迷你播放器与底栏排列可在预览工具栏调整。预览中的书籍和账号用于展示主题，原生光感材质以 App 为准。

“顶部按钮”分组提供书架、记录页共 23 个独立整按钮素材字段，支持透明 PNG／WebP 和状态预览。图片同时包含图标与底板，实际操作由 App 保留。完整主题字段共 134 项，主题包版本为 1。

右箭头统一显示系统符号，功能图标编辑项包含搜索、筛选、网格与列表。网页和 Windows 预览与 App 保持一致，主题包导入及导出时移除旧的右箭头图片字段。

## 开发与构建

需要 Node.js 22.12+。

```powershell
cd D:\HSDA\tools\theme-editor
npm install
npm run dev
npm run build
```

网页构建输出到 `dist/`，可部署到静态站点目录。开发服务默认使用本机地址。

GitHub Pages 由 `.github/workflows/app-gallery-pages.yml` 发布。推送制作器、主题字段或引用资源到 `main` 后，工作流构建网页，将应用介绍页与 `dist/` 合并到发布目录，制作器位于 `theme-editor/`。仓库 Pages 的构建来源设置为 GitHub Actions。相对资源路径同时适用于 Pages 子目录和 Electron。

预览实现位于 `src/preview.js` 与 `src/preview.css`；展示文案位于 `src/preview-copy.json`，字段和主题文件读写继续共用原有契约。图标来源与授权见 `src/assets/harmony/README.md`。

书架与阅听足迹沿用 App 的固定物理书封及默认文字；主题书封素材与装饰可在首页和播放器查看。

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
