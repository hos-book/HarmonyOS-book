"""Restore the pinned CPU-only llama.cpp sources used by local role attribution.

No model weights, tools, servers, downloads at app runtime, or optional GPU backends.
The extracted files are the unmodified upstream build inputs and their licenses.
"""
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
COMMIT = "cd959bae99ff4bed22bef2604f45241c09bbb8c8"
ARCHIVE_SHA256 = "fbe74146a3cdc00f706773eb233bc4aedb7d8c3c7e2122440e492a99c1ec5a76"
DEST = ROOT / "third_party" / "role-llama"
URL = f"https://codeload.github.com/ggml-org/llama.cpp/tar.gz/{COMMIT}"


def selected(name):
    parts = PurePosixPath(name).parts
    if name in ("CMakeLists.txt", "LICENSE", "ggml/CMakeLists.txt", "ggml/LICENSE"):
        return True
    if parts[0] in ("include", "src", "cmake"):
        return True
    if name == "vendor/CMakeLists.txt" or name.startswith(("vendor/hash/", "vendor/miniaudio/",
            "vendor/nlohmann/", "vendor/sheredom/", "vendor/stb/")):
        return True
    if name.startswith(("ggml/include/", "ggml/cmake/", "ggml/src/ggml-cpu/")):
        return True
    return len(parts) == 3 and parts[:2] == ("ggml", "src")


def main():
    with urllib.request.urlopen(URL, timeout=60) as response:
        data = response.read(100 * 1024 * 1024 + 1)
    if len(data) > 100 * 1024 * 1024:
        raise RuntimeError("Source archive exceeds limit")
    digest = hashlib.sha256(data).hexdigest()
    if digest != ARCHIVE_SHA256:
        raise RuntimeError("Pinned archive checksum mismatch")
    manifest = DEST / "upstream.json"
    if manifest.exists() and json.loads(manifest.read_text())['archiveSha256'] != digest:
        raise RuntimeError("Pinned archive checksum mismatch")
    count = 0
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        for member in archive:
            relative = PurePosixPath(member.name).parts[1:]
            if not member.isfile() or not relative or '..' in relative:
                continue
            name = '/'.join(relative)
            if not selected(name):
                continue
            target = DEST.joinpath(*relative)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.extractfile(member).read())
            count += 1
    manifest.write_text(json.dumps({"repository": "https://github.com/ggml-org/llama.cpp",
        "version": "v0.9.0", "commit": COMMIT, "archiveSha256": digest,
        "scope": "Unmodified CPU library build inputs; no model weights"}, indent=2) + '\n')
    license_path = ROOT / 'entry/src/main/resources/rawfile/third_party/role_llama/LICENSE.txt'
    license_path.parent.mkdir(parents=True, exist_ok=True)
    license_path.write_bytes((DEST / 'LICENSE').read_bytes())
    print(f"Restored {count} source files at {COMMIT}; archive SHA256 {digest}")


if __name__ == '__main__':
    main()
