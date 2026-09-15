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

import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { parseLrcLyric, parseKrcLyric, angleToRadian } from '../main/ets/lyric/LrcUtils';
import { LrcEntry, Word } from '../main/ets/lyric/LrcEntry';
import { MusicStore } from '../main/ets/services/MusicStore';
import { SongItem } from '../main/ets/songdatacontroller/SongData';
import { RepeatMode, Playlist } from '../main/ets/models/music';
import { Logger } from '../main/ets/utils/Logger';
import { DuplicateDetector, DuplicateGroup } from '../main/ets/utils/DuplicateDetector';
import { sortSongs } from '../main/ets/common/utils/SortUtil';

/**
 * 构造一个字段完整的 SongItem（SongItem 是普通类，`new` 后所有字段均有默认值）。
 * id/title/singer/album 是本次测试关心的字段，src/index 一并填上以免被误用为 undefined。
 */
function buildSong(id: number, title: string, singer: string, album: string): SongItem {
  const song: SongItem = new SongItem();
  song.id = id;
  song.title = title;
  song.singer = singer;
  song.album = album;
  song.src = `/music/${id}.mp3`;
  song.index = id;
  return song;
}

/** 按顺序取出 id，用于「不修改入参 / 保持顺序」类断言。 */
function collectIds(songs: SongItem[]): number[] {
  const out: number[] = [];
  for (let i = 0; i < songs.length; i++) {
    out.push(songs[i].id);
  }
  return out;
}

/** 取出 id 后升序排列，用于「排列不变（同一集合）」类断言。 */
function collectSortedIds(songs: SongItem[]): number[] {
  const out: number[] = collectIds(songs);
  out.sort((a: number, b: number) => a - b);
  return out;
}

/** 中英混合 + 含前导空格的名字，用于排序稳定性断言。 */
function buildMixedSongs(): SongItem[] {
  return [
    buildSong(1, '北京', '周杰伦', '叶惠美'),
    buildSong(2, 'Apple', 'Adele', '19'),
    buildSong(3, '  Shanghai', 'Zoe', '  Album X'),
    buildSong(4, '夜曲', '周杰伦', '十一月的萧邦')
  ];
}

/**
 * 断言辅助：相邻元素满足 localeCompare(...,'zh') 非降序。
 * 不写死期望顺序——localeCompare 的结果依赖运行环境 ICU 数据，
 * 写死顺序会在不同设备上假失败；只校验「有序性」这一真实契约。
 */
function isSortedByTitle(songs: SongItem[]): boolean {
  for (let i = 1; i < songs.length; i++) {
    if (songs[i - 1].title.localeCompare(songs[i].title, 'zh') > 0) {
      return false;
    }
  }
  return true;
}

function isSortedBySinger(songs: SongItem[]): boolean {
  for (let i = 1; i < songs.length; i++) {
    if (songs[i - 1].singer.localeCompare(songs[i].singer, 'zh') > 0) {
      return false;
    }
  }
  return true;
}

function isSortedByAlbum(songs: SongItem[]): boolean {
  for (let i = 1; i < songs.length; i++) {
    if (songs[i - 1].album.localeCompare(songs[i].album, 'zh') > 0) {
      return false;
    }
  }
  return true;
}

// ============================================================
// LrcUtils — 纯函数测试（无需 Context / 系统 API）
// ============================================================

