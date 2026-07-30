import { curves } from '@kit.ArkUI';
import { ThemeManager } from '../utils/ThemeManager';
import { SongItem } from '../models/music';
import { MusicStore } from '../services/MusicStore';
import { picker } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
import { common } from '@kit.AbilityKit';

const ACCENT: string = '#FA2759';
const PLAYER_COVER_ID: string = 'player_cover';

@Builder
export function LocalLibraryBuilder() {
  LocalLibrary()
}

@Component
export struct LocalLibrary {
  @Consume('navPathStack') pathStack: NavPathStack;
  store: MusicStore = MusicStore.getInstance();
  @StorageProp('topHeight') topHeight: number = 0;
  @StorageProp('bottomHeight') bottomHeight: number = 0;
  @StorageProp('isDark') isDark: boolean = false;

  @State searchText: string = '';
  @State filteredSongs: SongItem[] = [];
  @State isLoading: boolean = false;
  @State itemScales: number[] = [];
  @State importScale: number = 1.0;
  @State emptyIconScale: number = 1.0;
  @State playingIndex: number = -1;
  private playingPulse: number = -1;

  aboutToAppear(): void {
    this.filteredSongs = [...this.store.songs];
    this.itemScales = this.filteredSongs.map(() => 1.0);
    this.startEmptyPulse();
    this.startPlayingPulse();
  }

  aboutToDisappear(): void {
    if (this.playingPulse >= 0) {
      clearInterval(this.playingPulse);
    }
  }

  startEmptyPulse(): void {
    setInterval(() => {
      if (this.filteredSongs.length === 0 && !this.isLoading) {
        this.emptyIconScale = this.emptyIconScale === 1.0 ? 1.08 : 1.0;
      }
    }, 2000);
  }

  startPlayingPulse(): void {
    this.playingPulse = setInterval(() => {
      this.playingIndex = this.store.isPlaying ? this.store.currentIndex : -1;
    }, 500);
  }

  onSearchChange(text: string): void {
    this.searchText = text;
    if (text.trim() === '') {
      this.filteredSongs = [...this.store.songs];
    } else {
      this.filteredSongs = this.store.songs.filter(song =>
        song.title.includes(text) ||
        song.singer.includes(text)
      );
    }
    this.itemScales = this.filteredSongs.map(() => 1.0);
  }

