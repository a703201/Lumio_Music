# -*- coding: utf-8 -*-
"""Verify the fixed parseLrcLyric logic on the real Bet On Me text."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe_lyrics as P

FP = r"D:\iCloudDrive\音乐\Walk off the Earth,D Smoke - Bet On Me.flac"
raw = P.probe_flac(FP)[0][2]  # (name, enc, text)

import re
lrcLineRegex = re.compile(r'\[\d{2,}:\d{2}(?:\.|:)\d{2,}\]', re.I)
lrcTimeRegex1 = re.compile(r'\[\d{2,}', re.I)
lrcTimeRegex2 = re.compile(r'\d{2}\.\d{2,}', re.I)

CREDIT = ['作词','作曲','编曲','制作人','混音','母带','出品','发行','录音','企划','统筹',
          '原唱','翻唱','演唱','吉他','贝斯','鼓','钢琴','弦乐','和声','监制','文案','设计',
          '专辑','来源','校对','歌词','制作','编辑','提供','授权']

def is_credit(s):
    for k in CREDIT:
        if k in s:
            return True
    return False

def contains_cjk(s):
    for ch in s:
        c = ord(ch)
        if (0x3040 <= c <= 0x30FF) or (0x3400 <= c <= 0x4DBF) or (0x4E00 <= c <= 0x9FFF) \
           or (0x3000 <= c <= 0x303F) or (0xF900 <= c <= 0xFAFF) or (0xFF00 <= c <= 0xFFEF):
            return True
    return False

lyric = raw.split('\n')
groups = {}
for line in lyric:
    lineTime = lrcLineRegex.findall(line)
    lineText = lrcLineRegex.sub('', line)
    if lineTime and lineText:
        if is_credit(lineText):
            continue
        for lt in lineTime:
            m = lrcTimeRegex1.search(lt)
            s = lrcTimeRegex2.search(lt)
            minu = int(m.group(0)[1:]) if m else 0
            sec = float(s.group(0)) if s else 0.0
            t = (minu * 60 + sec) * 1000
            groups.setdefault(t, []).append(lineText)

cjk = sum(1 for ts, texts in groups.items() for x in texts if contains_cjk(x))
oth = sum(1 for ts, texts in groups.items() for x in texts if not contains_cjk(x))
translationIsCjk = cjk <= oth
print(f"cjk={cjk} other={oth} translationIsCjk={translationIsCjk}")
print("=> translation language:", "CJK(should be ZH)" if translationIsCjk else "non-CJK(should be EN)")
print()
for ts in sorted(groups)[:6]:
    texts = groups[ts]
    orig = [x for x in texts if contains_cjk(x) != translationIsCjk]
    tran = [x for x in texts if contains_cjk(x) == translationIsCjk]
    print(f"[{ts/1000:.2f}s] ORIG={orig} | TRANS={tran}")
