# GesturePro

[English](README.md)

给 iPhone 的操作按钮增加单击、双击和长按手势，每个手势都可以单独选择系统动作。

设置界面直接接在系统原生的“操作按钮”页面上，动作列表也是系统自己的，包括“无”。手电筒、静音模式、快捷指令、相机等原生动作都可以照常使用。

## 功能

- 单击、双击、长按分别设置动作
- 可选的方向模式
- 支持屏幕朝上、屏幕朝下、竖直、倒立、向左横放和向右横放
- 开启方向模式后最多可以保存 18 个动作
- 某个方向没有单独设置时，跟随同一手势的竖直动作
- 关闭方向模式不会清除已经保存的方向配置
- 支持简体中文、繁体中文、英文、越南语和阿拉伯语

## 使用

安装后打开：

```text
设置 > 操作按钮
```

页面右上角可以切换单击、双击和长按。旁边的方向菜单用于开启方向模式和选择当前要编辑的方向。

选择手势或方向后，直接在下面的系统动作列表里设置即可。

## 安装包

`releases.sh` 会在 `packages/` 目录生成三个包：

| 文件 | 越狱环境 |
| --- | --- |
| `GesturePro_0.0-3-arm.deb` | rootful |
| `GesturePro_0.0-3-arm64.deb` | rootless |
| `GesturePro_0.0-3-arm64e.deb` | RootHide |

需要一台带操作按钮的 iPhone，系统版本为 iOS 17 或更高。

## 构建

一次生成三个安装包：

```sh
./releases.sh
```

单独构建：

```sh
# rootful
make package FINALPACKAGE=1

# rootless
make package SCHEME=rootless FINALPACKAGE=1

# RootHide
make package SCHEME=roothide FINALPACKAGE=1
```
