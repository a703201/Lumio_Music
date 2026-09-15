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

/*
 * 本地分享工具：全部走系统能力，不依赖网络、不产生任何出网请求（隐私优先）。
 *  - shareSong   : 通过系统分享面板把单曲音频文件分享给其他应用（离线、文件不出机外的用户主动行为）。
 *  - shareText   : 分享文本卡片（如「年度记录」摘要），无文件传输。
 *  - exportPlaylist: 把歌单导出为 .m3u 文本，经 DocumentViewPicker 由用户主动选择落盘位置，不申请存储权限。
 */

import { SongItem, Playlist } from '../models/music';
import { MusicStore } from '../services/MusicStore';
import { Logger } from './Logger';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';

const TAG: string = 'ShareUtil';

export class ShareUtil {
  /**
   * 把单曲音频文件通过系统分享面板分享给其他应用。
   * 分享的是沙箱内音频文件的 URI，系统分享面板会在本次分享内临时授予目标应用读取权限。
   */
  static shareSong(song: SongItem): void {
    if (!song || !song.src || song.src.length === 0) {
      Logger.warn(TAG, 'shareSong: empty song src');
      return;
    }
    try {
      const uri: string = fileUri.getUriFromPath(song.src);
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.FILE,
        uri: uri,
        title: `${song.title} - ${song.singer}`
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      const ctx: common.UIAbilityContext | undefined = AppStorage.get('context') as common.UIAbilityContext;
      if (!ctx) {
        Logger.error(TAG, 'shareSong: missing UIAbilityContext');
        return;
      }
      controller.show(ctx, {}).catch((e: Object) => {
        Logger.error(TAG, 'shareSong failed: ' + (e as Error).message);
      });
    } catch (e) {
      Logger.error(TAG, 'shareSong failed: ' + (e as Error).message);
    }
  }

  /**
   * 分享一段文本（如年度听歌记录摘要）。不传输任何文件。
   */
  static shareText(text: string, title: string = ''): void {
    if (!text || text.length === 0) {
      return;
    }
    try {
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.PLAIN_TEXT,
        content: text,
        title: title
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      const ctx: common.UIAbilityContext | undefined = AppStorage.get('context') as common.UIAbilityContext;
      if (!ctx) {
        Logger.error(TAG, 'shareText: missing UIAbilityContext');
        return;
      }
      controller.show(ctx, {}).catch((e: Object) => {
        Logger.error(TAG, 'shareText failed: ' + (e as Error).message);
      });
    } catch (e) {
      Logger.error(TAG, 'shareText failed: ' + (e as Error).message);
    }
  }

  /**
   * 把歌单导出为 .m3u 播放列表文件。
   * 经 DocumentViewPicker 由用户主动选择保存位置（无需 WRITE_MEDIA 权限），写入成功返回 true。
   */
  static async exportPlaylist(playlist: Playlist): Promise<boolean> {
    if (!playlist) {
      return false;
    }
    try {
      const savePicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = [`${ShareUtil.sanitizeFileName(playlist.name)}.m3u`];
      const uris: Array<string> = await savePicker.save(options);
      if (!uris || uris.length === 0) {
        return false;
      }
      const content: string = ShareUtil.buildM3u(playlist);
      const file: fs.File = fs.openSync(uris[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE);
      try {
        fs.writeSync(file.fd, content);
      } finally {
        fs.closeSync(file);
      }
      return true;
    } catch (e) {
      Logger.error(TAG, 'exportPlaylist failed: ' + (e as Error).message);
      return false;
    }
  }

  /** 生成标准 .m3u 文本：每条歌曲一行 EXTINF（标题 - 艺术家）+ 一行文件 URI。 */
  private static buildM3u(playlist: Playlist): string {
    const lines: Array<string> = ['#EXTM3U'];
    const byId: Map<number, SongItem> = new Map<number, SongItem>();
    MusicStore.getInstance().songs.forEach((s: SongItem) => {
      byId.set(s.id, s);
    });
    playlist.songIds.forEach((id: number) => {
      const song: SongItem | undefined = byId.get(id);
      if (song) {
        lines.push(`#EXTINF:-1,${song.title} - ${song.singer}`);
        lines.push(song.src);
      }
    });
    return lines.join('\n');
  }

  /** 把歌单名转成安全的文件名片段（去斜杠/反斜杠/空字符等）。 */
  private static sanitizeFileName(name: string): string {
    const ctx: common.UIAbilityContext | undefined = AppStorage.get<common.UIAbilityContext>('context') as common.UIAbilityContext;
    const trimmed: string = (name && name.trim().length > 0) ? name.trim() : (ctx ? ctx.resourceManager.getStringSync($r('app.string.playlist').id) : 'playlist');
    return trimmed.replace(/[\\/:*?"<>|]/g, '_').substring(0, 64);
  }
}