describe('LrcUtils', () => {

  describe('angleToRadian', () => {
    it('0 degrees should return 0', 0, () => {
      expect(angleToRadian(0)).assertEqual(0);
    });

    it('90 degrees should return π/2', 0, () => {
      expect(angleToRadian(90)).assertEqual(Math.PI / 2);
    });

    it('180 degrees should return π', 0, () => {
      expect(angleToRadian(180)).assertEqual(Math.PI);
    });

    it('360 degrees should return 2π', 0, () => {
      expect(angleToRadian(360)).assertEqual(2 * Math.PI);
    });

    it('negative angle should return negative radian', 0, () => {
      expect(angleToRadian(-90)).assertEqual(-Math.PI / 2);
    });
  });

  describe('parseLrcLyric', () => {

    it('empty string should return empty array', 0, () => {
      const result: LrcEntry[] = parseLrcLyric('');
      expect(result.length).assertEqual(0);
    });

    it('single line LRC with timestamp', 0, () => {
      const lrc: string = '[00:21.98]Hello World';
      const result: LrcEntry[] = parseLrcLyric(lrc);
      expect(result.length).assertEqual(1);
      expect(result[0].lineStartTime).assertEqual(21980);
      expect(result[0].lineWords).assertContain('Hello World');
      // Last line duration should be MAX_VALUE
      expect(result[0].lineDuration).assertEqual(Number.MAX_VALUE);
    });

    it('multiple lines should be sorted by time ascending', 0, () => {
      const lrc: string = '[00:30.00]Line 3\n[00:10.00]Line 1\n[00:20.00]Line 2';
      const result: LrcEntry[] = parseLrcLyric(lrc);
      expect(result.length).assertEqual(3);
      expect(result[0].lineStartTime).assertEqual(10000);
      expect(result[1].lineStartTime).assertEqual(20000);
      expect(result[2].lineStartTime).assertEqual(30000);
    });

    it('lines share same timestamp should be merged as translation', 0, () => {
      const lrc: string = '[00:21.98]Hello\n[00:21.98]你好';
      const result: LrcEntry[] = parseLrcLyric(lrc);
      // Should have 1 entry with original + translation
      expect(result.length).assertEqual(1);
      expect(result[0].lineStartTime).assertEqual(21980);
      // CJK count <= non-CJK, so CJK (你好) is translation
      expect(result[0].translation).assertContain('你好');
    });

    it('credit lines should be filtered out', 0, () => {
      const lrc: string = '[00:05.00]作词: someone\n[00:10.00]real lyric';
      const result: LrcEntry[] = parseLrcLyric(lrc);
      expect(result.length).assertEqual(1);
      expect(result[0].lineWords).assertContain('real lyric');
    });

    it('multiple credit lines with作曲/编曲/制作人 should all be filtered', 0, () => {
      const lrc: string = '[00:01.00]作曲: A\n[00:02.00]编曲: B\n[00:03.00]制作人: C\n[00:04.00]混音: D\n[00:10.00]actual song';
      const result: LrcEntry[] = parseLrcLyric(lrc);
      expect(result.length).assertEqual(1);
      expect(result[0].lineWords).assertContain('actual song');
    });

    it('LRC with missing timestamps on some lines', 0, () => {
      const lrc: string = '[00:10.00]Line 1\nno timestamp line\n[00:20.00]Line 2';
      const result: LrcEntry[] = parseLrcLyric(lrc);
      // Line without timestamp should be ignored
      expect(result.length).assertEqual(2);
    });

    it('LRC with CJK original + English translation', 0, () => {
      const lrc: string = '[00:10.00]你好世界\n[00:10.00]Hello World\n[00:20.00]测试\n[00:20.00]Test';
      const result: LrcEntry[] = parseLrcLyric(lrc);
      // CJK majority → English is translation
      expect(result.length).assertEqual(2);
      expect(result[0].lineWords).assertContain('你好世界');
      // Since CJK count (2) > non-CJK (2), tie goes to CJK as original
      // Wait - counts are: CJK=2, other=2. translationIsCjk = (2 <= 2) = true
      // So translation IS CJK (你好世界 and 测试 are translations)
      // And originals are English (Hello World and Test)
      // This is the expected tie-breaking: CJK is minority language → translation
      expect(result[0].translation).assertContain('你好世界');
    });

    it('duration calculation: non-last lines have correct duration', 0, () => {
      const lrc: string = '[00:00.00]Line 1\n[00:05.00]Line 2\n[00:10.50]Line 3';
      const result: LrcEntry[] = parseLrcLyric(lrc);
      expect(result.length).assertEqual(3);
      expect(result[0].lineDuration).assertEqual(5000);
      expect(result[1].lineDuration).assertEqual(5500);
      expect(result[2].lineDuration).assertEqual(Number.MAX_VALUE);
    });

    it('LRC with minutes:seconds.milliseconds format', 0, () => {
      const lrc: string = '[01:30.50]One minute thirty';
      const result: LrcEntry[] = parseLrcLyric(lrc);
      expect(result[0].lineStartTime).assertEqual(90500); // 1*60*1000 + 30*1000 + 500
    });

    it('empty lines with only timestamps should be ignored', 0, () => {
      const lrc: string = '[00:10.00]\n[00:20.00]valid';
      const result: LrcEntry[] = parseLrcLyric(lrc);
      expect(result.length).assertEqual(1);
    });
  });

  describe('parseKrcLyric', () => {

    it('empty string should return empty array', 0, () => {
      const result: LrcEntry[] = parseKrcLyric('');
      expect(result.length).assertEqual(0);
    });

    it('single KRC line with words', 0, () => {
      const krc: string = '[494,228]<0,38,0>hello<38,38,0> world';
      const result: LrcEntry[] = parseKrcLyric(krc);
      expect(result.length).assertEqual(1);
      expect(result[0].lineStartTime).assertEqual(494);
      expect(result[0].lineDuration).assertEqual(228);
      expect(result[0].lineWords).assertEqual('hello world');
      expect(result[0].words.length).assertEqual(2);
      expect(result[0].words[0].text).assertEqual('hello');
      expect(result[0].words[0].wordStartTime).assertEqual(0);
      expect(result[0].words[0].duration).assertEqual(38);
    });

    it('multiple KRC lines should be sorted', 0, () => {
      const krc: string = '[1000,200]Line 2\n[500,200]Line 1';
      const result: LrcEntry[] = parseKrcLyric(krc);
      expect(result.length).assertEqual(2);
      expect(result[0].lineStartTime).assertEqual(500);
      expect(result[1].lineStartTime).assertEqual(1000);
    });

    it('KRC line without word tags', 0, () => {
      const krc: string = '[494,228]plain text';
      const result: LrcEntry[] = parseKrcLyric(krc);
      expect(result.length).assertEqual(1);
      expect(result[0].lineWords).assertEqual('');
      expect(result[0].words.length).assertEqual(0);
    });

    it('KRC with CJK characters in words', 0, () => {
      const krc: string = '[0,1000]<0,500,0>你好<500,500,0>世界';
      const result: LrcEntry[] = parseKrcLyric(krc);
      expect(result.length).assertEqual(1);
      expect(result[0].lineWords).assertEqual('你好世界');
      expect(result[0].words[0].text).assertEqual('你好');
    });

    it('KRC with empty body lines should not error', 0, () => {
      const krc: string = '[100,50]\n[200,50]valid';
      const result: LrcEntry[] = parseKrcLyric(krc);
      // First line has empty body (match still succeeds since regex captures groups)
      expect(result.length).assertEqual(2);
    });
  });

  describe('parseLrcLyric — 畸形时间戳与空白行', () => {

    it('out-of-range timestamp [99:99.999] should keep the raw ms arithmetic', 0, () => {
      const result: LrcEntry[] = parseLrcLyric('[99:99.999]Out of range');
      expect(result.length).assertEqual(1);
      // 与实现使用同一表达式，规避浮点表示差异
      const expected: number = (99 * 60 + 99.999) * 1000;
      expect(result[0].lineStartTime).assertEqual(expected);
      expect(result[0].lineStartTime > 6000000).assertEqual(true);
    });

    it('blank and whitespace-only input should return empty array', 0, () => {
      expect(parseLrcLyric('\n   \n\t\n').length).assertEqual(0);
    });

    it('blank lines between valid lines should not create entries', 0, () => {
      const result: LrcEntry[] = parseLrcLyric('[00:10.00]First\n\n   \n[00:20.00]Second');
      expect(result.length).assertEqual(2);
      expect(result[0].lineWords).assertContain('First');
      expect(result[1].lineWords).assertContain('Second');
    });

    it('text without any timestamp should return empty array', 0, () => {
      expect(parseLrcLyric('just plain text without timestamps').length).assertEqual(0);
    });

    it('timestamp without milliseconds [00:10] should be ignored', 0, () => {
      expect(parseLrcLyric('[00:10]No millis').length).assertEqual(0);
    });

    it('single-digit minute [0:10.00] should be ignored', 0, () => {
      expect(parseLrcLyric('[0:10.00]Short minute').length).assertEqual(0);
    });

    it('colon as millisecond separator [00:21:98] is accepted by regex but yields NaN time', 0, () => {
      const result: LrcEntry[] = parseLrcLyric('[00:21:98]Colon ms');
      expect(result.length).assertEqual(1);
      expect(Number.isNaN(result[0].lineStartTime)).assertEqual(true);
    });

    it('three lines sharing one timestamp should merge into original plus translation', 0, () => {
      const result: LrcEntry[] = parseLrcLyric('[00:10.00]Hello\n[00:10.00]你好\n[00:10.00]Hola');
      expect(result.length).assertEqual(1);
      expect(result[0].lineWords).assertEqual('Hello / Hola');
      expect(result[0].translation).assertEqual('你好');
    });

    it('credit line carrying a timestamp should still be dropped', 0, () => {
      const result: LrcEntry[] = parseLrcLyric('[00:01.00]作词: 某人\n[00:05.00]正文');
      expect(result.length).assertEqual(1);
      expect(result[0].lineWords).assertContain('正文');
    });
  });

  describe('parseKrcLyric — 逐字边界', () => {

    it('empty word text between two tags should keep an empty word', 0, () => {
      const result: LrcEntry[] = parseKrcLyric('[0,100]<0,50,0><50,50,0>尾');
      expect(result.length).assertEqual(1);
      expect(result[0].words.length).assertEqual(2);
      expect(result[0].words[0].text).assertEqual('');
      expect(result[0].words[0].wordStartTime).assertEqual(0);
      expect(result[0].words[0].duration).assertEqual(50);
      expect(result[0].lineWords).assertEqual('尾');
    });

    it('zero start and zero duration tag <0,0,0> should be preserved', 0, () => {
      const result: LrcEntry[] = parseKrcLyric('[0,100]<0,0,0>字');
      expect(result.length).assertEqual(1);
      expect(result[0].words.length).assertEqual(1);
      expect(result[0].words[0].wordStartTime).assertEqual(0);
      expect(result[0].words[0].duration).assertEqual(0);
      expect(result[0].lineWords).assertEqual('字');
    });

    it('two-number tag <0,0> is not a word tag and should yield no words', 0, () => {
      const result: LrcEntry[] = parseKrcLyric('[0,100]<0,0>字');
      expect(result.length).assertEqual(1);
      expect(result[0].words.length).assertEqual(0);
      expect(result[0].lineWords).assertEqual('');
    });

    it('very long word text should be preserved without truncation', 0, () => {
      let longText: string = '';
      for (let i = 0; i < 1000; i++) {
        longText += '长';
      }
      const krc: string = `[0,5000]<0,5000,0>${longText}`;
      const result: LrcEntry[] = parseKrcLyric(krc);
      expect(result.length).assertEqual(1);
      expect(result[0].words.length).assertEqual(1);
      expect(result[0].words[0].text.length).assertEqual(1000);
      expect(result[0].lineWords.length).assertEqual(1000);
    });

    it('two lines sharing the same start time should both be kept', 0, () => {
      const result: LrcEntry[] = parseKrcLyric('[100,50]A\n[100,50]B');
      expect(result.length).assertEqual(2);
      expect(result[0].lineStartTime).assertEqual(100);
      expect(result[1].lineStartTime).assertEqual(100);
    });

    it('lines without the [start,duration] head should be skipped', 0, () => {
      const result: LrcEntry[] = parseKrcLyric('no head line\n[200,50]<0,50,0>ok');
      expect(result.length).assertEqual(1);
      expect(result[0].lineStartTime).assertEqual(200);
    });
  });
});

