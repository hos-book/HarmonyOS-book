"""Verify the 7 JPG posters: 1080x1920, 9:16, under 5 MB."""
from pathlib import Path
from PIL import Image

OUT = Path(__file__).resolve().parent
ok = True
for f in sorted(OUT.glob("*.jpg")):
    img = Image.open(f)
    w, h = img.size
    ratio = w / h
    kb = f.stat().st_size / 1024
    size_ok = f.stat().st_size <= 5 * 1024 * 1024
    ratio_ok = abs(ratio - 9 / 16) < 0.005
    dim_ok = w == 1080 and h == 1920
    ok &= size_ok and ratio_ok and dim_ok
    print(f"{f.name:18s} {w}x{h} ratio={ratio:.4f} {kb:7.1f}KB "
          f"size={'OK' if size_ok else 'OVER'} ratio={'OK' if ratio_ok else 'BAD'} dim={'OK' if dim_ok else 'BAD'}")
print("\nALL PASS" if ok else "\nFAIL")
