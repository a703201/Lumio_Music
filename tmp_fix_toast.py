import os

BASE = r"D:\Codes\Project\Lumio_Music\entry\src\main\ets"

# Files whose `toast(message: string)` must widen to ResourceStr (showToast accepts ResourceStr)
toast_files = [
    r"pages\SettingsCategory.ets",
    r"components\ControlAreaComponent.ets",
    r"components\AddToPlaylistSheet.ets",
    r"pages\AlbumDetail.ets",
    r"pages\ArtistDetail.ets",
    r"pages\Playlists.ets",
    r"components\SettingsSubPageBodies.ets",
]

def patch(path, repls):
    with open(path, 'r', encoding='utf-8') as f:
        s = f.read()
    for i, (old, new) in enumerate(repls):
        c = s.count(old)
        if c != 1:
            raise SystemExit(f"[{os.path.basename(path)} repl #{i}] expected 1 match, got {c}\n--- old ---\n{old!r}")
        s = s.replace(old, new, 1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(s)
    print("OK", os.path.basename(path))

total = 0
for rel in toast_files:
    p = os.path.join(BASE, rel)
    patch(p, [
        ("private toast(message: string): void",
         "private toast(message: ResourceStr): void"),
    ])
    total += 1

# SettingsCategory:243 computeCacheSize(): string catches and returns a Resource -> return '' (string)
sc = os.path.join(BASE, r"pages\SettingsCategory.ets")
patch(sc, [
    ("      return $r('app.string.cache_size');",
     "      return '';"),
])
print("OK SettingsCategory computeCacheSize catch")
print("applied toast widening to", total, "files")