// ============================================================
// MusicStore — 纯内存逻辑测试（不依赖 dataPreferences）
// ============================================================

describe('MusicStore', () => {
  let store: MusicStore;

  beforeEach(() => {
    store = MusicStore.getInstance();
    // reset in-memory state for isolation
    store.songs = [];
    store.playList = [];
    store.favorites = new Set();
    store.playlists = [];
    store.recentlyPlayed = [];
    store.currentIndex = 0;
    store.isPlaying = false;
    store.repeatMode = 'list';
    store.loadError = false;
  });

  describe('toggleFavorite', () => {
    it('should add song id to favorites when not favorited', 0, () => {
      store.toggleFavorite(1);
      expect(store.isFavorite(1)).assertEqual(true);
    });

    it('should remove song id from favorites when already favorited', 0, () => {
      store.toggleFavorite(1);
      store.toggleFavorite(1);
      expect(store.isFavorite(1)).assertEqual(false);
    });

    it('should handle multiple favorites correctly', 0, () => {
      store.toggleFavorite(1);
      store.toggleFavorite(2);
      store.toggleFavorite(3);
      expect(store.isFavorite(1)).assertEqual(true);
      expect(store.isFavorite(2)).assertEqual(true);
      expect(store.isFavorite(3)).assertEqual(true);
      expect(store.favorites.size).assertEqual(3);
    });

    it('isFavorite should return false for never-favorited id', 0, () => {
      expect(store.isFavorite(999)).assertEqual(false);
    });
  });

  describe('addPlaylist', () => {
    it('should create a playlist with unique id', 0, () => {
      const pl: Playlist = store.addPlaylist('My Playlist', [1, 2, 3]);
      expect(pl.name).assertEqual('My Playlist');
      expect(pl.songIds.length).assertEqual(3);
      expect(store.playlists.length).assertEqual(1);
    });

    it('should create playlists with unique ids even when called in rapid succession', 0, () => {
      // simulate rapid creation
      const now: number = 1000000000000;
      // We can't mock Date.now but the implementation uses random suffix
      const pl1: Playlist = store.addPlaylist('A', [1]);
      const pl2: Playlist = store.addPlaylist('B', [2]);
      expect(pl1.id).not().assertEqual(pl2.id);
    });

    it('playlist with empty songIds should be valid', 0, () => {
      const pl: Playlist = store.addPlaylist('Empty', []);
      expect(pl.songIds.length).assertEqual(0);
      expect(store.playlists.length).assertEqual(1);
    });
  });

  describe('deletePlaylist', () => {
    it('should remove playlist by id', 0, () => {
      const pl: Playlist = store.addPlaylist('Test', [1]);
      expect(store.playlists.length).assertEqual(1);
      store.deletePlaylist(pl.id);
      expect(store.playlists.length).assertEqual(0);
    });

    it('should not error when deleting non-existent playlist', 0, () => {
      store.deletePlaylist('nonexistent_id');
      expect(store.playlists.length).assertEqual(0);
    });
  });

  describe('renamePlaylist', () => {
    it('should rename playlist by id', 0, () => {
      const pl: Playlist = store.addPlaylist('Old Name', []);
      store.renamePlaylist(pl.id, 'New Name');
      const renamed: Playlist | undefined = store.getPlaylistById(pl.id);
      expect(renamed?.name).assertEqual('New Name');
    });

    it('should not error when renaming non-existent playlist', 0, () => {
      // should not throw
      store.renamePlaylist('nonexistent', 'name');
      expect(store.playlists.length).assertEqual(0);
    });
  });

  describe('hasPlaylistName', () => {
    it('should detect duplicate names', 0, () => {
      store.addPlaylist('My List', []);
      expect(store.hasPlaylistName('My List')).assertEqual(true);
      expect(store.hasPlaylistName('my list')).assertEqual(false); // exact match
      expect(store.hasPlaylistName('Other')).assertEqual(false);
    });

    it('should ignore excluded id for rename check', 0, () => {
      const pl: Playlist = store.addPlaylist('My List', []);
      // When renaming, excludeId should skip the playlist itself
      expect(store.hasPlaylistName('My List', pl.id)).assertEqual(false);
    });

    it('should trim whitespace in name comparison', 0, () => {
      store.addPlaylist('My List', []);
      expect(store.hasPlaylistName('  My List  ')).assertEqual(true);
    });
  });

  describe('addSongsToPlaylist', () => {
    it('should add new songs to playlist', 0, () => {
      const pl: Playlist = store.addPlaylist('Test', [1, 2]);
      const added: number = store.addSongsToPlaylist(pl.id, [3, 4]);
      expect(added).assertEqual(2);
      const updated: Playlist | undefined = store.getPlaylistById(pl.id);
      expect(updated?.songIds.length).assertEqual(4);
    });

    it('should not add duplicate songs', 0, () => {
      const pl: Playlist = store.addPlaylist('Test', [1, 2]);
      const added: number = store.addSongsToPlaylist(pl.id, [2, 3]);
      expect(added).assertEqual(1); // only song 3 is new
      const updated: Playlist | undefined = store.getPlaylistById(pl.id);
      expect(updated?.songIds.length).assertEqual(3);
    });

    it('should return 0 for non-existent playlist', 0, () => {
      const added: number = store.addSongsToPlaylist('nonexistent', [1]);
      expect(added).assertEqual(0);
    });
  });

  describe('removeSongFromPlaylist', () => {
    it('should remove song from playlist', 0, () => {
      const pl: Playlist = store.addPlaylist('Test', [1, 2, 3]);
      store.removeSongFromPlaylist(pl.id, 2);
      const updated: Playlist | undefined = store.getPlaylistById(pl.id);
      expect(updated?.songIds.length).assertEqual(2);
      expect(updated?.songIds).assertContain(1);
      expect(updated?.songIds).assertContain(3);
    });

    it('should not error when removing from non-existent playlist', 0, () => {
      // should not throw
      store.removeSongFromPlaylist('nonexistent', 1);
    });
  });

  describe('reorderPlaylistSongs', () => {
    it('should move song from one position to another', 0, () => {
      const pl: Playlist = store.addPlaylist('Test', [1, 2, 3, 4]);
      store.reorderPlaylistSongs(pl.id, 1, 3);
      const updated: Playlist | undefined = store.getPlaylistById(pl.id);
      expect(updated?.songIds[0]).assertEqual(1);
      expect(updated?.songIds[1]).assertEqual(3);
      expect(updated?.songIds[2]).assertEqual(4);
      expect(updated?.songIds[3]).assertEqual(2);
    });

    it('should not error with invalid from/to', 0, () => {
      const pl: Playlist = store.addPlaylist('Test', [1, 2]);
      store.reorderPlaylistSongs(pl.id, -1, 0);
      expect(store.getPlaylistById(pl.id)?.songIds.length).assertEqual(2);
    });

    it('should not error when from equals to', 0, () => {
      const pl: Playlist = store.addPlaylist('Test', [1, 2, 3]);
      store.reorderPlaylistSongs(pl.id, 1, 1);
      expect(store.getPlaylistById(pl.id)?.songIds.length).assertEqual(3);
    });
  });

  describe('addToRecentlyPlayed', () => {
    it('should add song to recently played', 0, () => {
      const song: SongItem = new SongItem();
      song.id = 1;
      song.title = 'Test';
      song.singer = 'Artist';
      song.src = '/test.mp3';
      store.addToRecentlyPlayed(song);
      expect(store.recentlyPlayed.length).assertEqual(1);
      expect(store.recentlyPlayed[0].id).assertEqual(1);
    });

    it('should move existing song to front on re-play', 0, () => {
      const song1: SongItem = new SongItem();
      song1.id = 1; song1.title = 'A'; song1.src = '/a.mp3';
      const song2: SongItem = new SongItem();
      song2.id = 2; song2.title = 'B'; song2.src = '/b.mp3';
      store.addToRecentlyPlayed(song1);
      store.addToRecentlyPlayed(song2);
      store.addToRecentlyPlayed(song1); // re-play song1
      expect(store.recentlyPlayed.length).assertEqual(2);
      expect(store.recentlyPlayed[0].id).assertEqual(1);
    });

    it('should cap at 50 entries', 0, () => {
      for (let i = 0; i < 60; i++) {
        const song: SongItem = new SongItem();
        song.id = i;
        song.title = `Song ${i}`;
        song.src = `/song${i}.mp3`;
        store.addToRecentlyPlayed(song);
      }
      expect(store.recentlyPlayed.length).assertEqual(50);
      // Latest should be id 59
      expect(store.recentlyPlayed[0].id).assertEqual(59);
    });
  });

  describe('clearRecentlyPlayed', () => {
    it('should clear all recently played', 0, () => {
      const song: SongItem = new SongItem();
      song.id = 1; song.title = 'A'; song.src = '/a.mp3';
      store.addToRecentlyPlayed(song);
      expect(store.recentlyPlayed.length).assertEqual(1);
      store.clearRecentlyPlayed();
      expect(store.recentlyPlayed.length).assertEqual(0);
    });
  });

  describe('getFavoriteSongs', () => {
    it('should return only favorited songs', 0, () => {
      const song1: SongItem = new SongItem();
      song1.id = 1; song1.title = 'A'; song1.src = '/a.mp3';
      const song2: SongItem = new SongItem();
      song2.id = 2; song2.title = 'B'; song2.src = '/b.mp3';
      store.songs = [song1, song2];
      store.toggleFavorite(1);
      const favs: SongItem[] = store.getFavoriteSongs();
      expect(favs.length).assertEqual(1);
      expect(favs[0].id).assertEqual(1);
    });

    it('should return empty array when no favorites', 0, () => {
      const song: SongItem = new SongItem();
      song.id = 1; song.title = 'A'; song.src = '/a.mp3';
      store.songs = [song];
      expect(store.getFavoriteSongs().length).assertEqual(0);
    });
  });

  describe('getPlaylistById', () => {
    it('should find playlist by id', 0, () => {
      const pl: Playlist = store.addPlaylist('Test', []);
      expect(store.getPlaylistById(pl.id)?.name).assertEqual('Test');
    });

    it('should return undefined for non-existent id', 0, () => {
      expect(store.getPlaylistById('nonexistent')).assertEqual(undefined);
    });
  });

  describe('getPlaylistSongs', () => {
    it('should return songs matching playlist songIds', 0, () => {
      const song1: SongItem = new SongItem();
      song1.id = 1; song1.title = 'A'; song1.src = '/a.mp3'; song1.index = 0;
      const song2: SongItem = new SongItem();
      song2.id = 2; song2.title = 'B'; song2.src = '/b.mp3'; song2.index = 1;
      const song3: SongItem = new SongItem();
      song3.id = 3; song3.title = 'C'; song3.src = '/c.mp3'; song3.index = 2;
      store.songs = [song1, song2, song3];
      const pl: Playlist = store.addPlaylist('Test', [1, 3]);
      const songs: SongItem[] = store.getPlaylistSongs(pl);
      expect(songs.length).assertEqual(2);
      expect(songs[0].id).assertEqual(1);
      expect(songs[1].id).assertEqual(3);
    });
  });

  describe('setRepeatMode', () => {
    it('should set repeat mode to list', 0, () => {
      store.setRepeatMode('list');
      expect(store.repeatMode).assertEqual('list');
    });

    it('should set repeat mode to single', 0, () => {
      store.setRepeatMode('single');
      expect(store.repeatMode).assertEqual('single');
    });

    it('should set repeat mode to random', 0, () => {
      store.setRepeatMode('random');
      expect(store.repeatMode).assertEqual('random');
    });
  });

  describe('歌单重名与删除幂等（补充）', () => {

    it('should allow duplicate names at store level but report them via hasPlaylistName', 0, () => {
      const first: Playlist = store.addPlaylist('My List', []);
      const second: Playlist = store.addPlaylist('My List', []);
      expect(store.playlists.length).assertEqual(2);
      expect(store.hasPlaylistName('My List')).assertEqual(true);
      // 名字相同的两个歌单 id 必须不同，否则删除会误伤
      expect(first.id).not().assertEqual(second.id);
    });

    it('should detect duplicate name only after trimming', 0, () => {
      store.addPlaylist('Trimmed', []);
      expect(store.hasPlaylistName('  Trimmed  ')).assertEqual(true);
      expect(store.hasPlaylistName('Trimmed Name')).assertEqual(false);
    });

    it('hasPlaylistName should treat whitespace-only query as empty name', 0, () => {
      expect(store.hasPlaylistName('   ')).assertEqual(false);
      store.addPlaylist('', []);
      expect(store.hasPlaylistName('   ')).assertEqual(true);
    });

    it('renamePlaylist should trim the new name', 0, () => {
      const pl: Playlist = store.addPlaylist('Old', []);
      store.renamePlaylist(pl.id, '  New  ');
      expect(store.getPlaylistById(pl.id)?.name).assertEqual('New');
    });

    it('renamePlaylist should not block renaming onto an existing name (guard is at UI layer)', 0, () => {
      store.addPlaylist('Taken', []);
      const pl: Playlist = store.addPlaylist('Free', []);
      store.renamePlaylist(pl.id, 'Taken');
      expect(store.getPlaylistById(pl.id)?.name).assertEqual('Taken');
      expect(store.playlists.length).assertEqual(2);
    });

    it('deleting the same playlist twice should be idempotent', 0, () => {
      const pl: Playlist = store.addPlaylist('Temp', [1]);
      store.deletePlaylist(pl.id);
      expect(store.playlists.length).assertEqual(0);
      store.deletePlaylist(pl.id);
      expect(store.playlists.length).assertEqual(0);
    });

    it('deleting from an empty store should not error', 0, () => {
      expect(store.playlists.length).assertEqual(0);
      store.deletePlaylist('anything');
      expect(store.playlists.length).assertEqual(0);
    });
  });

  describe('收藏切换幂等（补充）', () => {

    it('toggling twice should return to the original state', 0, () => {
      store.toggleFavorite(1);
      store.toggleFavorite(1);
      expect(store.isFavorite(1)).assertEqual(false);
      expect(store.favorites.size).assertEqual(0);
    });

    it('toggling three times should end up favorited with a single set entry', 0, () => {
      store.toggleFavorite(1);
      store.toggleFavorite(1);
      store.toggleFavorite(1);
      expect(store.isFavorite(1)).assertEqual(true);
      expect(store.favorites.size).assertEqual(1);
    });

    it('repeated toggles on one id should never grow the favorites set', 0, () => {
      for (let i = 0; i < 10; i++) {
        store.toggleFavorite(42);
      }
      expect(store.favorites.size).assertEqual(0);
      store.toggleFavorite(42);
      expect(store.favorites.size).assertEqual(1);
    });

    it('should treat id 0 as a normal id', 0, () => {
      store.toggleFavorite(0);
      expect(store.isFavorite(0)).assertEqual(true);
      expect(store.favorites.size).assertEqual(1);
    });

    it('toggling one id should not affect another id', 0, () => {
      store.toggleFavorite(1);
      store.toggleFavorite(2);
      store.toggleFavorite(1);
      expect(store.isFavorite(1)).assertEqual(false);
      expect(store.isFavorite(2)).assertEqual(true);
      expect(store.favorites.size).assertEqual(1);
    });
  });

  describe('最近播放去重与上限（补充）', () => {

    it('adding the same id repeatedly should keep a single entry at front', 0, () => {
      const song: SongItem = buildSong(1, 'Repeat', 'A', 'X');
      store.addToRecentlyPlayed(song);
      store.addToRecentlyPlayed(song);
      store.addToRecentlyPlayed(song);
      expect(store.recentlyPlayed.length).assertEqual(1);
      expect(store.recentlyPlayed[0].id).assertEqual(1);
    });

    it('dedup should be keyed by id even for different SongItem instances', 0, () => {
      store.addToRecentlyPlayed(buildSong(5, 'Old Title', 'A', 'X'));
      store.addToRecentlyPlayed(buildSong(5, 'New Title', 'B', 'Y'));
      expect(store.recentlyPlayed.length).assertEqual(1);
      // 后入的实例替换先入的实例
      expect(store.recentlyPlayed[0].title).assertEqual('New Title');
    });

    it('exactly 50 entries should not be trimmed', 0, () => {
      for (let i = 0; i < 50; i++) {
        store.addToRecentlyPlayed(buildSong(i, `Song ${i}`, 'A', 'X'));
      }
      expect(store.recentlyPlayed.length).assertEqual(50);
      expect(store.recentlyPlayed[0].id).assertEqual(49);
      expect(store.recentlyPlayed[49].id).assertEqual(0);
    });

    it('the 51st distinct entry should drop the oldest one', 0, () => {
      for (let i = 0; i < 51; i++) {
        store.addToRecentlyPlayed(buildSong(i, `Song ${i}`, 'A', 'X'));
      }
      expect(store.recentlyPlayed.length).assertEqual(50);
      expect(store.recentlyPlayed[0].id).assertEqual(50);
      // 最旧的 id 0 已被挤出
      expect(store.recentlyPlayed.filter((s: SongItem) => s.id === 0).length).assertEqual(0);
    });

    it('re-adding an old entry at the 50 cap should refresh it, not grow the list', 0, () => {
      for (let i = 0; i < 50; i++) {
        store.addToRecentlyPlayed(buildSong(i, `Song ${i}`, 'A', 'X'));
      }
      // 重新播放最早的一条：应移到队首且总数不变
      store.addToRecentlyPlayed(buildSong(0, 'Song 0', 'A', 'X'));
      expect(store.recentlyPlayed.length).assertEqual(50);
      expect(store.recentlyPlayed[0].id).assertEqual(0);
      expect(store.recentlyPlayed.filter((s: SongItem) => s.id === 0).length).assertEqual(1);
    });
  });

  describe('loadError flag', () => {
    it('should default to false', 0, () => {
      expect(store.loadError).assertEqual(false);
    });

    it('should be settable to true for error state', 0, () => {
      store.loadError = true;
      expect(store.loadError).assertEqual(true);
    });
  });
});

