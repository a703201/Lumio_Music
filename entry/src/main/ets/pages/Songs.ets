import { SongItem } from '../models/music';
import { MusicStore } from '../services/MusicStore';
import { scanLocalMusic } from '../services/MusicScanner';
import { picker } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
import { common } from '@kit.AbilityKit';

@Component
export struct Songs {
  @Consume('navPathStack') pathStack: NavPathStack;
  store: MusicStore = MusicStore.getInstance();
  @StorageProp('topHeight') topHeight: number = 0;
  @State searchText: string = '';
  @State filteredSongs: SongItem[] = [];
  @State isLoading: boolean = false;
  @State isScanning: boolean = false;
  @State itemScales: number[] = [];
  @State importScale: number = 1.0;
  @State emptyIconScale: number = 1.0;
  @State scanProgress: number = 0;
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

  async onScanMusic(): Promise<void> {
    this.isScanning = true;
    this.isLoading = true;
    this.scanProgress = 0;
    try {
      const context = AppStorage.get<common.UIAbilityContext>('context') as common.UIAbilityContext;
      const interval = setInterval(() => {
        if (this.scanProgress < 90) {
          this.scanProgress += 5;
        }
      }, 100);
      const songs: SongItem[] = await scanLocalMusic(context);
      clearInterval(interval);
      this.scanProgress = 100;
      this.store.setSongs(songs);
      this.filteredSongs = [...this.store.songs];
      this.itemScales = this.filteredSongs.map(() => 1.0);
    } catch (err) {
      console.error('Scan failed');
    } finally {
      setTimeout(() => {
        this.isScanning = false;
        this.isLoading = false;
        this.scanProgress = 0;
      }, 300);
    }
  }

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
              console.error('Copy file failed: ' + copyErr);
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
        }
        this.isLoading = false;
      }
    } catch (err) {
      console.error('Pick music failed');
      this.isLoading = false;
    }
  }

  playSong(song: SongItem): void {
    const index = this.store.songs.findIndex(s => s.id === song.id);
    if (index >= 0) {
      this.store.currentIndex = index;
      AppStorage.setOrCreate('selectIndex', index);
      AppStorage.setOrCreate('songList', this.store.songs);
      this.pathStack.pushPathByName('PlayerPage', null);
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
            // Playing indicator with pulse
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
            .fontColor(this.store.currentIndex === index ? '#FA2759' : '#1C1C1E')
            .fontWeight(FontWeight.Medium)
            .margin({ bottom: 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .animation({ duration: 200, curve: Curve.EaseOut })

          Text(song.singer)
            .fontSize(13)
            .fontColor('#8E8E93')
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

      // Index number
      if (this.store.currentIndex !== index) {
        Text(`${index + 1}`)
          .fontSize(13)
          .fontColor('#C7C7CC')
          .margin({ right: 4 })
      }

      Image($r('app.media.ic_more'))
        .width(20)
        .height(20)
        .fillColor('#8E8E93')
        .padding(8)
        .bindMenu(this.buildSongMenu(song))
    }
    .width('100%')
    .height(72)
    .padding({ left: 16, right: 8 })
    .backgroundColor(this.store.currentIndex === index ? 'rgba(250, 39, 89, 0.05)' : '#F2F2F7')
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
        Image($r('app.media.ic_play'))
          .width(18)
          .fillColor('#1C1C1E')
          .margin({ right: 12 })
        Text('播放')
          .fontSize(14)
          .fontColor('#1C1C1E')
      }
      .width('100%')
      .height(44)
      .padding({ left: 16, right: 16 })
      .onClick(() => {
        this.playSong(song);
      })

      Divider().color('#E5E5EA').strokeWidth(0.5)

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
    .backgroundColor(Color.White)
    .borderRadius(12)
    .shadow({ radius: 8, color: 'rgba(0, 0, 0, 0.1)', offsetX: 0, offsetY: 2 })
  }

  build() {
    Column() {
      // Header
      Text('歌曲')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1C1C1E')
        .width('100%')
        .padding({ left: 16, right: 16, top: this.topHeight + 8, bottom: 12 })

      // Search bar
      Row() {
        Image($r('app.media.ic_search'))
          .width(18)
          .height(18)
          .fillColor('#8E8E93')

        TextInput({ placeholder: '搜索歌曲、艺术家' })
          .placeholderColor('#8E8E93')
          .backgroundColor(Color.Transparent)
          .fontColor('#1C1C1E')
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
      .backgroundColor('#F2F2F7')
      .borderRadius(22)
      .margin({ left: 16, right: 16, bottom: 12 })

      // Stats row
      Row() {
        Text(`共 ${this.filteredSongs.length} 首歌曲`)
          .fontSize(13)
          .fontColor('#8E8E93')
          .layoutWeight(1)

        // Quick scan button
        Row({ space: 4 }) {
          Image($r('app.media.ic_music'))
            .width(14)
            .height(14)
            .fillColor('#FA2759')

          Text('扫描')
            .fontSize(13)
            .fontColor('#FA2759')
            .fontWeight(FontWeight.Medium)
        }
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor('rgba(250, 39, 89, 0.08)')
        .borderRadius(16)
        .margin({ right: 8 })
        .enabled(!this.isScanning)
        .onClick(() => {
          this.onScanMusic();
        })

        Row({ space: 4 }) {
          Image($r('app.media.ic_music'))
            .width(14)
            .height(14)
            .fillColor('#FA2759')

          Text('导入')
            .fontSize(13)
            .fontColor('#FA2759')
            .fontWeight(FontWeight.Medium)
        }
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor('rgba(250, 39, 89, 0.08)')
        .borderRadius(16)
        .enabled(!this.isScanning)
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
      .padding({ left: 16, right: 16, bottom: 12 })

      // Scanning progress
      if (this.isScanning) {
        Column() {
          Progress({ style: ProgressStyle.Linear, value: this.scanProgress })
            .width('100%')
            .height(3)
            .color('#FA2759')
            .animation({ duration: 100, curve: Curve.Linear })

          Text(`正在扫描... ${this.scanProgress}%`)
            .fontSize(13)
            .fontColor('#8E8E93')
            .margin({ top: 12 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 12 })
      }

      if (this.isLoading && !this.isScanning) {
        Column() {
          Text('正在加载...')
            .fontSize(14)
            .fontColor('#8E8E93')
            .margin({ top: 100 })
        }
        .layoutWeight(1)
      } else if (this.filteredSongs.length === 0) {
        Column() {
          Image($r('app.media.ic_music'))
            .width(72)
            .height(72)
            .fillColor('#C7C7CC')
            .margin({ bottom: 16 })
            .scale({ x: this.emptyIconScale, y: this.emptyIconScale })
            .animation({ duration: 2000, curve: Curve.EaseInOut })

          Text('未找到本地音乐')
            .fontSize(16)
            .fontColor('#8E8E93')
            .fontWeight(FontWeight.Medium)

          Text('点击上方"扫描"或"导入"按钮添加音频文件')
            .fontSize(13)
            .fontColor('#636366')
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
    .backgroundColor(Color.White)
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
