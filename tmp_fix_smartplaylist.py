import os

p = r"D:\Codes\Project\Lumio_Music\entry\src\main\ets\services\SmartPlaylistService.ets"

with open(p, 'r', encoding='utf-8') as f:
    s = f.read()

old = "as unknown as string) ?? ''"
new = "as string) ?? ''"
c = s.count(old)
if c != 9:
    raise SystemExit(f"expected 9 matches for {old!r}, got {c}")
s = s.replace(old, new)

with open(p, 'w', encoding='utf-8') as f:
    f.write(s)
print("OK SmartPlaylistService.ets replaced", c, "as unknown -> as string")