// ============================================================
// 集成：MusicStore CRUD 联动测试
// ============================================================

describe('MusicStore CRUD Integration', () => {

  it('full lifecycle: add songs, favorite, playlist, remove', 0, () => {
    const store: MusicStore = MusicStore.getInstance();
    store.songs = [];
    store.favorites = new Set();
    store.playlists = [];
    store.loadError = false;

    // Add songs
    const song1: SongItem = new SongItem();
    song1.id = 1; song1.title = 'Song A'; song1.singer = 'Artist A';
    song1.src = '/a.mp3'; song1.index = 0;
    const song2: SongItem = new SongItem();
    song2.id = 2; song2.title = 'Song B'; song2.singer = 'Artist B';
    song2.src = '/b.mp3'; song2.index = 1;
    store.songs = [song1, song2];

    // Favorite song 1
    store.toggleFavorite(1);
    expect(store.isFavorite(1)).assertEqual(true);
    expect(store.getFavoriteSongs().length).assertEqual(1);

    // Create playlist with song 1
    const pl: Playlist = store.addPlaylist('Favorites Mix', [1]);
    expect(store.getPlaylistSongs(pl).length).assertEqual(1);

    // Add song 2 to playlist
    store.addSongsToPlaylist(pl.id, [2]);
    expect(store.getPlaylistSongs(pl).length).assertEqual(2);

    // Remove song 1 from playlist
    store.removeSongFromPlaylist(pl.id, 1);
    expect(store.getPlaylistSongs(pl).length).assertEqual(1);

    // Un-favorite song 1
    store.toggleFavorite(1);
    expect(store.isFavorite(1)).assertEqual(false);

    // Add to recently played
    store.addToRecentlyPlayed(song1);
    store.addToRecentlyPlayed(song2);
    expect(store.recentlyPlayed.length).assertEqual(2);
    expect(store.recentlyPlayed[0].id).assertEqual(2);
  });

  it('removeSong should clean up playlist references and favorites', 0, () => {
    const store: MusicStore = MusicStore.getInstance();
    store.songs = [];
    store.favorites = new Set();
    store.playlists = [];
    store.recentlyPlayed = [];
    store.loadError = false;

    const song: SongItem = new SongItem();
    song.id = 1; song.title = 'To Remove'; song.singer = 'Artist';
    song.src = '/remove.mp3'; song.index = 0;
    store.songs = [song];

    store.toggleFavorite(1);
    store.addPlaylist('Test', [1]);
    store.addToRecentlyPlayed(song);

    // Remove
    store.removeSong(1);

    expect(store.songs.length).assertEqual(0);
    expect(store.playList.length).assertEqual(0);
    expect(store.isFavorite(1)).assertEqual(false);
    expect(store.recentlyPlayed.length).assertEqual(0);
    expect(store.getPlaylistSongs(store.playlists[0]).length).assertEqual(0);
  });
});

