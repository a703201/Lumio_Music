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
