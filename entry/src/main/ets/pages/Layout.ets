import { Mine } from "./Mine"
import { Moment } from "./Moment"
import { Songs } from "./Songs"
import { MusicStore } from "../services/MusicStore"
import { SongItem } from "../models/music"

interface TabClass{
  text:string
  icon:ResourceStr
}

@Builder
export function LayoutBuilder(){
  Layout()
}

@Component
struct Layout{
  @State currentIndex: number = 0
  @State tabScale: number[] = [1.0, 1.0, 1.0]
  @State tabBarOffset: number = 100
  @State miniPlayerOffset: number = 80
  @State coverRotation: number = 0
  @State progressWidth: number = 0
  @StorageLink('isPlay') isPlaying: boolean = false
  @StorageLink('songList') songList: SongItem[] = []
  @StorageLink('selectIndex') selectIndex: number = 0
  @StorageLink('progress') progress: number = 0
  @StorageLink('progressMax') progressMax: number = 1
  @StorageProp('topHeight') topHeight: number = 0
  @StorageProp('bottomHeight') bottomHeight: number = 0
  @Consume('navPathStack') pathStack: NavPathStack;
  store: MusicStore = MusicStore.getInstance()
  private rotateInterval: number = -1;

  aboutToAppear(): void {
    setTimeout(() => {
      this.tabBarOffset = 0;
      this.miniPlayerOffset = 0;
    }, 200);
    this.rotateInterval = setInterval(() => {
      if (this.isPlaying) {
        this.coverRotation = (this.coverRotation + 2) % 360;
      }
    }, 50);
  }

  aboutToDisappear(): void {
    if (this.rotateInterval >= 0) {
      clearInterval(this.rotateInterval);
    }
  }

  tabData:TabClass[] = [
    {text:'歌曲',icon:$r('app.media.ic_recommend')},
    {text:'音乐库',icon:$r('app.media.ic_moment')},
    {text:'我的',icon:$r('app.media.ic_mine')}
  ]

  @Builder tabBuilder (item:TabClass, index:number) {
    Column({space : 4}){
      Image(item.icon)
        .width(22)
        .fillColor(this.currentIndex === index ? '#FA2759':'#8E8E93')
        .scale({ x: this.tabScale[index], y: this.tabScale[index] })
      Text(item.text)
        .fontSize(11)
        .fontColor(this.currentIndex === index ? '#FA2759':'#8E8E93')
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
    }
    .width(64)
    .height(44)
    .justifyContent(FlexAlign.Center)
  }

  build(){
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Tabs({ barPosition : BarPosition.End, index: this.currentIndex }){
          TabContent() {
            Songs()
          }
          .tabBar(this.tabBuilder(this.tabData[0], 0))

          TabContent() {
            Moment()
          }
          .tabBar(this.tabBuilder(this.tabData[1], 1))

          TabContent() {
            Mine()
          }
          .tabBar(this.tabBuilder(this.tabData[2], 2))
        }
        .onChange((index:number) => {
          const prev = this.currentIndex;
          this.currentIndex = index;
          let oldScales = [...this.tabScale];
          oldScales[prev] = 1.0;
          this.tabScale = oldScales;
          let newScales = [...this.tabScale];
          newScales[index] = 1.3;
          this.tabScale = newScales;
          setTimeout(() => {
            let resetScales = [...this.tabScale];
            resetScales[index] = 1.0;
            this.tabScale = resetScales;
          }, 150);
        })
        .barMode(BarMode.Fixed)
        .barWidth('100%')
        .barHeight(0)
        .scrollable(false)
        .width('100%')
        .height('100%')

        // Mini player bar
        if (this.songList.length > 0) {
          Column() {
            Row() {
              // Album cover with rotation when playing
              Stack() {
                Image(this.songList[this.selectIndex].getLabel())
                  .width(44)
                  .height(44)
                  .borderRadius(this.isPlaying ? 22 : 8)
                  .clip(true)
                  .rotate({ angle: this.isPlaying ? this.coverRotation : 0 })
                  .animation({ duration: 50, curve: Curve.Linear })
                  .shadow({
                    radius: 6,
                    color: 'rgba(0, 0, 0, 0.15)',
                    offsetX: 0,
                    offsetY: 2
                  })
              }
              .width(44)
              .height(44)

              // Song info
              Column() {
                Text(this.songList[this.selectIndex].title)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#1C1C1E')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Text(this.songList[this.selectIndex].singer)
                  .fontSize(12)
                  .fontColor('#8E8E93')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 2 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 12 })

              // Play/Pause button
              Image(this.isPlaying ? $r('app.media.ic_pause') : $r('app.media.ic_play'))
                .width(32)
                .height(32)
                .fillColor('#FA2759')
                .padding(2)
                .animation({ duration: 120, curve: Curve.EaseOut })
                .onClick(() => {
                  this.isPlaying = !this.isPlaying;
                })
            }
            .width('100%')
            .height(64)
            .padding({ left: 14, right: 14 })

            // Progress bar
            Row() {
              Text('')
                .width(`${this.progressMax > 0 ? (this.progress / this.progressMax) * 100 : 0}%`)
                .height(2)
                .backgroundColor('#FA2759')
                .borderRadius(1)
            }
            .width('100%')
            .height(2)
            .backgroundColor('#E5E5EA')
          }
          .width('100%')
          .backgroundColor('#F2F2F7')
          .borderRadius(16)
          .margin({ left: 16, right: 16, bottom: this.bottomHeight + 76 })
          .shadow({
            radius: 12,
            color: 'rgba(0, 0, 0, 0.1)',
            offsetX: 0,
            offsetY: 4
          })
          .translate({ y: this.miniPlayerOffset })
          .animation({ duration: 400, curve: Curve.EaseOut })
          .onClick(() => {
            this.pathStack.pushPathByName('PlayerPage', null);
          })
        }

        // Tab bar
        Row() {
          ForEach(this.tabData, (item: TabClass, index: number) => {
            Column({space: 4}) {
              Image(item.icon)
                .width(22)
                .fillColor(this.currentIndex === index ? '#FA2759' : '#8E8E93')
                .scale({ x: this.tabScale[index], y: this.tabScale[index] })
              Text(item.text)
                .fontSize(11)
                .fontColor(this.currentIndex === index ? '#FA2759' : '#8E8E93')
                .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
            }
            .width(64)
            .height(44)
            .justifyContent(FlexAlign.Center)
            .animation({ duration: 150, curve: Curve.EaseInOut })
            .onClick(() => {
              this.currentIndex = index;
            })
          })
        }
        .width('85%')
        .height(52)
        .backgroundColor(Color.White)
        .borderRadius(26)
        .shadow({
          radius: 12,
          color: 'rgba(0, 0, 0, 0.08)',
          offsetX: 0,
          offsetY: 4
        })
        .justifyContent(FlexAlign.SpaceEvenly)
        .margin({ bottom: this.bottomHeight + 20 })
        .translate({ y: this.tabBarOffset })
        .animation({ duration: 400, curve: Curve.EaseOut })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.White)
    }
    .hideTitleBar(true)
  }
}
