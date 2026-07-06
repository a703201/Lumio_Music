@Builder
export function AboutBuilder() {
  About()
}

@Component
struct About {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('topHeight') topHeight: number = 0;

  @State logoScale: number = 0.5;
  @State logoOpacity: number = 0;
  @State titleOpacity: number = 0;
  @State subtitleOpacity: number = 0;
  @State itemScales: number[] = [1.0, 1.0, 1.0, 1.0];
  @State featureScales: number[] = [0.9, 0.9, 0.9];
  @State featureOpacities: number[] = [0, 0, 0];

  aboutToAppear(): void {
    setTimeout(() => {
      this.logoScale = 1.0;
      this.logoOpacity = 1.0;
    }, 100);
    setTimeout(() => {
      this.titleOpacity = 1.0;
    }, 300);
    setTimeout(() => {
      this.subtitleOpacity = 1.0;
    }, 400);
    // Feature cards animation
    for (let i = 0; i < 3; i++) {
      setTimeout(() => {
        let newScales = [...this.featureScales];
        let newOpacities = [...this.featureOpacities];
        newScales[i] = 1.0;
        newOpacities[i] = 1.0;
        this.featureScales = newScales;
        this.featureOpacities = newOpacities;
      }, 600 + i * 100);
    }
  }

  build() {
    NavDestination() {
      Scroll() {
        Column() {
          // Header section
          Column() {
            Image($r('app.media.logo'))
              .width(108)
              .height(108)
              .borderRadius(24)
              .shadow({
                radius: 16,
                color: 'rgba(250, 39, 89, 0.2)',
                offsetX: 0,
                offsetY: 8
              })
              .scale({ x: this.logoScale, y: this.logoScale })
              .opacity(this.logoOpacity)
              .animation({
                duration: 600,
                curve: Curve.EaseOut,
              })

            Text('HM_Music')
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1C1C1E')
              .margin({ top: 20, bottom: 6 })
              .opacity(this.titleOpacity)
              .transition(TransitionEffect.translate({ y: 10 }))
              .animation({ duration: 400, curve: Curve.EaseOut })

            Text('本地音乐播放器')
              .fontSize(15)
              .fontColor('#8E8E93')
              .opacity(this.subtitleOpacity)
              .transition(TransitionEffect.translate({ y: 10 }))
              .animation({ duration: 400, curve: Curve.EaseOut })
          }
          .width('100%')
          .padding({ top: this.topHeight + 48, bottom: 36 })
          .backgroundColor('#FAFAFA')

          // Features section
          Text('功能特色')
            .fontSize(13)
            .fontColor('#8E8E93')
            .width('100%')
            .padding({ left: 20, bottom: 12 })

          Row() {
            Column() {
              Text('🎵')
                .fontSize(28)
                .margin({ bottom: 8 })
              Text('本地播放')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#1C1C1E')
            }
            .layoutWeight(1)
            .scale({ x: this.featureScales[0], y: this.featureScales[0] })
            .opacity(this.featureOpacities[0])
            .animation({ duration: 400, curve: Curve.EaseOut })

            Column() {
              Text('🔍')
                .fontSize(28)
                .margin({ bottom: 8 })
              Text('文件扫描')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#1C1C1E')
            }
            .layoutWeight(1)
            .scale({ x: this.featureScales[1], y: this.featureScales[1] })
            .opacity(this.featureOpacities[1])
            .animation({ duration: 400, curve: Curve.EaseOut })

            Column() {
              Text('📝')
                .fontSize(28)
                .margin({ bottom: 8 })
              Text('歌词显示')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#1C1C1E')
            }
            .layoutWeight(1)
            .scale({ x: this.featureScales[2], y: this.featureScales[2] })
            .opacity(this.featureOpacities[2])
            .animation({ duration: 400, curve: Curve.EaseOut })
          }
          .width('100%')
          .padding({ left: 24, right: 24, top: 12, bottom: 24 })
          .justifyContent(FlexAlign.SpaceAround)

          // Info section
          Text('应用信息')
            .fontSize(13)
            .fontColor('#8E8E93')
            .width('100%')
            .padding({ left: 20, bottom: 12 })

          Column() {
            this.buildAboutItem('应用版本', '2.0', 0)
            this.buildAboutItem('开发者', 'Lumio', 1)
            this.buildAboutItem('技术支持', 'HarmonyOS SDK', 2)
            this.buildAboutItem('架构', 'ArkTS + C++ Native', 3)
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          Text('一款简洁的本地音乐播放器，支持扫描设备音频文件、播放控制、歌词显示等功能。')
            .fontSize(14)
            .fontColor('#636366')
            .textAlign(TextAlign.Center)
            .width('100%')
            .margin({ top: 32, bottom: 40 })
            .padding({ left: 30, right: 30 })
            .transition(TransitionEffect.OPACITY)
            .animation({ duration: 500, curve: Curve.EaseOut, delay: 800 })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .backgroundColor(Color.White)
    }
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
    .hideTitleBar(true)
  }

  @Builder
  buildAboutItem(label: string, value: string, index: number) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor('#8E8E93')
        .layoutWeight(1)
        .textAlign(TextAlign.Start)

      Text(value)
        .fontSize(15)
        .fontColor('#1C1C1E')
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor('#F2F2F7')
    .borderRadius(14)
    .margin({ bottom: 2 })
    .scale({ x: this.itemScales[index] ?? 1.0, y: this.itemScales[index] ?? 1.0 })
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 })))
    .animation({ duration: 300, curve: Curve.EaseOut, delay: 500 + index * 80 })
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
}
