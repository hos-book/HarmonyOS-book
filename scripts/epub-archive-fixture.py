"""Read a user-supplied EPUB for host regression; never extract archive paths to disk."""
import base64
import json
import posixpath
import sys
import zipfile
import xml.etree.ElementTree as ET
from io import BytesIO
from PIL import Image

def resolve(parent, href):
    return posixpath.normpath(posixpath.join(posixpath.dirname(parent), href.split('#')[0]))

with zipfile.ZipFile(sys.argv[1]) as archive:
    if sum(item.file_size for item in archive.infolist()) > 128 * 1024 * 1024:
        raise ValueError('Host fixture expanded size exceeds 128 MiB')
    container = ET.fromstring(archive.read('META-INF/container.xml'))
    opf = next(item.attrib['full-path'] for item in container.iter() if item.tag.endswith('rootfile'))
    package = ET.fromstring(archive.read(opf))
    manifest = {item.attrib['id']: item.attrib for item in package.iter() if item.tag.endswith('}item')}
    spines = [{'idRef': item.attrib['idref'], 'href': resolve(opf, manifest[item.attrib['idref']]['href'])}
              for item in package.iter() if item.tag.endswith('itemref')]
    catalog = []
    for item in manifest.values():
        if item.get('media-type') == 'application/x-dtbncx+xml':
            ncx_path = resolve(opf, item['href'])
            ncx = ET.fromstring(archive.read(ncx_path))
            for point in ncx.iter():
                if not point.tag.endswith('navPoint'):
                    continue
                content = next((v for v in point if v.tag.endswith('content')), None)
                label = next((v for v in point if v.tag.endswith('navLabel')), None)
                if content is not None and label is not None:
                    href = content.attrib['src']
                    target = resolve(ncx_path, href)
                    catalog.append({'href': target + ('#' + href.split('#', 1)[1] if '#' in href else ''),
                                    'resourceFile': target, 'catalogName': ''.join(label.itertext()).strip()})
    entries = {name: base64.b64encode(archive.read(name)).decode('ascii') for name in archive.namelist()
               if name.lower().endswith(('.xhtml', '.html', '.htm', '.css', '.jpg', '.jpeg', '.png', '.webp', '.svg', '.opf', '.xml',
                                        '.ttf', '.otf', '.woff', '.woff2', '.mp3', '.mp4', '.m4a', '.wav', '.aac', '.webm', '.ogg', '.vtt'))}
    title = next((item.text for item in package.iter() if item.tag.endswith('}title')), '')
    author = next((item.text for item in package.iter() if item.tag.endswith('}creator')), '')
    sizes = {}
    for name, encoded in entries.items():
        if name.lower().endswith(('.jpg', '.jpeg', '.png', '.webp')):
            with Image.open(BytesIO(base64.b64decode(encoded))) as picture:
                picture.load()
                sizes[encoded] = {'width': picture.width, 'height': picture.height}
    json.dump({'spines': spines, 'catalog': catalog, 'entries': entries, 'imageSizes': sizes,
               'bookInfo': {'bookTitle': title, 'bookCreator': author}}, sys.stdout, ensure_ascii=True)
