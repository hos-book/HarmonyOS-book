"""Compare real C++ ACE decoding on HarmonyOS with upstream acefile, without Python in the app."""
import argparse
import concurrent.futures
import importlib.util
import os
import pathlib
import shutil
import struct
import subprocess
import tempfile
import urllib.request
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
PIN = '11ed076ae19e8228148731cfbc05f019a395b3b9'
UNACE_PIN = '7fc958444a6befebe65e00db36e1985651b2770d'

def fetch(url, path):
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=30) as response:
                path.write_bytes(response.read())
            break
        except OSError:
            if attempt == 2:
                raise
    return path

def checksum(data):
    return zlib.crc32(data) ^ 0xffffffff

def header(data):
    return struct.pack('<HH', checksum(data) & 65535, len(data)) + data

def archive(entries, solid=False, flags=0):
    main = struct.pack('<BH7sBBBBI8sB', 0, flags | (0x8000 if solid else 0), b'**ACE**', 20, 20, 0, 0, 0, b'\0' * 8, 0)
    result = header(main)
    for name, raw, packed, method in entries:
        name = name.encode('utf-8')
        body = struct.pack('<BHIIIIIBBHHH', 1, 1, len(packed), len(raw), 0, 0, checksum(raw), method, 0, 12, 0, len(name)) + name
        result += header(body) + packed
    return result

class BitWriter:
    def __init__(self, oracle):
        self.bits = []
        self.oracle = oracle

    def put(self, value, width):
        assert value >= 0 and value < 1 << width
        self.bits.extend((value >> i) & 1 for i in reversed(range(width)))

    def code(self, tree, symbol):
        width = tree.widths[symbol]
        code = tree.codes.index(symbol) >> (tree.max_width - width)
        self.put(code, width)

    def tree(self, widths, maximum):
        self.put(len(widths) - 1, 9)
        self.put(0, 4)
        upper = max(widths) + 1
        self.put(upper, 4)
        small_widths = [4] * (upper + 1)
        for width in small_widths:
            self.put(width, 3)
        small = self.oracle.Huffman._make_tree(small_widths, 7)
        previous = 0
        for width in widths:
            self.code(small, (width - previous) % upper)
            previous = width
        return self.oracle.Huffman._make_tree(list(widths), maximum)

    def rice(self, value, width, signed=False):
        if signed:
            value = -2 * value - 1 if value < 0 else 2 * value
        self.put(value & ((1 << width) - 1), width)
        for _ in range(value >> width):
            self.put(1, 1)
        self.put(0, 1)

    def finish(self):
        self.bits.extend([0] * ((-len(self.bits)) % 32))
        output = bytearray()
        for start in range(0, len(self.bits), 32):
            value = 0
            for bit in self.bits[start:start + 32]:
                value = (value << 1) | bit
            output += struct.pack('<I', value)
        return bytes(output)

def lz_pack(oracle, data, mode=None):
    """A literal/copy stream with independent Huffman trees, plus optional ACE2 filters."""
    writer = BitWriter(oracle)
    main = writer.tree([9] * 284, 11)
    lengths = writer.tree([8] * 256, 11)
    commands = []
    index = 0
    while index < len(data):
        if index and data[index] == data[index - 1]:
            end = index
            while end < len(data) and data[end] == data[index - 1] and end - index < 257:
                end += 1
            if end - index >= 2:
                commands.append((260, end - index - 2))
                index = end
                continue
        commands.append((data[index], None))
        index += 1
    writer.put(len(commands) + (1 if mode is not None else 0), 15)
    if mode is not None:
        writer.code(main, 283)
        writer.put(mode, 8)
        if mode == 1:
            writer.put(2, 8)
            writer.put(len(data), 17)
        if mode == 2:
            writer.put(1, 8)
    for symbol, length in commands:
        writer.code(main, symbol)
        if length is not None:
            writer.code(lengths, length)
    return writer.finish()

