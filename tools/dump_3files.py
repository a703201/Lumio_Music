# -*- coding: utf-8 -*-
"""Dump raw embedded lyrics of the 3 user-referenced files for inspection."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe_lyrics as P

FILES = [
    r"D:\iCloudDrive\音乐\Walk off the Earth,D Smoke - Bet On Me.flac",
    r"D:\iCloudDrive\音乐\F1 The Album (Cinematic Edition)\01. Lose My Mind (feat. Doja Cat).m4a",
    r"D:\iCloudDrive\音乐\周深 - 人是_.flac",
]

for fp in FILES:
    ext = os.path.splitext(fp)[1].lower()
    print("=" * 70)
    print("FILE:", fp)
    print("EXISTS:", os.path.exists(fp))
    if not os.path.exists(fp):
        continue
    if ext == '.mp3':
        tags = P.probe_mp3(fp)
    elif ext == '.flac':
        tags = P.probe_flac(fp)
    elif ext in ('.m4a', '.mp4', '.aac'):
        tags = P.probe_mp4(fp)
    else:
        tags = []
    if not tags:
        print("  <no embedded lyric tags found>")
    for name, enc, text in tags:
        print(f"  [{name}] enc={enc} chars={len(text)}")
        print("  ---- RAW (first 1600 chars) ----")
        print(text[:1600])
        print("  ---- END RAW ----")
