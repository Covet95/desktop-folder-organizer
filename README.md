# 文档整理

一个基于 Swift + AppKit 的 macOS 个人桌面文件整理应用。它以独立菜单栏应用运行，提供可自由摆放的 AppKit 文件管理面板。原生 WidgetKit 系统小组件未能在桌面图库完成验收，已从本机使用版中移除；此前实验保留在 Git 历史及标签 `widgetkit-experiment-v0.2.9`。

## 当前能力

- 多个独立面板，支持桌面层与悬浮置顶模式
- 文件和文件夹图标网格、拖拽排序、搜索、打开、Finder 定位、复制文件地址和快速预览
- 面板按文件类型分区显示（文件夹、图片、文档、表格、演示文稿、视频、音频、压缩包、代码、其他）；可在「面板设置」关闭分区显示。分组仅改变视觉布局，不会更改磁盘路径；分组内支持拖拽调整顺序，关闭分组后仍保留原平铺排序
- 面板 UI 使用 macOS 原生玻璃和 SF 系统字体：文件名 12 pt、分类标题 13 pt、设置标题 16 pt；较窄的面板会适当减少实际显示列数，优先保证文件名可读。工具栏保留文件数和原生搜索、添加及设置入口
- 面板尺寸、位置、列数和位置锁定设置；未锁定时支持鼠标悬停面板右下角拖拽调整尺寸
- 面板使用 macOS 语义色和原生 Popover 悬浮材质，支持跟随系统或单独设置浅色/深色外观
- 菜单栏入口、全局显示/隐藏快捷键、登录启动选项和手动检查 GitHub Releases 更新（支持 SHA-256 校验与一键替换重启）
- 面板配置持久化
- 自动收纳状态反馈、文件操作历史、重命名和撤销恢复

## 界面设计原则

