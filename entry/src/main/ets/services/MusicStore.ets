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

// A2 (3.0.0)：数据层由 Preferences(JSON 大 blob) 升级为 relationalStore(RDB)。
// 设计：内存数组(this.songs / this.favorites / ...) 仍是读路径的权威源（保证页面零改），
// 持久化层改为结构化 RDB，写路径增量 UPSERT（播放统计 / 单曲标签写回 / 删歌）或整表刷新
// （整库导入 import），并保留一次性 Preferences→RDB 迁移。
// ⚠️ 本文件在未安装 DevEco SDK 的沙箱中编写，最终需用户在 DevEco 真机 assembleHap 复核 0 ERROR。
import { Logger } from '../utils/Logger';
import { CoverCache } from '../utils/CoverCache';
import { EmbeddedLyricReader } from '../utils/EmbeddedLyricReader';
import { AudioMetaReader } from '../utils/AudioMeta';
import { SongItem } from '../models/music';
import { RepeatMode, Playlist } from '../models/music';
import dataPreferences from '@ohos.data.preferences';
import relationalStore from '@ohos.data.relationalStore';

interface SongData {
  id: number;
  title: string;
  singer: string;
  src: string;
  index: number;
  album?: string;
  author?: string;
  year?: string;
  lyric?: string;
  sampleRate?: number;
  bitDepth?: number;
  codec?: string;
  folder?: string;
}

const PREF_NAME = 'music_store';
const KEY_SONGS = 'songs';
const KEY_FAVORITES = 'favorites';
const KEY_RECENTLY_PLAYED = 'recently_played';
const KEY_PLAYLISTS = 'playlists';
const KEY_REPEAT_MODE = 'repeat_mode';
const KEY_CURRENT_INDEX = 'current_index';
const KEY_PLAY_COUNTS = 'play_counts';
const KEY_PLAY_MS = 'play_ms';

// ===== RDB 常量 =====
const DB_NAME = 'lumio_music.db';
const DB_VERSION = 1;
const TABLE_SONGS = 'songs';
const TABLE_FAVORITES = 'favorites';
const TABLE_RECENT = 'recently_played';
const TABLE_PLAYLISTS = 'playlists';
const TABLE_PLAY_COUNTS = 'play_counts';
const TABLE_PLAY_MS = 'play_ms';
const TABLE_KV = 'kv';

const COL_ID = 'id';
const COL_TITLE = 'title';
const COL_SINGER = 'singer';
const COL_SRC = 'src';
const COL_INDEX = 'idx';
const COL_ALBUM = 'album';
const COL_AUTHOR = 'author';
const COL_YEAR = 'year';
const COL_LYRIC = 'lyric';
const COL_SAMPLE_RATE = 'sample_rate';
const COL_BIT_DEPTH = 'bit_depth';
const COL_CODEC = 'codec';
const COL_FOLDER = 'folder';
const COL_POS = 'pos';
const COL_VAL = 'val';

const KV_META_SCANNED = 'meta_scanned_v1';
const KV_MIGRATED = 'migrated_v1';
const KV_REPEAT_MODE = 'repeat_mode';
const KV_CURRENT_INDEX = 'current_index';

export interface PlayStatsSummary {
  totalMs: number;
  totalPlays: number;
  songCount: number;
  topSongs: SongItem[];
}

export class MusicStore {
  private static instance: MusicStore | null = null;
  private rdbStore: relationalStore.RdbStore | null = null;

  public songs: SongItem[] = [];
  public playList: SongItem[] = [];
  public currentIndex: number = 0;
  public isPlaying: boolean = false;
  public repeatMode: RepeatMode = 'list';
  public favorites: Set<number> = new Set();
  public playlists: Playlist[] = [];
  public recentlyPlayed: SongItem[] = [];
  /** 听歌统计：播放次数（songId -> count） */
  public playCounts: Map<number, number> = new Map<number, number>();
  /** 听歌统计：累计播放时长（songId -> ms） */
  public playMs: Map<number, number> = new Map<number, number>();
  /** 持久化加载失败标记：页面据此展示错误态+重试按钮 */
  public loadError: boolean = false;

  private constructor() {
  }

  static getInstance(): MusicStore {
    if (!MusicStore.instance) {
      MusicStore.instance = new MusicStore();
    }
    return MusicStore.instance;
  }

