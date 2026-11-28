"""从应用字符串资源导出简听阅读上架隐私政策和图标，避免应用内外文案漂移。"""

import html
import json
import re
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'docs/app-gallery'


def main():
    strings = json.loads((ROOT / 'entry/src/main/resources/base/element/string.json')
                         .read_text(encoding='utf-8'))['string']
    values = {item['name']: item['value'] for item in strings}
    policy = (ROOT / 'entry/src/main/ets/pages/PrivacyPage.ets').read_text(encoding='utf-8')
    version = re.search(r"PRIVACY_POLICY_VERSION = '([^']+)'", policy).group(1)
    section_pattern = r"new PolicySection\('[^']+', \$r\('app.string.([^']+)'\), \[([\s\S]*?)\]\)"
    sections = []
    for title, body in re.findall(section_pattern, policy):
        paragraphs = []
        for key in re.findall(r"\$r\('app.string.([^']+)'", body):
            text = values[key].replace('%s', version)
            paragraphs.append('<p>' + html.escape(text) + '</p>')
        sections.append('<section><h2>' + html.escape(values[title]) + '</h2>\n'
                        + '\n'.join(paragraphs) + '</section>')
    if not sections:
        raise ValueError('未找到应用隐私政策章节')
    document = '''<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="简听阅读隐私政策：了解本地数据、书源访问、系统权限与数据管理方式。">
  <title>简听阅读隐私政策</title>
  <style>
    :root { color-scheme: light dark; }
    body { margin: 0; font: 16px/1.85 system-ui, sans-serif; color: #242424; background: #faf9f7; }
    main { max-width: 760px; margin: 0 auto; padding: 40px 24px 64px; }
    header { border-bottom: 1px solid #dedbd5; padding-bottom: 20px; margin-bottom: 28px; }
    h1 { font-size: 28px; margin: 0; } h2 { font-size: 20px; margin: 30px 0 12px; }
    p { margin: 12px 0; overflow-wrap: anywhere; }
    a { color: #9a4015; } footer { margin-top: 32px; }
    @media (prefers-color-scheme: dark) {
      body { color: #eae7e2; background: #191817; }
      header { border-color: #45413c; } a { color: #ffb58b; }
    }
  </style>
</head>
<body>
<main>
  <header><h1>简听阅读隐私政策</h1><p>开发者：ylwang · 更新日期：2026 年 9 月 14 日</p></header>
''' + '\n'.join(sections) + '''
  <footer><a href="https://github.com/end-web/HarmonyOS-book/issues">联系开发者</a></footer>
</main>
</body>
</html>
'''
    DEST.mkdir(parents=True, exist_ok=True)
    (DEST / 'privacy.html').write_text(document, encoding='utf-8', newline='\n')
    shutil.copyfile(ROOT / 'AppScope/resources/base/media/app_icon_legacy.png', DEST / 'icon.png')
    metadata = json.loads((DEST / 'zh-CN.json').read_text(encoding='utf-8'))
    intro = (metadata['appName'] + '\n\n' + metadata['shortDescription'] + '\n\n'
             + metadata['fullDescription'] + '\n\n新版本说明\n' + metadata['releaseNotes'] + '\n')
    (DEST / 'introduction.txt').write_text(intro, encoding='utf-8', newline='\n')
    description = '\n'.join('<p>' + html.escape(p) + '</p>'
                            for p in metadata['fullDescription'].split('\n\n'))
    gallery = '\n'.join('<img src="' + html.escape(path, quote=True)
                        + '" alt="简听阅读手机应用截图 ' + str(index + 1)
                        + '" width="1280" height="2832" loading="lazy">'
                        for index, path in enumerate(metadata['screenshots']))
    landing = '''<!doctype html>
<html lang="zh-CN"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="简听阅读，一款面向 HarmonyOS 手机的音频收听与小说阅读应用。">
<title>简听阅读 · 随心收听，静心阅读</title>
<link rel="icon" href="icon.png">
<style>
body { margin: 0; color: #292621; background: #faf8f4; font: 16px/1.85 system-ui, sans-serif; }
main { max-width: 1100px; margin: auto; padding: 48px 24px; }
header { max-width: 740px; margin-bottom: 36px; } header img { border-radius: 24px; }
h1 { font-size: 40px; margin: 12px 0 0; } h2 { font-size: 24px; }
.tagline { font-size: 24px; margin: 4px 0 20px; } a { color: #a14818; }
nav { display: flex; gap: 24px; flex-wrap: wrap; } .description { max-width: 780px; }
.description p { white-space: pre-line; } .gallery { display: grid; grid-template-columns: repeat(4, 1fr); gap: 18px; }
.gallery img { width: 100%; height: auto; border-radius: 14px; box-shadow: 0 8px 24px #30231014; }
footer { margin-top: 44px; color: #655e54; }
@media (max-width: 760px) { .gallery { grid-template-columns: repeat(2, 1fr); } }
</style></head><body><main>
<header><img src="icon.png" width="88" height="88" alt="简听阅读图标"><h1>简听阅读</h1>
<p class="tagline">随心收听，静心阅读</p>
<nav><a href="https://github.com/end-web/HarmonyOS-book/releases/latest">版本与下载</a>
<a href="theme-editor/">主题制作器</a><a href="privacy.html">隐私政策</a><a href="https://github.com/hos-book/HarmonyOS-book">项目主页</a></nav></header>
<section class="description"><h2>关于简听阅读</h2>
''' + description + '''</section>
<section><h2>应用截图</h2><div class="gallery">
''' + gallery + '''</div></section>
<footer>简听阅读 · ylwang</footer>
</main></body></html>
'''
    (DEST / 'index.html').write_text(landing, encoding='utf-8', newline='\n')
    print(f'已导出 {len(sections)} 个隐私政策章节和上架图标至 {DEST}')


if __name__ == '__main__':
    main()
