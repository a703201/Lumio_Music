/*
 * Copyright 2026 何宇翔
 *
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

/**
 * libnative_module.so — C++ NAPI 原生模块类型声明
 *
 * 向上层 ArkTS 暴露音频元数据解析函数。
 * 配合 `NativeModule.ets` 的单例封装使用，提供 IDE 类型提示与编译期契约校验。
 *
 * @module libnative_module
 * @see NativeModule.ets
 */

interface AudioMetadata {
  /** 歌曲标题（UTF-8） */
  title: string;
  /** 艺术家名（UTF-8），未解析到则为 "未知艺术家" */
  artist: string;
  /** 专辑名（UTF-8），未解析到则为 "未知专辑" */
  album: string;
  /** 年份（如 "2024"），未解析到则为空串 */
  year: string;
  /** 时长（毫秒） */
  duration: number;
  /** 采样率（Hz，如 44100） */
  sampleRate: number;
  /** 声道数（1=单声道，2=立体声） */
  channels: number;
  /** 位深（FLAC/WAV/ALAC 真实值；MP3/AAC 等损耗编码为 0 表示不适用） */
  bitDepth: number;
  /** 容器/编码：flac / mp3 / m4a / alac / wav，用于无损/Hi-Res 判定 */
  codec: string;
}

/** 解析本地音频文件的元数据（标题/艺术家/专辑/年份/时长/采样率/声道） */
export const parseAudioMetadata: (filePath: string) => AudioMetadata;
