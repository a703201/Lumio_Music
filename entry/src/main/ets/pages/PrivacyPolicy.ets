import { ThemeManager, ColorTokens } from '../utils/ThemeManager';

@Builder
export function PrivacyPolicyBuilder() {
  PrivacyPolicy()
}

@Component
struct PrivacyPolicy {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('topHeight') topHeight: number = 0;
  @StorageProp('isDark') isDark: boolean = false;

  private getThemeColors(): ColorTokens {
    return this.isDark ? ThemeManager.darkColors : ThemeManager.lightColors;
  }

  build() {
    NavDestination() {
      Column() {
        // Header
        Row() {
          Image($r('app.media.ic_hm_back'))
            .width(24)
            .height(24)
            .fillColor(this.getThemeColors().primaryText)
            .onClick(() => {
              this.pathStack.pop();
            })

          Text('隐私政策')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getThemeColors().primaryText)
            .margin({ left: 12 })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.topHeight + 12, bottom: 16 })

        Scroll() {
          Column() {
            this.buildSection(
              '概述',
              'Lumio Music 是一款纯本地音乐播放器。我们只读取你设备上的音频文件，帮你自由导入、播放和管理本地音乐。我们不做任何网络上传，没有云端，没有账号系统，也不会接入任何第三方 SDK 收集你的信息。'
            )
            this.buildSection(
              '我们收集的信息',
              '我们不收集你的个人信息，也绝不会把任何数据传输出你的手机。应用运行所需的全部数据——播放历史、收藏列表、主题与播放模式等设置偏好、听歌统计开关——都只保存在你的设备本地，一切都在你手机上完成，无需联网。'
            )
            this.buildSection(
              '权限说明',
              '为了正常播放本地音乐，应用会申请以下权限：读取本地音频文件（用于导入和播放你设备上的音乐）；媒体会话 / 锁屏控制（用于后台播放，并在锁屏界面显示媒体控制卡片）；应用存储（文件 / 媒体）（用于缓存与下载目录管理，提升播放体验）。这些权限仅用于实现播放功能，不会被用于任何其他用途。'
            )
            this.buildSection(
              '数据存储位置',
              '你所有的数据都存放在应用自己的沙箱目录（Preferences 与文件目录）中，与其他应用隔离，仅本应用可访问，不会上传到任何服务器。'
            )
            this.buildSection(
              '与第三方共享',
              '无。我们不向任何第三方分享、出售或传输你的数据，也不集成任何会收集信息的第三方 SDK。'
            )
            this.buildSection(
              '您的控制与权利',
              '你完全掌控自己的数据：在「设置」中可一键清除缓存；可清除听歌统计数据；可随时关闭听歌统计功能。卸载应用后，相关本地数据也会随之删除。'
            )
            this.buildSection(
              '联系方式',
              '如有任何疑问，欢迎联系开发者：何宇翔。'
            )
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 40 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.getThemeColors().bg)
    }
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
    .hideTitleBar(true)
  }

  @Builder
  buildSection(title: string, body: string) {
    Column() {
      Text(title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getThemeColors().primaryText)
        .width('100%')
        .margin({ bottom: 8 })

      Text(body)
        .fontSize(14)
        .fontColor(this.getThemeColors().secondaryText)
        .width('100%')
        .lineHeight(22)
    }
    .width('100%')
    .margin({ bottom: 24 })
  }
}
