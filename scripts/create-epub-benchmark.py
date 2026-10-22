"""Generate the disposable 5000-chapter EPUB fixture for LocalBookImportBenchmark."""
from pathlib import Path
import zipfile

target = Path(__file__).resolve().parents[1] / 'entry/src/ohosTest/resources/rawfile/import-benchmark.epub'
target.parent.mkdir(parents=True, exist_ok=True)
count = 5000
with zipfile.ZipFile(target, 'w', compression=zipfile.ZIP_DEFLATED) as book:
    book.writestr('mimetype', 'application/epub+zip', compress_type=zipfile.ZIP_STORED)
    book.writestr('META-INF/container.xml', '<?xml version="1.0"?><container version="1.0" '
                  'xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile '
                  'full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
    manifest = ''.join(f'<item id="c{i}" href="text/{i}.xhtml" media-type="application/xhtml+xml"/>' for i in range(count))
    spine = ''.join(f'<itemref idref="c{i}"/>' for i in range(count))
    book.writestr('OEBPS/content.opf', '<?xml version="1.0" encoding="utf-8"?><package version="2.0" '
                  'unique-identifier="id" xmlns="http://www.idpf.org/2007/opf"><metadata '
                  'xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>5000章导入基准</dc:title>'
                  '<dc:creator>测试作者</dc:creator><dc:language>zh-CN</dc:language><dc:identifier id="id">'
                  'hsda-import-benchmark</dc:identifier></metadata><manifest><item id="ncx" href="toc.ncx" '
                  f'media-type="application/x-dtbncx+xml"/>{manifest}</manifest><spine toc="ncx">{spine}</spine></package>')
    toc = ''.join(f'<navPoint id="n{i}" playOrder="{i + 1}"><navLabel><text>第{i + 1}章 原书目录</text>'
                  f'</navLabel><content src="text/{i}.xhtml"/></navPoint>' for i in range(count))
    book.writestr('OEBPS/toc.ncx', '<?xml version="1.0" encoding="utf-8"?><ncx '
                  'xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head>'
                  '<meta name="dtb:uid" content="hsda-import-benchmark"/></head><docTitle>'
                  f'<text>5000章导入基准</text></docTitle><navMap>{toc}</navMap></ncx>')
    for i in range(count):
        paragraphs = ''.join(f'<p>章节正文-{i + 1} 段落-{n}：这是用于核对导入完整性和性能的中文正文。</p>' for n in range(80))
        book.writestr(f'OEBPS/text/{i}.xhtml', '<?xml version="1.0" encoding="utf-8"?><html '
                      'xmlns="http://www.w3.org/1999/xhtml"><head><title>正文</title></head>'
                      f'<body><h1>第{i + 1}章</h1>{paragraphs}</body></html>')
print(f'{target}: {target.stat().st_size} bytes, {count} chapters')