def create_fixtures(oracle):
    # Valid 2x2 BMPs, different pixels, deliberately non-lexical page order and hostile path.
    def bmp(color):
        pixels = bytes(color) * 2 + b'\0\0'
        pixels *= 2
        return b'BM' + struct.pack('<IHHI', 54 + len(pixels), 0, 0, 54) + struct.pack('<IIIHHIIIIII', 40, 2, 2, 1, 24, 0, len(pixels), 0, 0, 0, 0) + pixels
    images = [bmp((255, 0, 0)), bmp((0, 255, 0)), bmp((0, 0, 255))]
    entries = [(name, raw, lz_pack(oracle, raw), 1) for name, raw in zip(['page10.bmp', 'page2.bmp', 'page1.bmp'], images)]
    fixtures = {'comic.cba': archive(entries), 'solid.cba': archive(entries, True)}
    fixtures['traversal.cba'] = archive([('../page1.bmp', images[0], lz_pack(oracle, images[0]), 1)])
    raw = b'abc' * 10 + bytes(range(30))
    for mode in [0, 1, 2]:
        packed = lz_pack(oracle, raw, mode)
        expected = b''.join(oracle.ACE().decompress_blocked(__import__('io').BytesIO(packed), len(raw), 1 << 22))
        fixtures[f'mode{mode}.ace'] = archive([('test.bin', expected, packed, 2)])
    # PIC: one zero row (predictor 0, Rice epsilon 0), then EOF by output size.
    writer = BitWriter(oracle)
    main = writer.tree([9] * 284, 11)
    writer.tree([8] * 256, 11)
    writer.put(1, 15); writer.code(main, 283); writer.put(7, 8)
    writer.rice(12, 12); writer.rice(1, 2); writer.put(1, 1)
    for used in range(1, 13):
        writer.rice(0, (4 // used).bit_length(), True)
    fixtures['pic.ace'] = archive([('pic.bin', b'\0' * 12, writer.finish(), 2)])
    # SOUND modes 3..6: zero predictor samples, explicit symbol values.
    for mode, channels in [(3, 1), (4, 2), (5, 3), (6, 3)]:
        writer = BitWriter(oracle)
        main = writer.tree([9] * 284, 11); writer.tree([8] * 256, 11)
        writer.put(1, 15); writer.code(main, 283); writer.put(mode, 8)
        sound_trees = [writer.tree([9] * 289, 10) for _ in range(channels * 3)]
        writer.put(16, 15)
        for _ in range(16):
            writer.code(sound_trees[0], 32)
        fixtures[f'sound{mode}.ace'] = archive([('sound.bin', b'\0' * 16, writer.finish(), 2)])
    broken = bytearray(fixtures['comic.cba']); broken[-8] ^= 128
    fixtures['bad-crc.cba'] = bytes(broken)
    fixtures['truncated.cba'] = fixtures['comic.cba'][:-7]
    fixtures['volume.cba'] = archive(entries, flags=0x800)
    return fixtures, images

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--deveco', default=os.environ.get('DEVECO_HOME'))
    parser.add_argument('--device', default='127.0.0.1:5555')
    parser.add_argument('--oracle', help='Existing acefile.py; otherwise download pinned upstream to temporary directory')
    parser.add_argument('--keep', help='Optional directory for generated fixture copies (for app smoke tests)')
    args = parser.parse_args()
    if not args.deveco:
        parser.error('DEVECO_HOME or --deveco is required')
    sdk = pathlib.Path(args.deveco) / 'sdk/default/openharmony'
    hdc = sdk / 'toolchains/hdc.exe'
    def run(command, **kwargs):
        return subprocess.run([str(x) for x in command], check=True, capture_output=True, text=True, timeout=180, **kwargs).stdout.strip()
    def device(*command):
        return run([hdc, '-t', args.device, *command])
    remote = '/data/local/tmp/hsda-cba-regression'
    with tempfile.TemporaryDirectory(prefix='hsda-cba-') as temporary:
        work = pathlib.Path(temporary)
        oracle_file = pathlib.Path(args.oracle) if args.oracle else fetch(f'https://raw.githubusercontent.com/droe/acefile/{PIN}/acefile.py', work / 'acefile.py')
        spec = importlib.util.spec_from_file_location('acefile', oracle_file)
        oracle = importlib.util.module_from_spec(spec); spec.loader.exec_module(oracle)
        fixtures, images = create_fixtures(oracle)
        for name, content in fixtures.items():
            (work / name).write_bytes(content)
        corpus = [('v1-onefile.ace', 'tests.ace.v1/onefile.ace'), ('v1-zgfx.ace', 'tests.ace.v1/ZGFX2.ace'), ('v2-dir.ace', 'tests.ace.v2/dir2.ace')]
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
            list(pool.map(lambda pair: fetch(f'https://raw.githubusercontent.com/wdlkmpx/unace/{UNACE_PIN}/{pair[1]}', work / pair[0]), corpus))
        if args.keep:
            destination = pathlib.Path(args.keep); destination.mkdir(parents=True, exist_ok=True)
            shutil.copy2(work / 'comic.cba', destination / 'comic.cba')
        architecture = device('shell', 'uname', '-m')
        target = 'aarch64' if 'aarch64' in architecture else 'x86_64'
        compiler = sdk / 'native/llvm/bin/clang++.exe'
        exe = work / 'ace-probe'
        sources = [ROOT / 'scripts/cba-native-probe.cpp', ROOT / 'entry/src/main/cpp/ace/AceArchive.cpp', ROOT / 'entry/src/main/cpp/ace/AceDecoder.cpp']
        run([compiler, f'--target={target}-linux-ohos', f'--sysroot={sdk / "native/sysroot"}', '-std=c++17', '-O2', '-Wall', '-Wextra', '-static-libstdc++', *sources, '-o', exe])
        device('shell', 'mkdir', '-p', remote)
        try:
            device('file', 'send', exe, remote + '/ace-probe')
            device('shell', 'chmod', '700', remote + '/ace-probe')
            for file in sorted(work.iterdir()):
                if file.suffix not in ['.ace', '.cba']:
                    continue
                remote_file = remote + '/' + file.name
                device('file', 'send', file, remote_file)
                result = device('shell', remote + '/ace-probe', remote_file)
                if file.name in ['bad-crc.cba', 'truncated.cba', 'volume.cba']:
                    assert 'ERROR import_cba_' in result, (file.name, result)
                    print('PASS rejected', file.name, flush=True)
                    continue
                expected = []
                with oracle.open(str(file)) as reader:
                    for index, member in enumerate(reader):
                        data = reader.read(member)
                        hash_value = 14695981039346656037
                        for byte in data:
                            hash_value = ((hash_value ^ byte) * 1099511628211) & ((1 << 64) - 1)
                        expected.append(f'{index} {len(data)} {hash_value:x}')
                assert result.splitlines() == expected, (file.name, result, expected)
                print('PASS decoder', file.name, len(expected), 'entries', flush=True)
            output = remote + '/pages'
            device('shell', 'mkdir', '-p', output)
            result = device('shell', remote + '/ace-probe', remote + '/comic.cba', output)
            assert result == 'pages 3', result
            # ../page2 never becomes a filesystem path, and 1/2/10 order is natural.
            for index, expected in enumerate([images[2], images[1], images[0]]):
                actual = work / f'page{index}.img'
                device('file', 'recv', output + f'/image_{index}_0.img', actual)
                assert actual.read_bytes() == expected
            traversal = remote + '/traversal'
            device('shell', 'mkdir', '-p', traversal)
            assert device('shell', remote + '/ace-probe', remote + '/traversal.cba', traversal) == 'pages 1'
            assert 'No such file' in device('shell', 'ls', remote + '/page1.bmp')
            print('PASS extraction: generated paths, natural order, original image bytes', flush=True)
        finally:
            # Fixed task-specific directory, created above; never remove a user data path.
            device('shell', 'rm', '-rf', remote)

if __name__ == '__main__':
    main()