  async init(context: Context): Promise<void> {
    try {
      this.rdbStore = await relationalStore.getRdbStore(context, {
        name: DB_NAME,
        securityLevel: relationalStore.SecurityLevel.S1
      });
      await this.createTables();
      await this.migrateFromPreferences(context);
      await this.loadState();
      this.loadError = false;
    } catch (err) {
      this.loadError = true;
      Logger.error('Failed to init RDB store');
    }
  }

  // ===== Schema =====
  private async createTables(): Promise<void> {
    if (!this.rdbStore) {
      return;
    }
    const songCols: string =
      `${COL_ID} INTEGER PRIMARY KEY,` +
      `${COL_TITLE} TEXT,${COL_SINGER} TEXT,${COL_SRC} TEXT,${COL_INDEX} INTEGER,` +
      `${COL_ALBUM} TEXT,${COL_AUTHOR} TEXT,${COL_YEAR} TEXT,${COL_LYRIC} TEXT,` +
      `${COL_SAMPLE_RATE} INTEGER,${COL_BIT_DEPTH} INTEGER,${COL_CODEC} TEXT,${COL_FOLDER} TEXT`;
    const recentCols: string =
      `${COL_ID} INTEGER PRIMARY KEY,` +
      `${COL_TITLE} TEXT,${COL_SINGER} TEXT,${COL_SRC} TEXT,${COL_INDEX} INTEGER,` +
      `${COL_ALBUM} TEXT,${COL_AUTHOR} TEXT,${COL_YEAR} TEXT,${COL_LYRIC} TEXT,` +
      `${COL_SAMPLE_RATE} INTEGER,${COL_BIT_DEPTH} INTEGER,${COL_CODEC} TEXT,${COL_FOLDER} TEXT,${COL_POS} INTEGER`;
    try {
      await this.rdbStore.executeSql(`CREATE TABLE IF NOT EXISTS ${TABLE_SONGS} (${songCols})`);
      await this.rdbStore.executeSql(`CREATE TABLE IF NOT EXISTS ${TABLE_FAVORITES} (${COL_ID} INTEGER PRIMARY KEY)`);
      await this.rdbStore.executeSql(`CREATE TABLE IF NOT EXISTS ${TABLE_RECENT} (${recentCols})`);
      await this.rdbStore.executeSql(`CREATE TABLE IF NOT EXISTS ${TABLE_PLAYLISTS} (id TEXT PRIMARY KEY,name TEXT,song_ids TEXT)`);
      await this.rdbStore.executeSql(`CREATE TABLE IF NOT EXISTS ${TABLE_PLAY_COUNTS} (${COL_ID} INTEGER PRIMARY KEY,${COL_VAL} INTEGER)`);
      await this.rdbStore.executeSql(`CREATE TABLE IF NOT EXISTS ${TABLE_PLAY_MS} (${COL_ID} INTEGER PRIMARY KEY,${COL_VAL} INTEGER)`);
      await this.rdbStore.executeSql(`CREATE TABLE IF NOT EXISTS ${TABLE_KV} (k TEXT PRIMARY KEY,v TEXT)`);
    } catch (err) {
      Logger.error('Failed to create RDB tables');
    }
  }

