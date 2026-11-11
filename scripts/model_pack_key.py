"""Keep the model-pack release key local; generate only a private native build header."""
import argparse
import hashlib
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KEY_FILE = ROOT / 'signing/model-pack.key'


def load_key(create=False):
    if not KEY_FILE.exists() and create:
        KEY_FILE.parent.mkdir(parents=True, exist_ok=True)
        try:
            with KEY_FILE.open('xb') as output:
                output.write(os.urandom(32))
        except FileExistsError:
            pass
    if not KEY_FILE.exists():
        raise ValueError('Missing private model-pack key; restore signing/model-pack.key from your secure backup')
    key = KEY_FILE.read_bytes()
    if len(key) != 32:
        raise ValueError('Invalid private model-pack key')
    return key


def key_id(key):
    return hashlib.sha256(key).hexdigest()[:16]


def write_header(path):
    key = load_key()
    mask = os.urandom(32)
    encoded = bytes(a ^ b for a, b in zip(key, mask))
    array = lambda value: ','.join(str(byte) for byte in value)
    content = ('// Generated in the native build directory. Never commit.\n'
               # Volatile loads prevent the optimizer folding XOR back into a raw key constant.
               f'static const volatile unsigned char PACK_KEY_MASK[32] = {{{array(mask)}}};\n'
               f'static const volatile unsigned char PACK_KEY_DATA[32] = {{{array(encoded)}}};\n'
               f'static constexpr char PACK_KEY_ID[] = "{key_id(key)}";\n')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--header', type=Path, required=True)
    write_header(parser.parse_args().header)
