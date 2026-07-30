#!/bin/bash
# 一键编译脚本：支持 rootful / roothide / rootless 三版本

echo ">>> 清理旧文件..."
make clean

echo ">>> 正在编译 Rootful (有根) 版本..."
make package

echo ">>> 正在编译 Roothide (隐藏越狱) 版本..."
make package THEOS_PACKAGE_SCHEME=roothide

echo ">>> 正在编译 Rootless (无根) 版本..."
make package THEOS_PACKAGE_SCHEME=rootless

echo ">>> 编译完成！三版本已生成到 packages/ 目录。"