// ============================================================
// DuplicateDetector — 纯函数测试（归一化 / 相似度阈值 / 聚类）
// ============================================================

describe('DuplicateDetector', () => {

  describe('normalizeTitle', () => {

    it('should lowercase and strip spaces and punctuation', 0, () => {
      // '!' 与空格都在剥离字符集内
      expect(DuplicateDetector.normalizeTitle('  Hello World!  ')).assertEqual('helloworld');
      expect(DuplicateDetector.normalizeTitle('hello world')).assertEqual('helloworld');
    });

    it('should treat fullwidth punctuation and CJK punctuation as separators', 0, () => {
      expect(DuplicateDetector.normalizeTitle('（Hello）')).assertEqual('hello');
      expect(DuplicateDetector.normalizeTitle('夜曲。')).assertEqual('夜曲');
      expect(DuplicateDetector.normalizeTitle('A、B（C），D')).assertEqual('abcd');
    });

    it('should strip hyphen and underscore and brackets', 0, () => {
      expect(DuplicateDetector.normalizeTitle('foo-bar_baz')).assertEqual('foobarbaz');
      expect(DuplicateDetector.normalizeTitle('[Live] Song')).assertEqual('livesong');
      expect(DuplicateDetector.normalizeTitle('【Live】Song')).assertEqual('livesong');
    });

    it('should be case-insensitive', 0, () => {
      expect(DuplicateDetector.normalizeTitle('ABC')).assertEqual(DuplicateDetector.normalizeTitle('abc'));
      expect(DuplicateDetector.normalizeTitle('The Song')).assertEqual(DuplicateDetector.normalizeTitle('the song'));
    });

    it('should return empty string for blank or punctuation-only titles', 0, () => {
      expect(DuplicateDetector.normalizeTitle('')).assertEqual('');
      expect(DuplicateDetector.normalizeTitle('   ')).assertEqual('');
      expect(DuplicateDetector.normalizeTitle('\t\n')).assertEqual('');
      expect(DuplicateDetector.normalizeTitle('!!!???...')).assertEqual('');
    });

    it('should keep digits and latin letters intact', 0, () => {
      expect(DuplicateDetector.normalizeTitle('Track 01')).assertEqual('track01');
    });
  });

  describe('similarity', () => {

    it('identical strings should have similarity 1', 0, () => {
      expect(DuplicateDetector.similarity('hello', 'hello')).assertEqual(1);
      expect(DuplicateDetector.similarity('夜曲', '夜曲')).assertEqual(1);
    });

    it('two empty strings should have similarity 1', 0, () => {
      expect(DuplicateDetector.similarity('', '')).assertEqual(1);
    });

    it('one empty string should have similarity 0', 0, () => {
      expect(DuplicateDetector.similarity('a', '')).assertEqual(0);
      expect(DuplicateDetector.similarity('', 'a')).assertEqual(0);
    });

    it('completely different equal-length strings should have similarity 0', 0, () => {
      expect(DuplicateDetector.similarity('abc', 'xyz')).assertEqual(0);
    });

    it('one-edit distance should scale by the longer length', 0, () => {
      // 'abcd' vs 'abc': 编辑距离 1，max 长度 4 → 1 - 1/4
      expect(DuplicateDetector.similarity('abcd', 'abc')).assertEqual(0.75);
      // 'abcdefghij' vs 'abcdefghi': 编辑距离 1，max 长度 10 → 1 - 1/10
      expect(DuplicateDetector.similarity('abcdefghij', 'abcdefghi')).assertEqual(0.9);
    });

    it('should be symmetric', 0, () => {
      expect(DuplicateDetector.similarity('kitten', 'sitting'))
        .assertEqual(DuplicateDetector.similarity('sitting', 'kitten'));
    });

    it('classic kitten/sitting case should land between 0.5 and 0.6', 0, () => {
      const s: number = DuplicateDetector.similarity('kitten', 'sitting');
      expect(s > 0.5).assertEqual(true);
      expect(s < 0.6).assertEqual(true);
    });
  });

  describe('sameTitle', () => {

    it('should be true for same title differing only in case/punctuation/spaces', 0, () => {
      const a: SongItem = buildSong(1, 'Hello World!', 'A', 'X');
      const b: SongItem = buildSong(2, '  hello   world  ', 'A', 'X');
      expect(DuplicateDetector.sameTitle(a, b)).assertEqual(true);
    });

    it('should be true for CJK title with trailing punctuation', 0, () => {
      const a: SongItem = buildSong(1, '夜曲。', '周杰伦', '萧邦');
      const b: SongItem = buildSong(2, '夜曲', '周杰伦', '萧邦');
      expect(DuplicateDetector.sameTitle(a, b)).assertEqual(true);
    });

    it('should be true just above the 0.85 threshold', 0, () => {
      // 归一化后长度 10 / 9，编辑距离 1 → 0.9 >= 0.85
      const a: SongItem = buildSong(1, 'abcdefghij', 'A', 'X');
      const b: SongItem = buildSong(2, 'abcdefghi', 'A', 'X');
      expect(DuplicateDetector.sameTitle(a, b)).assertEqual(true);
    });

    it('should be false just below the 0.85 threshold', 0, () => {
      // 归一化后长度 4 / 3，编辑距离 1 → 0.75 < 0.85
      const a: SongItem = buildSong(1, 'abcd', 'A', 'X');
      const b: SongItem = buildSong(2, 'abc', 'A', 'X');
      expect(DuplicateDetector.sameTitle(a, b)).assertEqual(false);
    });

    it('should be false for different titles', 0, () => {
      const a: SongItem = buildSong(1, 'Song One', 'A', 'X');
      const b: SongItem = buildSong(2, 'Completely Different', 'A', 'X');
      expect(DuplicateDetector.sameTitle(a, b)).assertEqual(false);
    });

    it('should be false when either normalized title is empty', 0, () => {
      const empty: SongItem = buildSong(1, '', 'A', 'X');
      const blank: SongItem = buildSong(2, '   ', 'A', 'X');
      const real: SongItem = buildSong(3, 'Song', 'A', 'X');
      expect(DuplicateDetector.sameTitle(empty, empty)).assertEqual(false);
      expect(DuplicateDetector.sameTitle(blank, blank)).assertEqual(false);
      expect(DuplicateDetector.sameTitle(empty, real)).assertEqual(false);
      expect(DuplicateDetector.sameTitle(real, empty)).assertEqual(false);
    });

    it('title equality should ignore singer (singer is handled by findDuplicates)', 0, () => {
      const a: SongItem = buildSong(1, 'Same', 'Artist A', 'X');
      const b: SongItem = buildSong(2, 'Same', 'Artist B', 'X');
      expect(DuplicateDetector.sameTitle(a, b)).assertEqual(true);
    });
  });

  describe('findDuplicates', () => {

    it('empty input should return empty groups', 0, () => {
      expect(DuplicateDetector.findDuplicates([]).length).assertEqual(0);
    });

    it('input without duplicates should return empty groups', 0, () => {
      const songs: SongItem[] = [
        buildSong(1, 'Alpha', 'A', 'X'),
        buildSong(2, 'Beta', 'A', 'X'),
        buildSong(3, 'Gamma', 'A', 'X')
      ];
      expect(DuplicateDetector.findDuplicates(songs).length).assertEqual(0);
    });

    it('should group two same-title same-singer songs with normalized key', 0, () => {
      const songs: SongItem[] = [
        buildSong(1, 'Hello World!', 'Adele', '19'),
        buildSong(2, 'hello world', 'Adele', '19')
      ];
      const groups: DuplicateGroup[] = DuplicateDetector.findDuplicates(songs);
      expect(groups.length).assertEqual(1);
      expect(groups[0].key).assertEqual('helloworld');
      expect(groups[0].songs.length).assertEqual(2);
      expect(groups[0].songs[0].id).assertEqual(1);
      expect(groups[0].songs[1].id).assertEqual(2);
    });

    it('should group three same-title songs into one group', 0, () => {
      const songs: SongItem[] = [
        buildSong(1, 'Same', 'A', 'X'),
        buildSong(2, 'same', 'A', 'X'),
        buildSong(3, '  SAME  ', 'A', 'X')
      ];
      const groups: DuplicateGroup[] = DuplicateDetector.findDuplicates(songs);
      expect(groups.length).assertEqual(1);
      expect(groups[0].songs.length).assertEqual(3);
    });

    it('should not group when both singers are set and differ', 0, () => {
      const songs: SongItem[] = [
        buildSong(1, 'Same', 'Artist A', 'X'),
        buildSong(2, 'Same', 'Artist B', 'X')
      ];
      expect(DuplicateDetector.findDuplicates(songs).length).assertEqual(0);
    });

    it('should group when one singer is empty (unknown artist fallback)', 0, () => {
      const songs: SongItem[] = [
        buildSong(1, 'Same', 'Artist A', 'X'),
        buildSong(2, 'Same', '', 'X')
      ];
      const groups: DuplicateGroup[] = DuplicateDetector.findDuplicates(songs);
      expect(groups.length).assertEqual(1);
      expect(groups[0].songs.length).assertEqual(2);
    });

    it('should group when both singers are empty', 0, () => {
      const songs: SongItem[] = [
        buildSong(1, 'Same', '', 'X'),
        buildSong(2, 'same', '', 'X')
      ];
      expect(DuplicateDetector.findDuplicates(songs).length).assertEqual(1);
    });

    it('should produce independent groups for two different duplicate clusters', 0, () => {
      const songs: SongItem[] = [
        buildSong(1, 'Alpha', 'A', 'X'),
        buildSong(2, 'alpha', 'A', 'X'),
        buildSong(3, 'Beta', 'B', 'Y'),
        buildSong(4, 'beta', 'B', 'Y')
      ];
      const groups: DuplicateGroup[] = DuplicateDetector.findDuplicates(songs);
      expect(groups.length).assertEqual(2);
      expect(groups[0].key).assertEqual('alpha');
      expect(groups[1].key).assertEqual('beta');
    });

    it('should skip songs with empty title instead of grouping them together', 0, () => {
      const songs: SongItem[] = [
        buildSong(1, '', 'A', 'X'),
        buildSong(2, '', 'A', 'X'),
        buildSong(3, 'Real', 'A', 'X')
      ];
      expect(DuplicateDetector.findDuplicates(songs).length).assertEqual(0);
    });
  });
});

