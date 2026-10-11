#!/bin/bash
# 打包 QuotaDeck 为 .app(菜单栏应用,无 Dock 图标)
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> swift build -c release"
swift build -c release

BIN=.build/release/QuotaDeck
APP=build/QuotaDeck.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp "$BIN" "$APP/Contents/MacOS/QuotaDeck"
chmod +x "$APP/Contents/MacOS/QuotaDeck"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>QuotaDeck</string>
    <key>CFBundleDisplayName</key>     <string>QuotaDeck</string>
    <key>CFBundleIdentifier</key>      <string>com.damien.quotadeck</string>
    <key>CFBundleVersion</key>         <string>0.1.0</string>
    <key>CFBundleShortVersionString</key> <string>0.1.0</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>QuotaDeck</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
EOF

echo "==> 完成: $APP"
echo "    安装到 ~/Applications: cp -R $APP ~/Applications/"
echo "    运行: open $APP"
