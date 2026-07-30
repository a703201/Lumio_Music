import { common, Want } from '@kit.AbilityKit';
import { getAppVersionDisplay } from '../utils/AppInfoUtil';
import { promptAction } from '@kit.ArkUI';
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

  @State itemScales: number[] = [1.0, 1.0, 1.0, 1.0];
  @State backScale: number = 1.0;
  @State appVersionDisplay: string = 'Lumio Music';

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

        Image($r('app.media.ic_hm_more'))
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

  private openDeveloper(): void {
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: 'https://www.a703201sworld.top/resume/'
      };
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.startAbility(want).catch((err: Error) => {
        console.error('Failed to open resume page:', err);
        promptAction.showToast({ message: '无法打开网页' });
      });
    } catch (err) {
      console.error('Failed to open resume page:', err);
      promptAction.showToast({ message: '无法打开网页' });
    }
  }

  aboutToAppear(): void {
    this.appVersionDisplay = getAppVersionDisplay();
  }

  build() {
    NavDestination() {
      Column() {
        // Header
        Row() {
          Image($r('app.media.ic_hm_back'))
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
            // 音乐管理
            Text('音乐管理')
              .fontSize(13)
              .fontColor('#8E8E93')
              .width('100%')
              .padding({ left: 4, bottom: 10 })

            Column() {
              this.buildSettingItem(
                $r('app.media.ic_hm_list'),
                '清空播放历史',
                `共 ${this.store.recentlyPlayed.length} 首`,
                0,
                '#FF9500',
                () => {
                  this.store.clearRecentlyPlayed();
                  promptAction.showToast({ message: '已清空播放历史' });
                }
              )
            }
            .margin({ bottom: 8 })

            // 关于
            Text('关于')
              .fontSize(13)
              .fontColor('#8E8E93')
              .width('100%')
              .padding({ left: 4, top: 16, bottom: 10 })

            Column() {
              this.buildSettingItem(
                $r('app.media.ic_hm_settings'),
                '版本信息',
                this.appVersionDisplay,
                1,
                '#5856D6',
                () => {
                  this.pathStack.pushPathByName('About', null);
                }
              )
            }
            .margin({ bottom: 8 })

            Column() {
              this.buildSettingItem(
                $r('app.media.ic_hm_profile'),
                '开发者',
                '何宇翔',
                2,
                '#34C759',
                () => {
                  this.openDeveloper();
                }
              )
            }
            .margin({ bottom: 8 })

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
