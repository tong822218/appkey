# AppKey

AppKey 是一个仅保留 Manico 核心能力的 macOS 菜单栏 App：把指定 App 绑定到全局快捷键，并按当前状态执行启动、激活或隐藏。

## 功能

- 支持 `A–Z`、`0–9`、`F1–F12`，快捷键必须包含 `Control`、`Command` 或 `Option`。
- 同一路径只能绑定一次，同一快捷键只能分配给一个 App。
- App 未运行时启动，已运行时重新唤醒（包括恢复已关闭的窗口），已经位于前台时隐藏。
- 以安装路径识别运行实例；Bundle ID 只在目标路径仍存在且运行实例唯一时回退使用。
- 缺失 App 的绑定不会删除，也不会自动替换；管理窗口会提供“重新选择”。
- 配置保存在 `~/Library/Application Support/AppKey/bindings.json`。
- 默认尝试注册为登录项；需要 macOS 批准时会显示入口。

AppKey 使用 Carbon `RegisterEventHotKey`，不监听普通键盘输入，不需要辅助功能或输入监控权限。

## 构建与测试

要求 Xcode 26 或更新版本，目标为 Apple Silicon、macOS 15.2 或更新版本。

```sh
xcodebuild test \
  -project AppKey.xcodeproj \
  -scheme AppKey \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO

xcodebuild build \
  -project AppKey.xcodeproj \
  -scheme AppKey \
  -configuration Release \
  -derivedDataPath .build/ReleaseDerivedData
```

Release App 位于 `.build/ReleaseDerivedData/Build/Products/Release/AppKey.app`。开发迁移工具是独立目标，不会被包含进 AppKey.app。

## Manico 一次性迁移

先退出 Manico，再针对 `Manico.sqlite` 的副本执行：

```sh
xcodebuild build \
  -project AppKey.xcodeproj \
  -scheme AppKeyMigrate \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO

.build/DerivedData/Build/Products/Debug/AppKeyMigrate \
  --source /path/to/Manico.sqlite
```

工具只读打开 Manico 数据库。若 AppKey 配置已经存在，会先在同目录生成带时间戳的备份；空快捷键、`keyCode=65535`、缓存目录 Updater、重复项和无法解析项会被跳过。

## 当前范围

第一版不包含 Dock/切换器模式、悬浮启动栏、多配置、外观定制、用量统计、云同步、窗口循环、自动更新或 App Store 分发。
