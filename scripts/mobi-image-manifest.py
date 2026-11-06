"""Independent MOBI6/PalmDOC/image manifest for the real-file import regression."""
import hashlib
import io
import json
import re
import struct
import sys
from PIL import Image

data = open(sys.argv[1], 'rb').read()
count = struct.unpack_from('>H', data, 76)[0]
offsets = [struct.unpack_from('>I', data, 78 + 8 * i)[0] for i in range(count)] + [len(data)]
record = data[offsets[0]:offsets[1]]
compression, = struct.unpack_from('>H', record)
size, records = struct.unpack_from('>IH', record, 4)
encoding, = struct.unpack_from('>I', record, 28)
first_image, = struct.unpack_from('>I', record, 108)
flags, = struct.unpack_from('>H', record, 242)
assert compression in (1, 2) and encoding == 65001

def palmdoc(packed):
    result = bytearray()
    cursor = 0
    while cursor < len(packed):
        code = packed[cursor]; cursor += 1
        if 1 <= code <= 8:
            result.extend(packed[cursor:cursor + code]); cursor += code
        elif code < 128:
            result.append(code)
        elif code < 192:
            pair = (code << 8) | packed[cursor]; cursor += 1
            distance, length = (pair & 0x3fff) >> 3, (pair & 7) + 3
            for _ in range(length):
                result.append(result[-distance])
        else:
            result.extend((32, code ^ 128))
    return result

text = bytearray()
for index in range(1, records + 1):
    packed = data[offsets[index]:offsets[index + 1]]
    for bit in range(1, 16):
        if not (flags & (1 << bit)):
            continue
        length = 0
        for i, value in enumerate(reversed(packed[-4:])):
            length |= (value & 127) << (7 * i)
            if value & 128:
                break
        packed = packed[:-length]
    if flags & 1:
        packed = packed[:-(packed[-1] & 3) - 1]
    text.extend(palmdoc(packed) if compression == 2 else packed)
html = text[:size].decode('utf-8')
references = [int(match.group(1) or match.group(2) or match.group(3)) for match in re.finditer(
    r'<img\b[^>]*\brecindex\s*=\s*(?:"(\d+)"|\'(\d+)\'|(\d+))', html, re.I)]
images = []
for index in sorted(set(references)):
    number = first_image + index - 1
    value = data[offsets[number]:offsets[number + 1]]
    with Image.open(io.BytesIO(value)) as image:
        width, height = image.size
        image.verify()
    images.append({'index': index, 'sha256': hashlib.sha256(value).hexdigest(),
        'size': {'width': width, 'height': height}, 'bytes': len(value)})
print(json.dumps({'references': references, 'images': images}))
