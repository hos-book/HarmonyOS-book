import struct, os

d = r"D:\HSDA\.creative-design\vip-badges"
for f in ["vip_month_new.png", "vip_year_new.png", "vip_life_new.png"]:
    p = os.path.join(d, f)
    with open(p, "rb") as fh:
        head = fh.read(33)
    ihdr = head[16:26]
    w, h = struct.unpack(">II", ihdr)
    bitdepth, colortype = head[24], head[25]
    print(f, os.path.getsize(p), f"{w}x{h}", "bitdepth", bitdepth,
          "colortype", colortype, "(6=RGBA,2=RGB-no-alpha)")
