# 第三方资源

项目源码从开源轻页拆出，遵循 GPL-3.0。资源各自的许可证保持不变。

- **OpenCC ver.1.1.9**：BYVoid and OpenCC contributors；Apache-2.0。原始 TSCharacters / TSPhrases 字典、来源、哈希与完整许可见 [opencc](aiengine/src/main/resources/rawfile/opencc/NOTICE.md)。本库实现词组最长匹配的繁→简适配器，不是完整 OpenCC 引擎。
- **Manga-Colorizer / AlacGAN**：固定上游提交 `623f5a2a9dc3bb4fc0c8edbfa2d22de43f8f6ea7`，采用上游仓库 MIT 声明。来源、权重、转换参数与 SHA-256 见 [model.json](aiengine/src/main/resources/rawfile/comic-colorizer/model.json)，完整声明见 [LICENSE](aiengine/src/main/resources/rawfile/comic-colorizer/LICENSE)。转换模型随 HAR 打包。

HarmonyOS CoreVisionKit 和 MindSporeLiteKit 由设备系统提供，本库不分发这些系统运行时。
