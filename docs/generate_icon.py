import math

def pt(cx, cy, r, deg):
    a = math.radians(deg)
    return cx + r*math.cos(a), cy + r*math.sin(a)

def arc(cx, cy, r, start, sweep):
    x1, y1 = pt(cx, cy, r, start)
    x2, y2 = pt(cx, cy, r, start + sweep)
    large = 1 if sweep > 180 else 0
    return f"M{x1:.2f} {y1:.2f} A{r} {r} 0 {large} 1 {x2:.2f} {y2:.2f}"

def spark(cx, cy, long, short, w, color):
    # Curved four-point sparkle. `short` sets how much the sides bulge.
    k = short
    p = (f"M{cx} {cy-long} "
         f"Q{cx+k} {cy-k} {cx+long} {cy} "
         f"Q{cx+k} {cy+k} {cx} {cy+long} "
         f"Q{cx-k} {cy+k} {cx-long} {cy} "
         f"Q{cx-k} {cy-k} {cx} {cy-long} Z")
    return f'<path d="{p}" fill="{color}" stroke="{color}" stroke-width="{w}" stroke-linejoin="round"/>'

def mark(cx, cy, r, ring_w, color, track_opacity, long, short, spark_w):
    # 270° gauge open at the bottom, ~70% filled.
    return f'''<path d="{arc(cx, cy, r, 135, 270)}" fill="none" stroke="{color}" stroke-opacity="{track_opacity}" stroke-width="{ring_w}" stroke-linecap="round"/>
  <path d="{arc(cx, cy, r, 135, 189)}" fill="none" stroke="{color}" stroke-width="{ring_w}" stroke-linecap="round"/>
  {spark(cx, cy, long, short, spark_w, color)}'''

# App icon (1024 canvas, Apple macOS grid: 824pt card inset 100).
icon = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#E8896A"/>
      <stop offset="1" stop-color="#B9573A"/>
    </linearGradient>
    <linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.22"/>
      <stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0"/>
    </linearGradient>
  </defs>
  <rect x="100" y="100" width="824" height="824" rx="185" fill="url(#bg)"/>
  <rect x="100" y="100" width="824" height="824" rx="185" fill="url(#gloss)"/>
  {mark(512, 530, 250, 64, "#FFF8F2", 0.28, 150, 26, 14)}
</svg>
'''
open("icon.svg", "w").write(icon)

# Menu bar / popover template mark (16pt, 100-unit viewBox).
logo = f'''<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 100 100">
  {mark(50, 52, 40, 12, "#000000", 0.35, 24, 5, 3)}
</svg>
'''
open("logo.svg", "w").write(logo)
