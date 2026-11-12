"""Build the import ZIP from an already downloaded official Kokoro archive.

No network access and no model weights in the application package. Download:
https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-int8-multi-lang-v1_1.tar.bz2
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import tarfile
import zipfile


ROOT = Path(__file__).resolve().parent.parent
MODEL_ID = "kokoro-int8-v1_1"
CHUNK_BYTES = 4 * 1024 * 1024
MAX_BYTES = 512 * 1024 * 1024
MAX_MANIFEST = 128 * 1024


def load_spec(path):
    data = json.loads(path.read_text(encoding="utf-8"))
    files = data["files"]
    if not 9 <= len(files) <= 512:
        raise ValueError("Invalid pinned asset count")
    seen = set()
    total = 0
    data_bytes = 0
    for asset in files:
        name, size, digest = asset["path"], asset["bytes"], asset["sha256"]
        parts = name.split("/")
        if (name in seen or len(parts) > 6 or any(p in ("", ".", "..") for p in parts)
                or "\\" in name or not name.isascii()
                or any(not (c.isalnum() or c in "-_.+!/ ") for c in name)
                or not isinstance(size, int) or size <= 0
                or len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest)):
            raise ValueError(f"Invalid pinned asset: {name}")
        if name.startswith("espeak-ng-data/"):
            if size > 16 * 1024 * 1024:
                raise ValueError("Oversized eSpeak asset")
            data_bytes += size
        seen.add(name)
        total += size
    if total > MAX_BYTES or data_bytes > 32 * 1024 * 1024:
        raise ValueError("Pinned model exceeds import budget")
    return files


def write_entry(archive, name, content):
    info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_STORED
    info.external_attr = 0o100644 << 16
    archive.writestr(info, content)


def pack(source, target, spec, force):
    if source.resolve() == target.resolve():
        raise ValueError("Output must differ from the source archive")
    if target.exists() and not force:
        raise ValueError("Output already exists; use --force to replace it")
    files = load_spec(spec)
    manifest = {
        "format": 1, "id": MODEL_ID, "chunkBytes": CHUNK_BYTES,
        "assets": [{"name": f["path"], "bytes": f["bytes"], "sha256": f["sha256"]} for f in files],
    }
    raw = json.dumps(manifest, ensure_ascii=True, separators=(",", ":")).encode("utf-8")
    if len(raw) > MAX_MANIFEST:
        raise ValueError("Import manifest exceeds 128 KiB")
    prefix = "kokoro-int8-multi-lang-v1_1/"
    expected = {prefix + f["path"]: f for f in files}
    seen = set()
    target.parent.mkdir(parents=True, exist_ok=True)
    partial = target.with_name(target.name + ".partial")
    if partial.exists():
        raise ValueError(f"Partial output exists: {partial}")
    try:
        with tarfile.open(source, mode="r|bz2") as source_tar, zipfile.ZipFile(partial, "x") as output:
            write_entry(output, "offline-tts.json", raw)
            for count, member in enumerate(source_tar):
                if count > 5000:
                    raise ValueError("Source archive has too many entries")
                normalized = member.name.removeprefix("./")
                asset = expected.get(normalized)
                if asset is None:
                    continue
                name = asset["path"]
                if name in seen or not member.isfile() or member.size != asset["bytes"]:
                    raise ValueError(f"Invalid source asset: {name}")
                reader = source_tar.extractfile(member)
                if reader is None:
                    raise ValueError(f"Missing source data: {name}")
                digest = hashlib.sha256()
                with reader:
                    for offset in range(0, asset["bytes"], CHUNK_BYTES):
                        length = min(CHUNK_BYTES, asset["bytes"] - offset)
                        chunk = reader.read(length)
                        if len(chunk) != length:
                            raise ValueError(f"Truncated source data: {name}")
                        digest.update(chunk)
                        write_entry(output, f"{name}/{offset // CHUNK_BYTES}.bin", chunk)
                if digest.hexdigest() != asset["sha256"]:
                    raise ValueError(f"SHA256 mismatch: {name}")
                seen.add(name)
            missing = sorted(f["path"] for f in files if f["path"] not in seen)
            if missing:
                raise ValueError(f"Source is not the pinned complete model: missing {', '.join(missing[:8])}")
        os.replace(partial, target)
    finally:
        if partial.exists():
            partial.unlink()
    print(f"Created {target} ({target.stat().st_size:,} bytes; {len(files)} verified assets)")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Downloaded kokoro-int8-multi-lang-v1_1.tar.bz2")
    parser.add_argument("--output", type=Path,
                        default=ROOT / "artifacts/model-packs/v1/Jianting-local-tts-kokoro-v1_1.zip")
    parser.add_argument("--spec", type=Path, default=ROOT / "scripts/offline-tts-assets.json")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    try:
        pack(args.source, args.output, args.spec, args.force)
    except (OSError, ValueError, KeyError, tarfile.TarError, zipfile.BadZipFile) as error:
        parser.exit(1, f"Kokoro packaging failed: {error}\n")


if __name__ == "__main__":
    main()
