# 文档整理

一个基于 Swift + AppKit 的 macOS 桌面文件整理应用。它以独立菜单栏应用运行，保留可自由摆放的 AppKit 文件管理面板，并通过 WidgetKit 在桌面显示整理目录摘要。

## 当前能力

- 多个独立面板，支持桌面层与悬浮置顶模式
- 文件和文件夹图标网格、拖拽排序、搜索、打开、Finder 定位和快速预览
- 面板尺寸、位置、列数和位置锁定设置
- 桌面使用 WidgetKit 原生系统小组件显示整理目录摘要，跟随 macOS 的 Clear/Tinted/Full Color 外观；点击后打开完整 AppKit 文件管理面板
- 面板使用 macOS 语义色和原生 Popover 悬浮材质，随系统浅色/深色外观切换
- 菜单栏入口、全局显示/隐藏快捷键和登录启动选项
- 面板配置持久化
- 自动收纳状态反馈、文件操作历史、重命名和撤销恢复

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
- 右键文件可重命名或恢复原位置；菜单栏和面板菜单均可打开“收纳记录与恢复”
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
- PanelToolbarView.swift、PanelEmptyStateView.swift：独立的界面组件
- PanelDropController.swift、PanelContextMenuController.swift：拖放和右键交互
- PanelFileActionCoordinator.swift：文件选择、收纳、重命名和恢复入口
- FileOperationJournal.swift：文件操作写前日志、状态持久化和异常恢复
- FileActivityWindowController.swift：操作历史、状态反馈和恢复界面

视图层不直接执行文件移动；文件操作统一经过 AppStore 和 FileOperationService。面板配置通过 PanelStateRepository 持久化，文件操作日志由 FileOperationService 管理。桌面自动收纳由 DesktopIntakeCoordinator 编排，AppDelegate 不负责文件筛选和移动流程。

## 构建

构建需要 macOS、Swift 编译器和 Xcode Command Line Tools；若要使用免费 Personal Team 的 Apple Development 签名，还需要安装完整 Xcode 并在 Accounts 中登录 Apple Account。

默认构建 Universal Binary（Apple Silicon + Intel），最低系统版本从 `Info.plist` 的 `LSMinimumSystemVersion` 读取：

```bash
./build.sh
```

只构建单一架构：

```bash
ARCHS=arm64 ./build.sh
ARCHS=x86_64 ./build.sh
```

构建脚本先在临时目录完成编译、签名和校验，成功后才替换旧的 `build/文档整理.app`。因此编译失败不会先删除现有应用。

默认使用 Ad-hoc 签名，仅用于本机预览；此时不能据此验收主应用与 WidgetKit 的 App Group 数据共享。

**免费 Apple Account 本机签名：**

1. 安装完整 Xcode，在 Xcode > Settings > Accounts 中添加自己的 Apple Account。
2. 选择 Personal Team，并在 Manage Certificates 中创建 Apple Development 证书。
3. 从 Xcode 账户信息取得 Team ID；在终端执行 `security find-identity -v -p codesigning`，确认 Apple Development 身份已出现在钥匙串。
4. 使用同一个 Team ID 和 Apple Development 身份构建：

```bash
TEAM_ID="<你的10位Team ID>" \
CODESIGN_IDENTITY="Apple Development: <证书名称> (<你的10位Team ID>)" \
./build.sh
```

构建脚本会为主应用和 Widget Extension 写入相同的 macOS App Group 标识：`<Team ID>.com.covet.DesktopFolderWidget`。这种 macOS 团队 ID 前缀形式不需要在开发者网站注册 App Group，也不需要为该 App Group 单独配置预置描述文件；签名代码的 Team ID 必须与标识前缀一致。参见 [Apple：Accessing app group containers](https://developer.apple.com/documentation/xcode/accessing-app-group-containers)。

该方案仅用于自己的 Mac 本机开发和使用，不提供 App Store 上架、Developer ID 分发或公证能力。签名身份必须存在于当前 Mac 的钥匙串中。

## 测试

- test.sh：运行 AppStore、PanelStateRepository、FileOperationService 以及 WidgetSnapshot 数据测试；均使用临时目录
- `./snapshot.sh`：会创建 UI 窗口并在 `/tmp` 写入截图
- `./feature_tests.sh`：包含 Quick Look 窗口和全局快捷键测试，不适合在用户正在工作的桌面上无提示执行

## 版本与平台

- Bundle ID：`com.covet.DesktopFolderWidget`
- 最低 macOS 版本：以 `Info.plist` 为准
- 版本号：`CFBundleShortVersionString`
- 构建号：`CFBundleVersion`

## WidgetKit + AppKit 双层模式

- 在 macOS 27 桌面编辑小组件中添加「文档整理」，提供小、中、大三种尺寸；WidgetKit 小组件的刷新由系统调度，不保证逐秒实时
- 小组件只读取主应用写入共享 App Group 的文件名与计数摘要；不直接移动、删除或访问原始文件
- 点击小组件打开交互式 AppKit 面板；历史自动收纳、文件恢复、拖放与搜索逻辑不变
- 在菜单栏「文档整理」中选择「显示/隐藏全部面板」可以隐藏旧桌面面板，避免与 WidgetKit 小组件叠放
- 主应用和 Widget Extension 通过 App Group 共享摘要文件；免费 Personal Team 本机开发使用 macOS 团队 ID 前缀标识 `<Team ID>.com.covet.DesktopFolderWidget`。Ad-hoc 签名只用于预览，不能作为共享容器验收依据；必须使用同一 Personal Team 的 Apple Development 身份签署两个 bundle