  // ===== 一次性迁移：旧 Preferences(JSON blob) -> RDB =====
  private async migrateFromPreferences(context: Context): Promise<void> {
    if (!this.rdbStore) {
      return;
    }
    const migrated: string = await this.getKv(KV_MIGRATED, 'false');
    if (migrated === 'true') {
      return;
    }
    try {
      const prefs: dataPreferences.Preferences = await dataPreferences.getPreferences(context, PREF_NAME);
      const songsStr: string = await prefs.get(KEY_SONGS, '[]') as string;
      if (songsStr && songsStr !== '[]') {
        const songsData: SongData[] = JSON.parse(songsStr) as SongData[];
        this.songs = songsData.map((d: SongData) => this.mapSongData(d));
        this.playList = [...this.songs];
        await this.saveSongs();

        const favArr: number[] = JSON.parse(await prefs.get(KEY_FAVORITES, '[]') as string) as number[];
        this.favorites = new Set<number>(favArr);
        await this.saveFavorites();

        const recentData: SongData[] = JSON.parse(await prefs.get(KEY_RECENTLY_PLAYED, '[]') as string) as SongData[];
        this.recentlyPlayed = recentData.map((d: SongData) => this.mapSongData(d));
        await this.saveRecentlyPlayed();

        const rawPlaylists: Playlist[] = JSON.parse(await prefs.get(KEY_PLAYLISTS, '[]') as string) as Playlist[];
        this.playlists = (Array.isArray(rawPlaylists) ? rawPlaylists : [])
          .filter((p: Playlist) => p !== null && p !== undefined && typeof p.id === 'string')
          .map((p: Playlist): Playlist => {
            return {
              id: p.id,
              name: p.name ?? '',
              songIds: Array.isArray(p.songIds)
                ? p.songIds.filter((n: number) => typeof n === 'number')
                : []
            };
          });
        await this.savePlaylists();

        const repeatMode: string = await prefs.get(KEY_REPEAT_MODE, 'list') as string;
        this.repeatMode = repeatMode as RepeatMode;
        await this.putKv(KV_REPEAT_MODE, this.repeatMode);

        const currentIndex: number = await prefs.get(KEY_CURRENT_INDEX, 0) as number;
        this.currentIndex = currentIndex;
        await this.putKv(KV_CURRENT_INDEX, currentIndex.toString());

        this.playCounts = await this.loadNumberMapFromPrefs(prefs, KEY_PLAY_COUNTS);
        this.playMs = await this.loadNumberMapFromPrefs(prefs, KEY_PLAY_MS);
        await this.saveNumberMap(TABLE_PLAY_COUNTS, this.playCounts);
        await this.saveNumberMap(TABLE_PLAY_MS, this.playMs);

        const scanned: boolean = await prefs.get('meta_scanned_v1', false) as boolean;
        await this.putKv(KV_META_SCANNED, scanned ? 'true' : 'false');
      }
      await this.putKv(KV_MIGRATED, 'true');
    } catch (err) {
      Logger.error('RDB migration failed, starting fresh');
      await this.putKv(KV_MIGRATED, 'true');
    }
  }

