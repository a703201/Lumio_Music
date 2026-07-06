import { common, wantConstant, Want } from '@kit.AbilityKit';
import { MusicStore } from '../services/MusicStore';

@Builder
export function SettingsBuilder() {
  Settings()
}

@Component
struct Settings {
  pathStack: NavPathStack = new NavPathStack();
  store: MusicStore = MusicStore.getInstance();
  @StorageProp('topHeight') topHeight: number = 0;

  @State scanProgress: number = 0;
  @State isScanning: boolean = false;
  @State itemScales: number[] = [1.0, 1.0, 1.0, 1.0];
  @State backScale: number = 1.0;
  @State repeatModeIndex: number = 0;

  aboutToAppear(): void {
    const modes: ('none' | 'list' | 'single')[] = ['none', 'list', 'single'];
    this.repeatModeIndex = modes.indexOf(this.store.repeatMode);
  }

  @Builder
  buildSettingItem(icon: ResourceStr, title: string, subtitle: string = '', index: number = 0, iconColor: string = '#FA2759', onClick: () => void = () => {}) {
    Column() {
      Row() {
        // Icon container
        Stack() {
          Image(icon)
            .width(20)
            .height(20)
            .fillColor(Color.White)
        }
        .width(36)
        .height(36)
        .borderRadius(10)
        .backgroundColor(iconColor)
        .margin({ right: 14 })
        .shadow({
          radius: 6,
          color: `${iconColor}33`,
          offsetX: 0,
          offsetY: 2
        })

        Column() {
          Text(title)
            .fontSize(16)
            .fontColor('#1C1C1E')
            .fontWeight(FontWeight.Medium)
            .margin({ bottom: subtitle ? 4 : 0 })

          if (subtitle) {
            Text(subtitle)
              .fontSize(13)
              .fontColor('#8E8E93')
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Image($r('app.media.ic_more'))
          .width(16)
          .fillColor('#C7C7CC')
      }
      .width('100%')
      .height(60)
      .padding({ left: 16, right: 16 })
      .onClick(onClick)
    }
    .width('100%')
    .backgroundColor('#F2F2F7')
    .borderRadius(14)
    .margin({ bottom: 2 })
    .scale({ x: this.itemScales[index] ?? 1.0, y: this.itemScales[index] ?? 1.0 })
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 })))
    .animation({ duration: 300, curve: Curve.EaseOut, delay: index * 60 })
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

  build() {
    NavDestination() {
      Column() {
        // Header
        Row() {
          Image($r('app.media.ic_back'))
            .width(24)
            .height(24)
            .fillColor('#1C1C1E')
            .scale({ x: this.backScale, y: this.backScale })
            .animation({ duration: 150, curve: Curve.EaseOut })
            .onClick(() => {
              this.pathStack.pop();
            })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                this.backScale = 0.8;
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.backScale = 1.0;
              }
            })

          Text('设置')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1C1C1E')
            .margin({ left: 12 })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.topHeight + 12, bottom: 16 })

        Scroll() {
          Column() {
            // Scan section
            Text('音乐管理')
              .fontSize(13)
              .fontColor('#8E8E93')
              .width('100%')
              .padding({ left: 4, bottom: 10 })

            Column() {
              this.buildSettingItem(
                $r('app.media.ic_music'),
                '扫描本地音乐',
                '扫描设备中的音频文件',
                0,
                '#FA2759',
                () => {
                  this.isScanning = true;
                  this.scanProgress = 0;
                  const interval = setInterval(() => {
                    this.scanProgress += 8;
                    if (this.scanProgress >= 100) {
                      clearInterval(interval);
                      setTimeout(() => {
                        this.isScanning = false;
                        this.scanProgress = 0;
                      }, 300);
                    }
                  }, 100);
                }
              )
            }
            .margin({ bottom: 8 })

            // Scan progress
            if (this.isScanning) {
              Column() {
                Row() {
                  Text('扫描中...')
                    .fontSize(13)
                    .fontColor('#8E8E93')
                  Text(`${this.scanProgress}%`)
                    .fontSize(13)
                    .fontColor('#FA2759')
                    .fontWeight(FontWeight.Medium)
                }
                .width('100%')
                .justifyContent(FlexAlign.SpaceBetween)
                .margin({ bottom: 8 })

                Progress({ style: ProgressStyle.Linear, value: this.scanProgress })
                  .width('100%')
                  .height(4)
                  .color('#FA2759')
                  .animation({ duration: 100, curve: Curve.Linear })
              }
              .width('100%')
              .padding({ left: 16, right: 16, bottom: 12 })
              .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -10 })))
              .animation({ duration: 300, curve: Curve.EaseOut })
            }

            // Playback section
            Text('播放设置')
              .fontSize(13)
              .fontColor('#8E8E93')
              .width('100%')
              .padding({ left: 4, top: 16, bottom: 10 })

            Column() {
              this.buildSettingItem(
                $r('app.media.ic_repeat'),
                '播放模式',
                `当前: ${this.store.repeatMode === 'list' ? '列表循环' : this.store.repeatMode === 'single' ? '单曲循环' : '顺序播放'}`,
                1,
                '#FF9500',
                () => {
                  const modes: ('none' | 'list' | 'single')[] = ['none', 'list', 'single'];
                  const currentIndex: number = modes.indexOf(this.store.repeatMode);
                  const nextIndex: number = (currentIndex + 1) % modes.length;
                  this.store.setRepeatMode(modes[nextIndex]);
                  this.repeatModeIndex = nextIndex;
                }
              )
            }
            .margin({ bottom: 8 })

            // About section
            Text('关于')
              .fontSize(13)
              .fontColor('#8E8E93')
              .width('100%')
              .padding({ left: 4, top: 16, bottom: 10 })

            Column() {
              this.buildSettingItem(
                $r('app.media.ic_logo'),
                '版本信息',
                'HM_Music v2.0',
                2,
                '#5856D6',
                () => {
                  this.pathStack.pushPathByName('About', null);
                }
              )
            }
            .margin({ bottom: 2 })

            Column() {
              this.buildSettingItem(
                $r('app.media.ic_code'),
                '开发者',
                'Lumio',
                3,
                '#34C759',
                () => {
                  try {
                    const want: Want = {
                      action: 'ohos.want.action.viewData',
                      uri: 'https://www.a703201sworld.top/resume/',
                      flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
                    };
                    let context = getContext(this) as common.UIAbilityContext;
                    context.startAbility(want).catch((err: Error) => {
                      console.error('Failed to start ability:', err);
                    });
                  } catch (err) {
                    console.error('Failed to start ability:', err);
                  }
                }
              )
            }
            .margin({ bottom: 8 })

            // Footer
            Text('Made with HarmonyOS SDK')
              .fontSize(12)
              .fontColor('#C7C7CC')
              .margin({ top: 24, bottom: 20 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 40 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.White)
    }
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
    .hideTitleBar(true)
  }
}
