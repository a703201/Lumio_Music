# HM Music

<img width="200" height="200" alt="logo" src="https://github.com/user-attachments/assets/bec472ea-0320-4c85-85a5-1c898d9d9aee" />

一款简洁的本地音乐播放器，运行在 HarmonyOS 平台，基于 ArkTS + ArkUI + C++ Native 开发。

## 功能特性

- 本地音乐文件扫描与导入
- 音乐播放控制（播放/暂停/上一首/下一首）
- 播放模式切换（顺序/列表循环/单曲循环）
- 歌曲收藏与播放历史记录
- 搜索功能
- 播放器页面（封面显示、歌词显示）
- 迷你播放器（底栏显示当前播放歌曲）
- 多页面导航与交互动效

## 技术栈

- **前端框架**: ArkTS + ArkUI
- **原生模块**: C++ (NAPI)
- **开发工具**: DevEco Studio
- **目标平台**: HarmonyOS NEXT (API 12+)

## 项目结构

```
entry/src/main/
├── ets/
│   ├── pages/          # 页面组件
│   │   ├── Index.ets       # 入口页面
│   │   ├── Layout.ets      # 主布局（Tab栏+迷你播放器）
│   │   ├── Songs.ets       # 歌曲列表
│   │   ├── Moment.ets      # 音乐库
│   │   ├── Mine.ets        # 个人中心
│   │   ├── PlayerPage.ets  # 播放器页面
│   │   ├── Settings.ets    # 设置
│   │   ├── About.ets       # 关于
│   │   ├── Favorites.ets   # 收藏列表
│   │   ├── PlayHistory.ets # 播放历史
│   │   └── LocalLibrary.ets# 本地音乐库
│   ├── components/     # 通用组件
│   ├── services/       # 服务层
│   ├── models/         # 数据模型
│   └── utils/          # 工具类
└── cpp/                # C++ 原生模块
```

## 已知问题

- **音频播放功能异常**: 目前软件无法正常播放音频文件，AudioRendererController 的播放逻辑需要进一步调试和完善
- 部分音频格式可能不支持
- 歌词显示功能尚未完全实现

## 更新日志

### v2.0 (2026-07-05)

#### 新增
- 迷你播放器：底部显示当前播放歌曲，点击进入播放器页面
- 播放器页面入场/退场动画
- 页面交互动效：
  - 列表项交错入场动画
  - 按压缩放反馈
  - 空状态图标脉冲动画
  - Tab栏切换弹跳动画
  - 头像呼吸灯效果
  - 数字滚动统计动画
- 音乐库统计面板（歌曲数/收藏数/最近播放数）
- 分类文件夹彩色图标
- 歌曲序号显示
- 播放中歌曲高亮状态
- 扫描进度条
- 关于页面功能特色展示

#### 优化
- 整体UI视觉升级：
  - 统一圆角风格（14-16px）
  - 彩色图标容器
  - 徽章式计数显示
  - 分组标题设计
- 各页面头部统一为20px粗体标题
- 返回按钮按压缩放效果
- 设置页面分组优化
- 版本号更新至 2.0

#### 修复
- C++ 编译 duplicate symbol 错误（拆分 audio_metadata.h/.cpp）
- ArkTS Object.assign 受限问题（改用手动属性赋值）
- main_pages.json 中非 @Entry 页面注册错误

### v1.1.0

#### 新增
- 基础音乐播放功能框架
- 歌曲列表展示
- 音乐文件扫描与导入
- 收藏功能
- 播放历史记录
- 播放模式切换
- 设置页面
- 关于页面

#### 技术
- ArkTS + ArkUI 开发
- C++ Native 模块（音频元数据解析）
- Navigation + NavPathStack 页面路由

## 构建

```bash
# 使用 DevEco Studio 打开项目
# 选择 Build > Build Hap(s)/APP(s) > Build Hap(s)
# 或使用命令行：
hvigorw assembleHap --mode module -p module=entry@default -p product=default -p buildMode=release
```

## 许可

仅供学习交流使用。
