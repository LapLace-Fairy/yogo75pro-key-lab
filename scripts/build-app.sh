#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"
configuration=${YOGO_BUILD_CONFIGURATION:-release}
case "$configuration" in debug|release) ;; *) printf '无效的构建配置：%s\n' "$configuration" >&2; exit 1 ;; esac
swift build --disable-sandbox --build-system native -c "$configuration"
binary_dir=$(swift build --disable-sandbox --build-system native -c "$configuration" --show-bin-path)
if [ "$configuration" = debug ]; then
    default_app_dir="$project_dir/.build/YogoLab Debug.app"
else
    default_app_dir="$project_dir/.build/YogoLab.app"
fi
app_dir=${YOGO_APP_DIR:-"$default_app_dir"}
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/YogoKeyLab" "$app_dir/Contents/MacOS/YogoKeyLab"
cp "$binary_dir/YogoSignal" "$app_dir/Contents/MacOS/YogoSignal"
# Release binaries do not need debug symbols, which may embed local build paths.
if [ "$configuration" = release ]; then
    strip -S -x "$app_dir/Contents/MacOS/YogoKeyLab" "$app_dir/Contents/MacOS/YogoSignal"
fi
iconset="$project_dir/.build/YogoKeyLab.iconset"
mkdir -p "$iconset"
make_icon() { sips -z "$1" "$1" "$project_dir/Assets/AppIcon.png" --out "$iconset/$2" >/dev/null; }
make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png
if ! iconutil -c icns "$iconset" -o "$app_dir/Contents/Resources/AppIcon.icns" 2>/dev/null; then
    swift scripts/pack-icon.swift "$iconset" "$app_dir/Contents/Resources/AppIcon.icns"
fi
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>dev.yogokeylab.app</string>
    <key>CFBundleName</key><string>YogoLab</string>
    <key>CFBundleDisplayName</key><string>YogoLab</string>
    <key>CFBundleExecutable</key><string>YogoKeyLab</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app_dir"
printf '构建完成：%s\n' "$app_dir"
