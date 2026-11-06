# CBA / ACE decoder

The decoder is a bounded C++ adaptation of the bitstream, Huffman, LZ77,
DELTA, EXE, SOUND and PIC algorithms in Daniel Roethlisberger's `acefile`:

- Upstream: https://github.com/droe/acefile
- Revision: `11ed076ae19e8228148731cfbc05f019a395b3b9`
- Source: `acefile.py`, classes BitStream, Huffman, LZ77, Sound, Pic and ACE.
- License: BSD-2-Clause, reproduced in `LICENSE`.

`AceArchive` is the application container adapter. It validates header/file
CRCs, runs physical entry order for solid archives, and writes only generated
image paths. Archive filenames are used solely for natural page ordering.
It never extracts an archive-supplied path. Passwords and split volumes are
explicitly rejected. All native work is called from `CbaImportWorker` in a taskpool.

Bounds: 3 GiB input, 50000 headers, 32 MiB packed / 20 MiB unpacked per entry,
6 GiB total unpacked content, 4 MiB LZ dictionary, 3 minute decode deadline.
The ArkTS worker additionally validates image dimensions and rejects corrupt
or unsupported images. Import failures roll back the entire book directory.

Regression: `scripts/test-cba-native.py` builds the same decoder for the
connected HarmonyOS emulator/device and compares results against independent
`acefile` output. See its `--help` for requirements. Python is a host test
dependency only; the application contains no Python runtime.