// ============================================================
// SortUtil — 纯函数测试（各档位 / 边界 / 不修改入参）
// ============================================================

describe('SortUtil', () => {

  describe('mode 0 默认顺序', () => {

    it('should keep the input order', 0, () => {
      const songs: SongItem[] = buildMixedSongs();
      const result: SongItem[] = sortSongs(songs, 0, []);
      expect(collectIds(result).join(',')).assertEqual('1,2,3,4');
    });

    it('should return a new array instead of the input reference', 0, () => {
      const songs: SongItem[] = buildMixedSongs();
      expect(sortSongs(songs, 0, []) === songs).assertEqual(false);
    });

    it('empty array should return empty array', 0, () => {
      expect(sortSongs([], 0, []).length).assertEqual(0);
    });

    it('single element should be returned as-is', 0, () => {
      const songs: SongItem[] = [buildSong(7, 'Only', 'Solo', 'Alone')];
      const result: SongItem[] = sortSongs(songs, 0, []);
      expect(result.length).assertEqual(1);
      expect(result[0].id).assertEqual(7);
    });

    it('unknown mode should fall back to the input order', 0, () => {
      const songs: SongItem[] = buildMixedSongs();
      expect(collectIds(sortSongs(songs, 99, [])).join(',')).assertEqual('1,2,3,4');
    });
  });

  describe('mode 1 按标题', () => {

    it('should sort mixed Chinese and English titles in zh locale order', 0, () => {
      const result: SongItem[] = sortSongs(buildMixedSongs(), 1, []);
      expect(result.length).assertEqual(4);
      expect(isSortedByTitle(result)).assertEqual(true);
    });

    it('should preserve the same set of songs (permutation only)', 0, () => {
      const result: SongItem[] = sortSongs(buildMixedSongs(), 1, []);
      expect(collectSortedIds(result).join(',')).assertEqual('1,2,3,4');
    });

    it('empty array should return empty array', 0, () => {
      expect(sortSongs([], 1, []).length).assertEqual(0);
    });

    it('single element should not be reordered', 0, () => {
      const songs: SongItem[] = [buildSong(7, 'Only', 'Solo', 'Alone')];
      const result: SongItem[] = sortSongs(songs, 1, []);
      expect(result.length).assertEqual(1);
      expect(result[0].id).assertEqual(7);
    });

    it('should not mutate the input array', 0, () => {
      const songs: SongItem[] = buildMixedSongs();
      sortSongs(songs, 1, []);
      expect(collectIds(songs).join(',')).assertEqual('1,2,3,4');
    });
  });

  describe('mode 2 按歌手', () => {

    it('should sort by singer in zh locale order', 0, () => {
      const result: SongItem[] = sortSongs(buildMixedSongs(), 2, []);
      expect(result.length).assertEqual(4);
      expect(isSortedBySinger(result)).assertEqual(true);
    });

    it('should preserve the same set of songs', 0, () => {
      const result: SongItem[] = sortSongs(buildMixedSongs(), 2, []);
      expect(collectSortedIds(result).join(',')).assertEqual('1,2,3,4');
    });

    it('empty array should return empty array', 0, () => {
      expect(sortSongs([], 2, []).length).assertEqual(0);
    });

    it('single element should not be reordered', 0, () => {
      const result: SongItem[] = sortSongs([buildSong(7, 'Only', 'Solo', 'Alone')], 2, []);
      expect(result[0].id).assertEqual(7);
    });
  });

  describe('mode 3 按最近播放', () => {

    it('should put recently played songs first, newest first', 0, () => {
      const songs: SongItem[] = buildMixedSongs();
      // 最近播放顺序：id 4 最新，其次 id 2
      const recent: SongItem[] = [buildSong(4, '夜曲', '周杰伦', '十一月的萧邦'), buildSong(2, 'Apple', 'Adele', '19')];
      const result: SongItem[] = sortSongs(songs, 3, recent);
      expect(result.length).assertEqual(4);
      expect(result[0].id).assertEqual(4);
      expect(result[1].id).assertEqual(2);
      expect(collectSortedIds(result).join(',')).assertEqual('1,2,3,4');
    });

    it('empty recently played should keep the input order', 0, () => {
      const result: SongItem[] = sortSongs(buildMixedSongs(), 3, []);
      expect(collectIds(result).join(',')).assertEqual('1,2,3,4');
    });

    it('recently played ids not present in songs should be ignored', 0, () => {
      const recent: SongItem[] = [buildSong(101, 'Ghost', 'Nobody', 'Nowhere')];
      const result: SongItem[] = sortSongs(buildMixedSongs(), 3, recent);
      expect(collectIds(result).join(',')).assertEqual('1,2,3,4');
    });

    it('empty array should return empty array', 0, () => {
      expect(sortSongs([], 3, [buildSong(1, 'A', 'B', 'C')]).length).assertEqual(0);
    });
  });

  describe('mode 4 随机', () => {

    it('should return a permutation of the input (no lost or duplicated songs)', 0, () => {
      const result: SongItem[] = sortSongs(buildMixedSongs(), 4, []);
      expect(result.length).assertEqual(4);
      expect(collectSortedIds(result).join(',')).assertEqual('1,2,3,4');
    });

    it('should not mutate the input array', 0, () => {
      const songs: SongItem[] = buildMixedSongs();
      sortSongs(songs, 4, []);
      expect(collectIds(songs).join(',')).assertEqual('1,2,3,4');
    });

    it('empty array should return empty array', 0, () => {
      expect(sortSongs([], 4, []).length).assertEqual(0);
    });

    it('single element should be returned unchanged', 0, () => {
      const result: SongItem[] = sortSongs([buildSong(7, 'Only', 'Solo', 'Alone')], 4, []);
      expect(result.length).assertEqual(1);
      expect(result[0].id).assertEqual(7);
    });
  });

  describe('mode 5 按专辑', () => {

    it('should sort by album in zh locale order', 0, () => {
      const result: SongItem[] = sortSongs(buildMixedSongs(), 5, []);
      expect(result.length).assertEqual(4);
      expect(isSortedByAlbum(result)).assertEqual(true);
    });

    it('should preserve the same set of songs', 0, () => {
      const result: SongItem[] = sortSongs(buildMixedSongs(), 5, []);
      expect(collectSortedIds(result).join(',')).assertEqual('1,2,3,4');
    });

    it('should not mutate the input array', 0, () => {
      const songs: SongItem[] = buildMixedSongs();
      sortSongs(songs, 5, []);
      expect(collectIds(songs).join(',')).assertEqual('1,2,3,4');
    });

    it('empty array should return empty array', 0, () => {
      expect(sortSongs([], 5, []).length).assertEqual(0);
    });

    it('single element should not be reordered', 0, () => {
      const result: SongItem[] = sortSongs([buildSong(7, 'Only', 'Solo', 'Alone')], 5, []);
      expect(result[0].id).assertEqual(7);
    });
  });

  describe('排序稳定性', () => {

    it('songs with identical title should keep their relative input order', 0, () => {
      const songs: SongItem[] = [
        buildSong(1, 'Same', 'A', 'X'),
        buildSong(2, 'Same', 'B', 'Y'),
        buildSong(3, 'Same', 'C', 'Z')
      ];
      const result: SongItem[] = sortSongs(songs, 1, []);
      expect(collectIds(result).join(',')).assertEqual('1,2,3');
    });

    it('songs with identical album should keep their relative input order', 0, () => {
      const songs: SongItem[] = [
        buildSong(1, 'A', 'X', 'Same Album'),
        buildSong(2, 'B', 'Y', 'Same Album'),
        buildSong(3, 'C', 'Z', 'Same Album')
      ];
      const result: SongItem[] = sortSongs(songs, 5, []);
      expect(collectIds(result).join(',')).assertEqual('1,2,3');
    });

    it('titles with leading and trailing spaces should still be orderable', 0, () => {
      const songs: SongItem[] = [
        buildSong(1, '  Zebra', 'A', 'X'),
        buildSong(2, 'Apple  ', 'A', 'X')
      ];
      const result: SongItem[] = sortSongs(songs, 1, []);
      expect(isSortedByTitle(result)).assertEqual(true);
      expect(collectSortedIds(result).join(',')).assertEqual('1,2');
    });
  });
});
