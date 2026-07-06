@Entry
@Component
struct Index {
  @Provide('navPathStack') pathStack: NavPathStack = new NavPathStack()

  build() {
    Navigation(this.pathStack) {
    }
    .onAppear(() => {
      this.pathStack.pushPathByName('Layout', null, false);
    })
    .hideNavBar(true)
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
  }
}