- **原生外观**：桌面层级使用 macOS 的 NSGlassEffectView Clear 材质，悬浮置顶模式使用 Regular 材质增强复杂背景下的文字对比度；配合语义文字颜色，不手工模拟玻璃色块。
- **系统字体层级**：使用系统 SF 字体。工具栏和分类标题约 13 pt，文件名 12 pt（至多两行，完整名称可在悬停提示中查看），设置标题 16 pt、设置正文 13 pt；操作记录约 12–15 pt。
- **适配式文件网格**：保留「每行最多图标」用户设置；窄面板自动减少实际显示列数。分类分隔线和辅助数字采用系统语义色。
- **不改文件行为**：只调整 AppKit 视图及文字排版，自动收纳、文件路径、恢复操作、配置存储与拖拽业务保持不变。
- **设计参考**：[DockDoor](https://github.com/ejbills/DockDoor)、[Shelf](https://github.com/f/shelf)、[Layby](https://github.com/gonnabeafreeman/Layby)。仅借鉴原生视觉原则，没有引入第三方 UI 依赖或复制其源码。

## 文件行为与数据位置

**注意：当前版本采用移动文件的收纳方式，不是创建快捷方式或复制文件。**

- 启动后自动扫描桌面上已有的可见项目，并在文件稳定后移动到 ~/Documents/文档整理/
- 运行期间持续监控桌面，新项目通过相同的稳定性检测后自动收纳
- 使用 FSEvents 发现桌面变化；文件大小、修改时间或文件资源标识变化会重置 0.5 秒静默窗口
- 收纳失败不会被标记为完成：按 2、4、8 秒递增退避重试，最长间隔 60 秒；桌面暂时不可读取时监控继续运行
- 常见下载临时扩展名 .download、.crdownload 和 .part 不会被收纳
- 从面板选择或拖入外部文件时，同样会移动原文件
- 面板中的“移除”只移除面板引用，不删除磁盘上的文件；收纳目录内的文件会在下次目录同步时重新出现
- 启动时校对收纳目录第一层可见项目；目录新增、删除或重命名后同步更新面板，保留现有面板排序及外部引用
- 面板布局和文件引用保存在 `~/Library/Application Support/DesktopFolderWidget/panels.json`
- 面板配置损坏、无法读取或版本不兼容时，保留原文件并阻止默认配置覆盖；菜单栏显示恢复警告
- 文件操作日志保存在同目录的 file-operations.json，记录自动收纳、手动收纳和重命名
- 文件移动采用写前日志：先持久化原路径与目标路径，再执行移动，最后提交完成状态
- 应用异常退出后会核对原位置、目标位置和恢复目标，自动补全能够确定的操作；无法确定时标记为需要检查
- 右键文件可复制文件地址（`⌥⌘C` 悬停快捷键）、重命名或恢复原位置；菜单栏和面板菜单均可打开“收纳记录与恢复”
- 恢复时校验文件身份；原位置重名会生成“恢复副本”，不会覆盖已有文件
- 重命名会修改磁盘上的实际文件名，并同步更新所有面板引用
- 自动收纳失败会显示等待重试状态；菜单栏图标和提示文本同步反映监控、处理中及异常状态
- 用户主动恢复到桌面的文件会被监控器标记为已处理，避免立即再次自动收纳
- 退出应用时会先停止新监控事件，等待已提交的文件操作及面板回调完成，再保存配置并退出

当前产品采用自动收纳模式。用户应在使用前了解：桌面项目会被移动，而不是复制；重名项目会在目标目录中自动追加序号。

## 界面与业务结构

- AppDelegate.swift：应用生命周期、菜单、全局快捷键和面板窗口同步
- DesktopIntakeCoordinator.swift：桌面自动收纳和收纳目录的显示同步
- DesktopWatcher.swift：文件稳定性检测、重复识别和失败退避重试
- AppStore.swift：应用级面板状态、持久化与文件操作的协调门面
- PanelStateRepository.swift：面板配置仓储契约、JSON 编解码、版本检查和损坏数据保护
- FileOperationService.swift：独立执行串行文件移动、重命名、恢复及操作日志协调
- PanelStore.swift：单个面板配置、搜索状态和条目操作
- PanelView.swift：面板视图组合、外观、布局和键鼠交互
- PanelToolbarView.swift、PanelEmptyStateView.swift、PanelSectionHeaderView.swift：独立的界面组件
- PanelDropController.swift、PanelContextMenuController.swift：拖放和右键交互
- PanelFileActionCoordinator.swift：文件选择、收纳、重命名和恢复入口
- FileOperationJournal.swift：文件操作写前日志、状态持久化和异常恢复
- FileActivityWindowController.swift：操作历史、状态反馈和恢复界面
- AppUpdateService.swift、AppUpdateController.swift：轻量原生 GitHub Releases 在线检查更新、SHA-256 校验与安装重启流程

视图层不直接执行文件移动；文件操作统一经过 AppStore 和 FileOperationService。面板配置通过 PanelStateRepository 持久化，文件操作日志由 FileOperationService 管理。桌面自动收纳由 DesktopIntakeCoordinator 编排，AppDelegate 不负责文件筛选和移动流程。

## 构建

构建需要 macOS、Swift 编译器和 Xcode Command Line Tools（或完整 Xcode）。当前只构建 AppKit 主应用，不需要 WidgetKit Extension、App Group 或单独的 Xcode 小组件工程。

```bash
./build.sh
```

默认构建 Apple Silicon `arm64`；只有需要兼容 Intel 时才运行：

```bash
ARCHS=universal ./build.sh
```

如需用现有免费 Apple Development 证书进行本机签名，可指定钥匙串中的身份：

```bash
CODESIGN_IDENTITY="<钥匙串中可用的 Apple Development 身份>" ./build.sh
```

不指定签名身份时使用 Ad-hoc 签名，供本机调试。构建脚本先编译、签名、验证，再替换 `build/文档整理.app`，失败时保留原构建产物。

## 测试

- `./test.sh`：运行 AppStore、PanelStateRepository、FileOperationService、CopyPathTests 和 AppUpdateServiceTests 测试；均使用临时目录、模拟网络与独立剪贴板
- `./snapshot.sh`：会创建 UI 窗口并在 `/tmp` 写入截图
- `./feature_tests.sh`：包含 Quick Look 窗口和全局快捷键测试，不适合在用户正在工作的桌面上无提示执行

## 版本与平台

- 当前版本：`0.2.17`（构建号 `30`）
- Bundle ID：`com.covet.DesktopFolderWidget`
- 最低 macOS 版本：以 `Info.plist` 为准
- 版本号：`CFBundleShortVersionString`
- 构建号：`CFBundleVersion`

## 本机使用范围

- 本版本使用可拖动的 AppKit 桌面整理面板和菜单栏入口，不会出现在 macOS「编辑小组件」系统图库
- 文件整理、恢复日志和面板配置的数据目录沿用原位置，不做迁移
- WidgetKit 试验工程、专用 URL Scheme、App Group 权限和摘要发布逻辑已退役；可从 Git 历史恢复，不影响现有 AppKit 功能
