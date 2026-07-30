# GesturePro

iOS 状态栏手势插件，支持在状态栏左/灵动岛/右三个区域独立配置手势动作。

## 功能

- 状态栏左侧区域：单击、双击、长按、左滑、右滑
- 灵动岛区域：单击、双击、长按、左滑、右滑
- 状态栏右侧区域：单击、双击、长按、左滑、右滑
- 共 15 个独立可配置手势
- 支持动作：截图、锁屏、主屏幕、多任务切换、控制中心、通知中心、手电筒、静音切换、Siri、旋转锁定、打开 App、快捷指令、Shell 命令、注销、安全模式、重启
- 使用 PreferenceLoader 独立设置面板
- 支持 iOS 16+ / Dopamine Rootless / arm64

## 使用

安装后打开：

```text
设置 → GesturePro
```

开启"启用插件"，然后为每个区域的手势选择绑定的动作。

## 兼容性

- iOS 16.0 - 16.x
- Dopamine 2 Rootless
- arm64 / arm64e
- iPhone 14 Pro 及有状态栏的设备

## 构建

```sh
# rootless (Dopamine / 无根)
make package THEOS_PACKAGE_SCHEME=rootless

# roothide (隐藏越狱)
make package THEOS_PACKAGE_SCHEME=roothide

# rootful (有根)
make package

# 一键编译三版本
./build.sh
```

## 安装包

| 文件 | 越狱环境 |
| --- | --- |
| `com.axs.gesturepro_*_iphoneos-arm.deb` | rootful |
| `com.axs.gesturepro_*_iphoneos-arm64.deb` | rootless |
| `com.axs.gesturepro_*_iphoneos-arm64e.deb` | RootHide |

## v6.0 重构说明

此版本将 GesturePro 从 iOS 17 操作按钮插件完全重写为 iOS 16 通用状态栏手势插件。旧版操作按钮功能不再保留。