  private async getKv(k: string, def: string): Promise<string> {
    if (!this.rdbStore) {
      return def;
    }
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_KV);
    predicates.equalTo('k', k);
    try {
      const rs: relationalStore.ResultSet = await this.rdbStore.query(predicates, ['v']);
      let out: string = def;
      if (rs.goToNextRow()) {
        out = rs.getString(rs.getColumnIndex('v'));
      }
      rs.close();
      return out;
    } catch (err) {
      return def;
    }
  }

  private async putKv(k: string, v: string): Promise<void> {
    if (!this.rdbStore) {
      return;
    }
    const values: relationalStore.ValuesBucket = { k: k, v: v };
    try {
      await this.rdbStore.insert(TABLE_KV, values, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    } catch (err) {
      Logger.error('Failed to put kv: ' + k);
    }
  }

  private mapSongData(d: SongData): SongItem {
    const song: SongItem = new SongItem();
    song.id = d.id;
    song.title = d.title;
    song.singer = d.singer;
    song.src = d.src;
    song.index = d.index;
    song.album = d.album ?? '';
    song.author = d.author ?? '';
    song.year = d.year ?? '';
    song.lyric = d.lyric ?? '';
    song.sampleRate = d.sampleRate ?? 0;
    song.bitDepth = d.bitDepth ?? 0;
    song.codec = d.codec ?? '';
    song.folder = d.folder ?? '';
    return song;
  }

  private songToValues(s: SongItem): relationalStore.ValuesBucket {
    const v: relationalStore.ValuesBucket = {};
    v[COL_ID] = s.id;
    v[COL_TITLE] = s.title;
    v[COL_SINGER] = s.singer;
    v[COL_SRC] = s.src;
    v[COL_INDEX] = s.index;
    v[COL_ALBUM] = s.album ?? '';
    v[COL_AUTHOR] = s.author ?? '';
    v[COL_YEAR] = s.year ?? '';
    v[COL_LYRIC] = s.lyric ?? '';
    v[COL_SAMPLE_RATE] = s.sampleRate ?? 0;
    v[COL_BIT_DEPTH] = s.bitDepth ?? 0;
    v[COL_CODEC] = s.codec ?? '';
    v[COL_FOLDER] = s.folder ?? '';
    return v;
  }

  private resultRowToSong(rs: relationalStore.ResultSet): SongItem {
    const s: SongItem = new SongItem();
    s.id = rs.getLong(rs.getColumnIndex(COL_ID));
    s.title = rs.getString(rs.getColumnIndex(COL_TITLE));
    s.singer = rs.getString(rs.getColumnIndex(COL_SINGER));
    s.src = rs.getString(rs.getColumnIndex(COL_SRC));
    s.index = rs.getLong(rs.getColumnIndex(COL_INDEX));
    s.album = rs.getString(rs.getColumnIndex(COL_ALBUM));
    s.author = rs.getString(rs.getColumnIndex(COL_AUTHOR));
    s.year = rs.getString(rs.getColumnIndex(COL_YEAR));
    s.lyric = rs.getString(rs.getColumnIndex(COL_LYRIC));
    s.sampleRate = rs.getLong(rs.getColumnIndex(COL_SAMPLE_RATE));
    s.bitDepth = rs.getLong(rs.getColumnIndex(COL_BIT_DEPTH));
    s.codec = rs.getString(rs.getColumnIndex(COL_CODEC));
    s.folder = rs.getString(rs.getColumnIndex(COL_FOLDER));
    return s;
  }

  setSongs(songs: SongItem[]) {
    this.songs = songs;
    this.playList = [...songs];
    this.saveSongs();
  }

  setCurrentIndex(index: number) {
    this.currentIndex = index;
  }

  setIsPlaying(isPlaying: boolean) {
    this.isPlaying = isPlaying;
  }

  setRepeatMode(mode: RepeatMode) {
    this.repeatMode = mode;
    this.saveRepeatMode();
  }

  toggleFavorite(songId: number) {
    if (this.favorites.has(songId)) {
      this.favorites.delete(songId);
    } else {
      this.favorites.add(songId);
    }
    this.saveFavorites();
  }

  isFavorite(songId: number): boolean {
    return this.favorites.has(songId);
  }

  addPlaylist(name: string, songIds: number[]): Playlist {
    const playlist: Playlist = {
      // P2-3：同一毫秒内连续创建会产生重复 id，deletePlaylist 会一次删掉两个；加随机后缀
      id: `${Date.now()}_${Math.floor(Math.random() * 1e6)}`,
      name: name,
      songIds: songIds
    };
    this.playlists.push(playlist);
    this.savePlaylists();
    return playlist;
  }

  deletePlaylist(id: string) {
    this.playlists = this.playlists.filter(p => p.id !== id);
    this.savePlaylists();
  }

  getPlaylistSongs(playlist: Playlist): SongItem[] {
    return this.songs.filter(s => playlist.songIds.includes(s.id));
  }

  /**
   * 按 id 取歌单。歌单页与详情页之间只传 id，避免传对象副本导致的状态不同步。
   */
  getPlaylistById(id: string): Playlist | undefined {
    return this.playlists.find(p => p.id === id);
  }

  /**
   * 歌单是否已存在同名项（创建/重命名时做去重校验）。
   */
  hasPlaylistName(name: string, excludeId: string = ''): boolean {
    const target: string = name.trim();
    return this.playlists.some(p => p.id !== excludeId && p.name === target);
  }

  renamePlaylist(id: string, name: string): void {
    const target: Playlist | undefined = this.playlists.find(p => p.id === id);
    if (!target) {
      return;
    }
    target.name = name.trim();
    this.savePlaylists();
  }

  /**
   * 向歌单批量追加歌曲，自动去重并保持原有顺序。
   * @returns 实际新增条数
   */
  addSongsToPlaylist(playlistId: string, songIds: number[]): number {
    const target: Playlist | undefined = this.playlists.find(p => p.id === playlistId);
    if (!target) {
      return 0;
    }
    const existing: Set<number> = new Set<number>(target.songIds);
    let added: number = 0;
    songIds.forEach((id: number) => {
      if (!existing.has(id)) {
        existing.add(id);
        target.songIds.push(id);
        added++;
      }
    });
    if (added > 0) {
      this.savePlaylists();
    }
    return added;
  }

  removeSongFromPlaylist(playlistId: string, songId: number): void {
    const target: Playlist | undefined = this.playlists.find(p => p.id === playlistId);
    if (!target) {
      return;
    }
    const before: number = target.songIds.length;
    target.songIds = target.songIds.filter(id => id !== songId);
    if (target.songIds.length !== before) {
      this.savePlaylists();
    }
  }

  /**
   * 歌单内歌曲拖拽排序：将 songIds 中 from 位置移动到 to 位置（FR-24）。
   * 直接操作权威数据数组并持久化，页面按 songIds 顺序渲染即可联动刷新。
   */
  reorderPlaylistSongs(playlistId: string, from: number, to: number): void {
    const target: Playlist | undefined = this.playlists.find(p => p.id === playlistId);
    if (!target) {
      return;
    }
    const ids: number[] = target.songIds;
    if (from < 0 || from >= ids.length || to < 0 || to > ids.length || from === to) {
      return;
    }
    const removed: number[] = ids.splice(from, 1);
    const moved: number = removed[0];
    ids.splice(to, 0, moved);
    this.savePlaylists();
  }

  addToRecentlyPlayed(song: SongItem) {
    this.recentlyPlayed = this.recentlyPlayed.filter(s => s.id !== song.id);
    this.recentlyPlayed.unshift(song);
    if (this.recentlyPlayed.length > 50) {
      this.recentlyPlayed = this.recentlyPlayed.slice(0, 50);
    }
    this.saveRecentlyPlayed();
  }

  getRecentlyPlayed(): SongItem[] {
    return this.recentlyPlayed;
  }

  /**
   * 取「高频」歌曲 src 列表：收藏 + 最近播放 + 各歌单前 N 首，去重保序，上限 totalLimit。
   * 主线程专用（非 sendable）——EntryAbility 启动预热的回退路径，当
   * LumioCoverPreloadTask（taskPool 异步）尚未把 AppStorage('highFreqCoverSrcs') 写好时使用。
   * 与 task 内同名逻辑保持一致，便于两路结果互为兜底。
   */
  getHighFrequencySongSrcs(perPlaylistLimit: number = 5, totalLimit: number = 200): string[] {
    const idToSrc: Map<number, string> = new Map<number, string>();
    for (let i = 0; i < this.songs.length; i++) {
      const s: SongItem = this.songs[i];
      idToSrc.set(s.id, s.src);
    }
    const orderedIds: number[] = [];
    const seen: Set<number> = new Set<number>();
    const pushId = (id: number): void => {
      if (id === undefined || id === null) {
        return;
      }
      if (seen.has(id) || !idToSrc.has(id)) {
        return;
      }
      seen.add(id);
      orderedIds.push(id);
    };
    const favArr: number[] = Array.from(this.favorites);
    for (let i = 0; i < favArr.length && orderedIds.length < totalLimit; i++) {
      pushId(favArr[i]);
    }
    for (let i = 0; i < this.recentlyPlayed.length && orderedIds.length < totalLimit; i++) {
      pushId(this.recentlyPlayed[i].id);
    }
    for (let i = 0; i < this.playlists.length && orderedIds.length < totalLimit; i++) {
      const pl: Playlist = this.playlists[i];
      const ids: number[] = pl.songIds;
      for (let j = 0; j < ids.length && j < perPlaylistLimit && orderedIds.length < totalLimit; j++) {
        pushId(ids[j]);
      }
    }
    const out: string[] = [];
    for (let i = 0; i < orderedIds.length; i++) {
      const src: string | undefined = idToSrc.get(orderedIds[i]);
      if (src !== undefined) {
        out.push(src);
      }
    }
    return out;
  }

  // ===== 听歌统计 =====
  recordPlayStart(songId: number): void {
    if (songId <= 0) {
      return;
    }
    const c: number = this.playCounts.get(songId) ?? 0;
    this.playCounts.set(songId, c + 1);
    this.saveNumberMap(TABLE_PLAY_COUNTS, this.playCounts);
  }

  recordPlayDuration(songId: number, ms: number): void {
    if (songId <= 0 || ms <= 0) {
      return;
    }
    const t: number = this.playMs.get(songId) ?? 0;
    this.playMs.set(songId, t + ms);
    this.saveNumberMap(TABLE_PLAY_MS, this.playMs);
  }

  getPlayCount(songId: number): number {
    return this.playCounts.get(songId) ?? 0;
  }

  getPlayMs(songId: number): number {
    return this.playMs.get(songId) ?? 0;
  }

  getTotalPlayMs(): number {
    let total: number = 0;
    this.playMs.forEach((v: number) => {
      total += v;
    });
    return total;
  }

  getTotalPlays(): number {
    let total: number = 0;
    this.playCounts.forEach((v: number) => {
      total += v;
    });
    return total;
  }

  getMostPlayed(limit: number = 20): SongItem[] {
    const entries: Array<[number, number]> = Array.from(this.playCounts.entries());
    entries.sort((a: [number, number], b: [number, number]) => b[1] - a[1]);
    const out: SongItem[] = [];
    for (let i = 0; i < entries.length && out.length < limit; i++) {
      const song: SongItem | undefined = this.songs.find((s: SongItem) => s.id === entries[i][0]);
      if (song) {
        out.push(song);
      }
    }
    return out;
  }

  getStatsSummary(): PlayStatsSummary {
    return {
      totalMs: this.getTotalPlayMs(),
      totalPlays: this.getTotalPlays(),
      songCount: this.songs.length,
      topSongs: this.getMostPlayed(10)
    };
  }

  getFavoriteSongs(): SongItem[] {
    return this.songs.filter(s => this.favorites.has(s.id));
  }

  /** 按艺术家聚合歌曲（用于艺术家详情页）。 */
  getSongsByArtist(artist: string): SongItem[] {
    if (!artist || artist.length === 0) {
      return [];
    }
    return this.songs.filter((s: SongItem) => s.singer === artist);
  }

  /** 按专辑聚合歌曲（用于专辑详情页）。 */
  getSongsByAlbum(album: string): SongItem[] {
    if (!album || album.length === 0) {
      return [];
    }
    return this.songs.filter((s: SongItem) => s.album === album);
  }

  /** 全部不重复艺术家名（升序），用于浏览入口。 */
  getAllArtists(): string[] {
    const set: Set<string> = new Set<string>();
    this.songs.forEach((s: SongItem) => {
      if (s.singer && s.singer.length > 0) {
        set.add(s.singer);
      }
    });
    return Array.from(set).sort();
  }

  /** 全部不重复专辑名（升序），用于浏览入口。 */
  getAllAlbums(): string[] {
    const set: Set<string> = new Set<string>();
    this.songs.forEach((s: SongItem) => {
      if (s.album && s.album.length > 0) {
        set.add(s.album);
      }
    });
    return Array.from(set).sort();
  }

  /** 持久化当前 songs（标签编辑等写回后调用，对外暴露的安全封装）。 */
  persistSongs(): void {
    this.saveSongs();
  }

  clearRecentlyPlayed() {
    this.recentlyPlayed = [];
    this.saveRecentlyPlayed();
  }

  removeSong(songId: number) {
    // 先取出 src 再过滤，顺带清掉封面 / 歌词缓存，避免删歌后仍占内存
    const removed: SongItem | undefined = this.songs.find(s => s.id === songId);
    if (removed && removed.src) {
      CoverCache.getInstance().evict(removed.src);
      EmbeddedLyricReader.evict(removed.src);
    }
    this.songs = this.songs.filter(s => s.id !== songId);
    this.playList = this.playList.filter(s => s.id !== songId);
    this.favorites.delete(songId);
    this.recentlyPlayed = this.recentlyPlayed.filter(s => s.id !== songId);
    // 同步清理自建歌单中的悬挂引用，避免删歌后歌单数量虚高
    let playlistChanged: boolean = false;
    this.playlists.forEach((p: Playlist) => {
      const before: number = p.songIds.length;
      p.songIds = p.songIds.filter(id => id !== songId);
      if (p.songIds.length !== before) {
        playlistChanged = true;
      }
    });
    this.saveSongs();
    this.saveFavorites();
    this.saveRecentlyPlayed();
    if (playlistChanged) {
      this.savePlaylists();
    }
  }

  /**
   * 一次性补扫已入库歌曲的文本元数据（标题 / 艺术家 / 专辑 / 作者）。
   * 历史版本导入时未读取元数据，导致「未知艺术家」等问题；升级后用本方法在
   * 首次启动时补扫一次，之后通过偏好标记跳过，避免每次启动都做 I/O。
   */
  async refreshMetadataIfNeeded(): Promise<void> {
    const scanned: string = await this.getKv(KV_META_SCANNED, 'false');
    if (scanned === 'true') {
      return;
    }
    let changed: boolean = false;
    for (const song of this.songs) {
      const meta = await AudioMetaReader.read(song.src);
      if (meta) {
        if (meta.title && meta.title.trim().length > 0) {
          song.title = meta.title;
          changed = true;
        }
        if (meta.artist && meta.artist.trim().length > 0) {
          song.singer = meta.artist;
          changed = true;
        }
        if (meta.album) {
          song.album = meta.album;
          changed = true;
        }
        if (meta.author) {
          song.author = meta.author;
          changed = true;
        }
        // 发行年份：一次性补扫路径也回填，保证历史入库歌曲升级后可直读 SongItem.year
        if (meta.year && meta.year.trim().length > 0) {
          song.year = meta.year;
          changed = true;
        }
        // 音频规格：采样率/位深/编码，用于无损/Hi-Res 徽标（补扫路径一并回填）
        if (meta.sampleRate && meta.sampleRate > 0) {
          song.sampleRate = meta.sampleRate;
          changed = true;
        }
        if (meta.bitDepth && meta.bitDepth > 0) {
          song.bitDepth = meta.bitDepth;
          changed = true;
        }
        if (meta.codec && meta.codec.trim().length > 0) {
          song.codec = meta.codec;
          changed = true;
        }
      }
    }
    if (changed) {
      this.saveSongs();
    }
    try {
      await this.putKv(KV_META_SCANNED, 'true');
    } catch (e) {
      Logger.error('Failed to mark metadata scanned');
    }
  }

  private async loadState(): Promise<void> {
    if (!this.rdbStore) {
      return;
    }
    this.loadError = false;
    try {
      const songCols: string[] = [
        COL_ID, COL_TITLE, COL_SINGER, COL_SRC, COL_INDEX, COL_ALBUM, COL_AUTHOR,
        COL_YEAR, COL_LYRIC, COL_SAMPLE_RATE, COL_BIT_DEPTH, COL_CODEC, COL_FOLDER
      ];
      const songRs: relationalStore.ResultSet = await this.rdbStore.query(new relationalStore.RdbPredicates(TABLE_SONGS), songCols);
      this.songs = [];
      while (songRs.goToNextRow()) {
        this.songs.push(this.resultRowToSong(songRs));
      }
      songRs.close();
      this.playList = [...this.songs];

      const favRs: relationalStore.ResultSet = await this.rdbStore.query(new relationalStore.RdbPredicates(TABLE_FAVORITES), [COL_ID]);
      this.favorites = new Set<number>();
      while (favRs.goToNextRow()) {
        this.favorites.add(favRs.getLong(favRs.getColumnIndex(COL_ID)));
      }
      favRs.close();

      const recentPred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_RECENT);
      recentPred.orderByAsc(COL_POS);
      const recentRs: relationalStore.ResultSet = await this.rdbStore.query(recentPred, songCols);
      this.recentlyPlayed = [];
      while (recentRs.goToNextRow()) {
        this.recentlyPlayed.push(this.resultRowToSong(recentRs));
      }
      recentRs.close();

      const plRs: relationalStore.ResultSet = await this.rdbStore.query(new relationalStore.RdbPredicates(TABLE_PLAYLISTS), ['id', 'name', 'song_ids']);
      this.playlists = [];
      while (plRs.goToNextRow()) {
        const id: string = plRs.getString(plRs.getColumnIndex('id'));
        const name: string = plRs.getString(plRs.getColumnIndex('name'));
        const songIdsStr: string = plRs.getString(plRs.getColumnIndex('song_ids'));
        let songIds: number[] = [];
        try {
          songIds = JSON.parse(songIdsStr) as number[];
        } catch (e) {
          songIds = [];
        }
        this.playlists.push({
          id: id,
          name: name,
          songIds: Array.isArray(songIds) ? songIds : []
        });
      }
      plRs.close();

      const repeatMode: string = await this.getKv(KV_REPEAT_MODE, 'list');
      this.repeatMode = repeatMode as RepeatMode;
      const currentIndex: string = await this.getKv(KV_CURRENT_INDEX, '0');
      this.currentIndex = parseInt(currentIndex, 10);
      if (isNaN(this.currentIndex)) {
        this.currentIndex = 0;
      }

      this.playCounts = await this.loadNumberMap(TABLE_PLAY_COUNTS);
      this.playMs = await this.loadNumberMap(TABLE_PLAY_MS);
    } catch (err) {
      this.loadError = true;
      Logger.error('Failed to load state from RDB');
    }
  }

  private async saveSongs(): Promise<void> {
    if (!this.rdbStore) {
      return;
    }
    try {
      await this.rdbStore.executeSql(`DELETE FROM ${TABLE_SONGS}`);
      if (this.songs.length > 0) {
        const bucket: relationalStore.ValuesBucket[] = this.songs.map((s: SongItem) => this.songToValues(s));
        await this.rdbStore.batchInsert(TABLE_SONGS, bucket);
      }
    } catch (err) {
      Logger.error('Failed to save songs');
    }
  }

  private async saveFavorites(): Promise<void> {
    if (!this.rdbStore) {
      return;
    }
    try {
      await this.rdbStore.executeSql(`DELETE FROM ${TABLE_FAVORITES}`);
      const bucket: relationalStore.ValuesBucket[] = [];
      this.favorites.forEach((id: number) => {
        const favRow: relationalStore.ValuesBucket = {};
          favRow[COL_ID] = id;
          bucket.push(favRow);
      });
      if (bucket.length > 0) {
        await this.rdbStore.batchInsert(TABLE_FAVORITES, bucket);
      }
    } catch (err) {
      Logger.error('Failed to save favorites');
    }
  }

  private async saveRecentlyPlayed(): Promise<void> {
    if (!this.rdbStore) {
      return;
    }
    try {
      await this.rdbStore.executeSql(`DELETE FROM ${TABLE_RECENT}`);
      if (this.recentlyPlayed.length > 0) {
        const bucket: relationalStore.ValuesBucket[] = this.recentlyPlayed.map((s: SongItem, i: number) => {
          const v: relationalStore.ValuesBucket = this.songToValues(s);
          v[COL_POS] = i;
          return v;
        });
        await this.rdbStore.batchInsert(TABLE_RECENT, bucket);
      }
    } catch (err) {
      Logger.error('Failed to save recently played');
    }
  }

  private async savePlaylists(): Promise<void> {
    if (!this.rdbStore) {
      return;
    }
    try {
      await this.rdbStore.executeSql(`DELETE FROM ${TABLE_PLAYLISTS}`);
      const bucket: relationalStore.ValuesBucket[] = this.playlists.map((p: Playlist) => {
        const v: relationalStore.ValuesBucket = {};
        v['id'] = p.id;
        v['name'] = p.name;
        v['song_ids'] = JSON.stringify(p.songIds);
        return v;
      });
      if (bucket.length > 0) {
        await this.rdbStore.batchInsert(TABLE_PLAYLISTS, bucket);
      }
    } catch (err) {
      Logger.error('Failed to save playlists');
    }
  }

  private async saveRepeatMode(): Promise<void> {
    await this.putKv(KV_REPEAT_MODE, this.repeatMode);
  }

  private async loadNumberMap(table: string): Promise<Map<number, number>> {
    const m: Map<number, number> = new Map<number, number>();
    if (!this.rdbStore) {
      return m;
    }
    try {
      const rs: relationalStore.ResultSet = await this.rdbStore.query(new relationalStore.RdbPredicates(table), [COL_ID, COL_VAL]);
      while (rs.goToNextRow()) {
        const id: number = rs.getLong(rs.getColumnIndex(COL_ID));
        const val: number = rs.getLong(rs.getColumnIndex(COL_VAL));
        m.set(id, val);
      }
      rs.close();
    } catch (e) {
      // 空表或损坏时返回空 Map
    }
    return m;
  }

  private async loadNumberMapFromPrefs(prefs: dataPreferences.Preferences, key: string): Promise<Map<number, number>> {
    const m: Map<number, number> = new Map<number, number>();
    try {
      const str: string = await prefs.get(key, '{}') as string;
      const obj: Record<string, number> = JSON.parse(str) as Record<string, number>;
      Object.keys(obj).forEach((k: string) => {
        const id: number = Number(k);
        if (!isNaN(id)) {
          m.set(id, obj[k]);
        }
      });
    } catch (e) {
      // 解析失败返回空 Map
    }
    return m;
  }

  private async saveNumberMap(table: string, m: Map<number, number>): Promise<void> {
    if (!this.rdbStore) {
      return;
    }
    try {
      await this.rdbStore.executeSql(`DELETE FROM ${table}`);
      const bucket: relationalStore.ValuesBucket[] = [];
      m.forEach((v: number, k: number) => {
        const numRow: relationalStore.ValuesBucket = {};
          numRow[COL_ID] = k;
          numRow[COL_VAL] = v;
          bucket.push(numRow);
      });
      if (bucket.length > 0) {
        await this.rdbStore.batchInsert(table, bucket);
      }
    } catch (err) {
      Logger.error('Failed to save number map: ' + table);
    }
  }
}