  // 原歌曲页的导入功能，已迁移至音乐库页
  async onPickMusic(): Promise<void> {
    try {
      const audioPicker = new picker.DocumentViewPicker();
      const result: string[] = await audioPicker.select();
      if (result && result.length > 0) {
        this.isLoading = true;
        const context = AppStorage.get<common.UIAbilityContext>('context') as common.UIAbilityContext;
        const downloadDir = context.filesDir + '/download';
        try {
          if (!fs.accessSync(downloadDir)) {
            fs.mkdirSync(downloadDir);
          }
        } catch (e) {
          try { fs.mkdirSync(downloadDir); } catch (err) {}
        }
        const newSongs: SongItem[] = [];
        for (const uri of result) {
          const existingIndex = this.store.songs.findIndex(s => s.src === uri);
          if (existingIndex < 0) {
            const fileName = decodeURIComponent(uri.substring(uri.lastIndexOf('/') + 1));
            const title = fileName.includes('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;
            const destPath = downloadDir + '/' + fileName;
            try {
              const srcFile = fs.openSync(uri, fs.OpenMode.READ_ONLY);
              const destFile = fs.openSync(destPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
              fs.copyFileSync(srcFile.fd, destFile.fd);
              fs.closeSync(srcFile.fd);
              fs.closeSync(destFile.fd);
              const song = new SongItem();
              song.id = Math.abs(hashCode(destPath));
              song.title = title;
              song.singer = '未知艺术家';
              song.src = destPath;
              song.index = this.store.songs.length + newSongs.length;
              newSongs.push(song);
            } catch (copyErr) {
              const song = new SongItem();
              song.id = Math.abs(hashCode(uri));
              song.title = title;
              song.singer = '未知艺术家';
              song.src = uri;
              song.index = this.store.songs.length + newSongs.length;
              newSongs.push(song);
            }
          }
        }
        if (newSongs.length > 0) {
          this.store.setSongs([...this.store.songs, ...newSongs]);
          this.filteredSongs = [...this.store.songs];
          this.itemScales = this.filteredSongs.map(() => 1.0);
          this.getUIContext().getPromptAction().showToast({ message: `已导入 ${newSongs.length} 首音乐` });
        } else {
          this.getUIContext().getPromptAction().showToast({ message: '没有新的音乐文件' });
        }
        this.isLoading = false;
      }
    } catch (err) {
      console.error('Pick music failed');
      this.isLoading = false;
    }
  }

  // 一镜到底：进入播放页时与迷你播放条封面共享元素过渡
  playSong(song: SongItem): void {
    const index = this.store.songs.findIndex(s => s.id === song.id);
    if (index >= 0) {
      this.store.currentIndex = index;
      AppStorage.setOrCreate('selectIndex', index);
      AppStorage.setOrCreate('songList', this.store.songs);
      this.getUIContext().animateTo(
        { curve: curves.interpolatingSpring(0, 1, 328, 36) },
        () => {
          this.pathStack.pushPathByName('PlayerPage', null);
        }
      );
    }
  }

  deleteSong(song: SongItem): void {
    this.store.removeSong(song.id);
    this.filteredSongs = [...this.store.songs];
    this.itemScales = this.filteredSongs.map(() => 1.0);
  }

  @Builder
  buildSongItem(song: SongItem, index: number) {
    Row() {
      Row() {
        Stack() {
          Image(song.getMark())
            .width(56)
            .height(56)
            .borderRadius(this.playingIndex === index ? 28 : 8)
            .clip(true)
            .animation({ duration: 300, curve: Curve.EaseOut })

          if (this.store.currentIndex === index && this.store.isPlaying) {
            Stack() {
              Circle()
                .width(24)
                .height(24)
                .fill('rgba(250, 39, 89, 0.3)')
                .scale({ x: this.emptyIconScale, y: this.emptyIconScale })

              Image($r('app.media.ic_playing'))
                .width(16)
                .height(16)
            }
            .position({ x: 38, y: 38 })
          }
        }

        Column() {
          Text(song.title)
            .fontSize(16)
            .fontColor(this.store.currentIndex === index ? '#FA2759' : ThemeManager.getColors().primaryText)
            .fontWeight(FontWeight.Medium)
            .margin({ bottom: 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .animation({ duration: 200, curve: Curve.EaseOut })

          Text(song.singer)
            .fontSize(13)
            .fontColor(ThemeManager.getColors().secondaryText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 12 })
      }
      .layoutWeight(1)
      .height('100%')
      .onClick(() => {
        this.playSong(song);
      })

      if (this.store.currentIndex !== index) {
        Text(`${index + 1}`)
          .fontSize(13)
          .fontColor(ThemeManager.getColors().secondaryText)
          .margin({ right: 4 })
      }

      Image($r('app.media.ic_hm_more'))
        .width(20)
        .height(20)
        .fillColor(ThemeManager.getColors().secondaryText)
        .padding(8)
        .bindMenu(this.buildSongMenu(song))
    }
    .width('100%')
    .height(72)
    .padding({ left: 16, right: 8 })
    .backgroundColor(this.store.currentIndex === index ? 'rgba(250, 39, 89, 0.05)' : ThemeManager.getColors().cardBg)
    .borderRadius(12)
    .margin({ bottom: 8 })
    .scale({ x: this.itemScales[index] ?? 1.0, y: this.itemScales[index] ?? 1.0 })
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 30 })))
    .animation({ duration: 300, curve: Curve.EaseOut, delay: index * 50 })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        let scales = [...this.itemScales];
        scales[index] = 0.96;
        this.itemScales = scales;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        let scales = [...this.itemScales];
        scales[index] = 1.0;
        this.itemScales = scales;
      }
    })
  }

  @Builder
  buildSongMenu(song: SongItem) {
    Column() {
      Row() {
        Image($r('app.media.ic_hm_play'))
          .width(18)
          .fillColor(ThemeManager.getColors().primaryText)
          .margin({ right: 12 })
        Text('播放')
          .fontSize(14)
          .fontColor(ThemeManager.getColors().primaryText)
      }
      .width('100%')
      .height(44)
      .padding({ left: 16, right: 16 })
      .onClick(() => {
        this.playSong(song);
      })

      Divider().color(ThemeManager.getColors().separator).strokeWidth(0.5)

      Row() {
        Image($r('app.media.ic_close'))
          .width(18)
          .fillColor('#FA2759')
          .margin({ right: 12 })
        Text('删除')
          .fontSize(14)
          .fontColor('#FA2759')
      }
      .width('100%')
      .height(44)
      .padding({ left: 16, right: 16 })
      .onClick(() => {
        this.deleteSong(song);
      })
    }
    .width(160)
    .backgroundColor(ThemeManager.getColors().bg)
    .borderRadius(12)
    .shadow({ radius: 8, color: 'rgba(0, 0, 0, 0.1)', offsetX: 0, offsetY: 2 })
  }

  build() {
    Column() {
      // Header + 导入入口（原歌曲页导入功能已迁移至此）
      Row() {
        Text('音乐库')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeManager.getColors().primaryText)
          .layoutWeight(1)
          .padding({ left: 16, right: 16, top: this.topHeight + 8, bottom: 12 })

        Row({ space: 4 }) {
          Image($r('app.media.ic_hm_download'))
            .width(16)
            .height(16)
            .fillColor(ACCENT)
          Text('导入')
            .fontSize(13)
            .fontColor(ACCENT)
            .fontWeight(FontWeight.Medium)
        }
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor('rgba(250, 39, 89, 0.08)')
        .borderRadius(16)
        .margin({ right: 16, top: this.topHeight + 8 })
        .scale({ x: this.importScale, y: this.importScale })
        .animation({ duration: 150, curve: Curve.EaseOut })
        .onClick(() => {
          this.onPickMusic();
        })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.importScale = 0.92;
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.importScale = 1.0;
          }
        })
      }
      .width('100%')

      // Search bar
      Row() {
        Image($r('app.media.ic_hm_search'))
          .width(18)
          .height(18)
          .fillColor(ThemeManager.getColors().secondaryText)

        TextInput({ placeholder: '搜索歌曲、艺术家' })
          .placeholderColor(ThemeManager.getColors().secondaryText)
          .backgroundColor(Color.Transparent)
          .fontColor(ThemeManager.getColors().primaryText)
          .fontSize(15)
          .layoutWeight(1)
          .margin({ left: 8 })
          .onChange((value: string) => {
            this.onSearchChange(value);
          })
      }
      .width('100%')
      .height(44)
      .padding({ left: 14, right: 14 })
      .backgroundColor(ThemeManager.getColors().cardBg)
      .borderRadius(22)
      .margin({ left: 16, right: 16, bottom: 12 })

      // Stats row
      Row() {
        Text(`共 ${this.filteredSongs.length} 首歌曲`)
          .fontSize(13)
          .fontColor(ThemeManager.getColors().secondaryText)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 12 })

      if (this.isLoading) {
        Column() {
          Text('正在导入...')
            .fontSize(14)
            .fontColor(ThemeManager.getColors().secondaryText)
            .margin({ top: 100 })
        }
        .layoutWeight(1)
      } else if (this.filteredSongs.length === 0) {
        Column() {
          Image($r('app.media.ic_hm_library'))
            .width(72)
            .height(72)
            .fillColor(ThemeManager.getColors().secondaryText)
            .margin({ bottom: 16 })
            .scale({ x: this.emptyIconScale, y: this.emptyIconScale })
            .animation({ duration: 2000, curve: Curve.EaseInOut })

          Text('音乐库还是空的')
            .fontSize(16)
            .fontColor(ThemeManager.getColors().secondaryText)
            .fontWeight(FontWeight.Medium)

          Text('点击右上角"导入"添加本地音频')
            .fontSize(13)
            .fontColor(ThemeManager.getColors().secondaryText)
            .margin({ top: 8 })
            .textAlign(TextAlign.Center)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.filteredSongs, (song: SongItem, index: number) => {
            ListItem() {
              this.buildSongItem(song, index)
            }
          })
        }
        .width('100%')
        .height('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ bottom: this.bottomHeight + 200 })
    .backgroundColor(ThemeManager.getColors().bg)
  }
}

function hashCode(str: string): number {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash;
  }
  return hash;
}
