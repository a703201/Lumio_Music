/*
 * Copyright (c) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { util } from '@kit.ArkTS';
import { Logger } from '../utils/Logger';
import { LrcEntry, Word } from './LrcEntry';

/**
 * LRC format lyrics.
 */
const lrcLineRegex: RegExp = new RegExp('\\[\\d{2,}:\\d{2}((\\.|:)\\d{2,})\\]', 'g');
const lrcTimeRegex1: RegExp = new RegExp('\\[\\d{2,}', 'i');
const lrcTimeRegex2: RegExp = new RegExp('\\d{2}\\.\\d{2,}', 'i');

/**
 * KRC format lyrics.
 */
const krcLineRegex = new RegExp('\\[(\\d+),(\\d+)\\](.*)');
const krcWordRegex1 = new RegExp('<(\\d+),(\\d+),(\\d+)>([^<]*)', 'g');
const krcWordRegex2 = new RegExp('<(\\d+),(\\d+),(\\d+)>(.*)');


export async function getRawStringData(context: Context, rawFilePath: string): Promise<string> {
  try {
    let value = await context.resourceManager.getRawFileContent(rawFilePath);
    let textDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
    let stringData = textDecoder.decodeToString(value, { stream: false });
    return stringData;
  } catch (e) {
    Logger.error('LrcUtils', 'getRawStringData failed');
    throw new Error('getRawStringData failed');
  }
}

/**
 * Analysis of the lrc structure, similar to the following: [00:21.98] prime embryo outlines the blue and white pen dark to light.
 *
 * @param text
 * @returns
 * @param text
 * @returns
 */
export function parseLrcLyric(text: string): Array<LrcEntry> {
  if (!text) {
    return [];
  }
  let lyric: string[] = text.split('\n');
  // 按时间戳分组：同一个时间戳可能出现多行（原文 + 翻译）
  let groups: Map<number, string[]> = new Map();
  for (let i = 0; i < lyric.length; i++) {
    let lineTime = lyric[i].match(lrcLineRegex);
    let lineText = lyric[i].replace(lrcLineRegex, '');
    if (lineTime && lineText) {
      for (let j = 0; j < lineTime.length; j++) {
        let min = Number(String(lineTime[j].match(lrcTimeRegex1)).slice(1));
        let sec = Number.parseFloat(String(lineTime[j].match(lrcTimeRegex2)));
        let timeInSeconds = (min * 60 + sec) * 1000;
        let list = groups.get(timeInSeconds);
        if (!list) {
          list = [];
          groups.set(timeInSeconds, list);
        }
        list.push(lineText);
      }
    }
  }
  if (groups.size === 0) {
    Logger.error('Failed to parse the lyrics.');
    return [];
  }

  // 以整首歌的语种多数决判断「翻译」属于哪一语种：
  // 少数语种（平局时取 CJK）的那一类行即为翻译。这样对两类常见情形都正确：
  //  - 外语原曲 + 中文翻译：中文为少数 -> 作翻译
  //  - 中文原曲 + 英文翻译：英文为少数 -> 作翻译
  let cjkCount = 0;
  let otherCount = 0;
  groups.forEach((texts: string[]) => {
    for (let t = 0; t < texts.length; t++) {
      if (containsCjk(texts[t])) {
        cjkCount++;
      } else {
        otherCount++;
      }
    }
  });
  let translationIsCjk = cjkCount <= otherCount;

  let lrc = new Array<LrcEntry>();
  groups.forEach((texts: string[], time: number) => {
    let originals: string[] = [];
    let translations: string[] = [];
    for (let t = 0; t < texts.length; t++) {
      if (containsCjk(texts[t]) === translationIsCjk) {
        translations.push(texts[t]);
      } else {
        originals.push(texts[t]);
      }
    }
    if (originals.length === 0) {
      // 极端情况：所有行都是翻译语种，退化为首行作原文
      originals.push(texts[0]);
      translations = texts.slice(1);
    }
    lrc.push({
      lineStartTime: time,
      lineDuration: 0,
      lineWords: originals.join(' / '),
      words: [],
      translation: translations.length > 0 ? translations.join(' / ') : ''
    });
  });

  lrc.sort((a, b) => {
    return a.lineStartTime - b.lineStartTime;
  });
  for (let i = 0; i < lrc.length; i++) {
    if (i === lrc.length - 1) {
      lrc[i].lineDuration = Number.MAX_VALUE;
    } else {
      lrc[i].lineDuration = lrc[i + 1].lineStartTime - lrc[i].lineStartTime;
    }
  }
  return lrc;
}

/**
 * 判断文本是否含有 CJK / 日文假名等东亚字符（用于区分原文与翻译）。
 */
function containsCjk(s: string): boolean {
  for (let i = 0; i < s.length; i++) {
    let code = s.charCodeAt(i);
    if ((code >= 0x3040 && code <= 0x30FF) || // 平假名 / 片假名
      (code >= 0x3400 && code <= 0x4DBF) || // CJK 扩展 A
      (code >= 0x4E00 && code <= 0x9FFF) || // CJK 统一表意
      (code >= 0x3000 && code <= 0x303F) || // CJK 符号与标点
      (code >= 0xF900 && code <= 0xFAFF) || // CJK 兼容
      (code >= 0xFF00 && code <= 0xFFEF)) { // 全角字符
      return true;
    }
  }
  return false;
}

/**
 * Resolve the lyrics of Cool Dog, similar to the following structure.
 * [494, 228] < 0, 38, 0 > for < 38, 38, 0 > song < 76, 38, 0 >: < 114, 38, 0 > Zhou < 152, 38, 0 > Jie < 190, 38, 0 > L\n.
 *
 * @param lyricText
 * @returns
 */
export function parseKrcLyric(lyricText: string): LrcEntry[] {
  const lines: string[] = lyricText.split('\n');
  const lyricLines: LrcEntry[] = [];

  for (const line of lines) {
    const matches = line.match(krcLineRegex);
    if (matches) {
      const lineStartTime = Number.parseInt(matches[1]);
      const lineDuration = Number.parseInt(matches[2]);
      const lineWordsText = matches[3];
      const words: Word[] = [];
      const wordsMatches = lineWordsText.match(krcWordRegex1);
      let lineWords: string = '';
      if (wordsMatches) {
        for (const wordMatch of wordsMatches) {
          const wordMatches = wordMatch.match(krcWordRegex2);
          if (wordMatches) {
            const wordStartTime = Number.parseInt(wordMatches[1]);
            const wordDuration = Number.parseInt(wordMatches[2]);
            const wordText = wordMatches[4];
            lineWords += wordText;
            words.push({
              text: wordText,
              wordStartTime: wordStartTime,
              duration: wordDuration
            });
          }
        }
      }
      lyricLines.push({
        lineStartTime: lineStartTime,
        lineDuration: lineDuration,
        lineWords: lineWords,
        words: words
      });
    }
  }
  lyricLines.sort((a, b) => {
    return a.lineStartTime - b.lineStartTime;
  })
  return lyricLines;
}

/**
 * The angle is converted into radians.
 * Because the trigonometric function of Math needs to pass in the radian system instead of the angle value,
 * the angle needs to be converted into radians. Angle / 180 * π
 *
 * @param angle
 * @returns
 */
export function angleToRadian(angle: number): number {
  return angle * Math.PI / 180;
}