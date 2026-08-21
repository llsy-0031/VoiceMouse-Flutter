#!/bin/bash
# VoiceMouse macOS 安装包构建脚本
# 产物：VoiceMouse-<ver>-macos-arm64.dmg 或 .pkg
# 前置条件：在 macOS 上运行，已安装 Xcode Command Line Tools 和 create-dmg（可选）

set -e

VERSION="1.0.3"
APP_NAME="VoiceMouse"
APP_BUNDLE="build/macos/Build/Products/Release/${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${VERSION}-macos-arm64.dmg"
PKG_NAME="${APP_NAME}-${VERSION}-macos-arm64.pkg"

echo "[1/5] 清理旧产物..."
rm -rf "build/${DMG_NAME}" "build/${PKG_NAME}"

echo "[2/5] 安装依赖..."
flutter pub get

echo "[3/5] 构建 macOS Release..."
flutter build macos --release

echo "[4/5] ad-hoc 签名..."
codesign --force --deep --sign - "${APP_BUNDLE}"
codesign --verify --deep --strict "${APP_BUNDLE}"

echo "[5/5] 打包 DMG..."
if command -v create-dmg &> /dev/null; then
    create-dmg \
        --volname "${APP_NAME} ${VERSION}" \
        --window-size 600 400 \
        --icon-size 100 \
        --app-drop-link 450 180 \
        --icon "${APP_NAME}.app" 150 180 \
        "build/${DMG_NAME}" \
        "${APP_BUNDLE}"
else
    echo "create-dmg 未安装，改用 pkgbuild 生成 .pkg"
    pkgbuild --install-location /Applications \
        --component "${APP_BUNDLE}" \
        "build/${PKG_NAME}"
fi

echo "完成：build/${DMG_NAME} 或 build/${PKG_NAME}"
