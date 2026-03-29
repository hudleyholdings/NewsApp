#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

BUILD_CONFIG="${1:-release}"
swift build -c "$BUILD_CONFIG"

APP_DIR="$ROOT_DIR/build/NewsApp.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

cp "$ROOT_DIR/.build/$BUILD_CONFIG/NewsApp" "$MACOS_DIR/NewsApp"

# Generate app icon from logo2_cropped.png
if [ -f "$ROOT_DIR/logo2_cropped.png" ]; then
  ICONSET_DIR="$ROOT_DIR/build/AppIcon.iconset"
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"

  # Generate all required icon sizes
  sips -z 16 16     "$ROOT_DIR/logo2_cropped.png" --out "$ICONSET_DIR/icon_16x16.png" > /dev/null
  sips -z 32 32     "$ROOT_DIR/logo2_cropped.png" --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null
  sips -z 32 32     "$ROOT_DIR/logo2_cropped.png" --out "$ICONSET_DIR/icon_32x32.png" > /dev/null
  sips -z 64 64     "$ROOT_DIR/logo2_cropped.png" --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null
  sips -z 128 128   "$ROOT_DIR/logo2_cropped.png" --out "$ICONSET_DIR/icon_128x128.png" > /dev/null
  sips -z 256 256   "$ROOT_DIR/logo2_cropped.png" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null
  sips -z 256 256   "$ROOT_DIR/logo2_cropped.png" --out "$ICONSET_DIR/icon_256x256.png" > /dev/null
  sips -z 512 512   "$ROOT_DIR/logo2_cropped.png" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null
  sips -z 512 512   "$ROOT_DIR/logo2_cropped.png" --out "$ICONSET_DIR/icon_512x512.png" > /dev/null
  sips -z 1024 1024 "$ROOT_DIR/logo2_cropped.png" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null

  # Convert iconset to icns
  iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
  rm -rf "$ICONSET_DIR"
  echo "Generated app icon from logo2_cropped.png"
fi
chmod +x "$MACOS_DIR/NewsApp"

# Copy resource bundles (SPM may name them NewsApp_NewsApp.bundle or NewsApp_Resources.bundle)
for bundle in "$ROOT_DIR/.build/$BUILD_CONFIG"/NewsApp*.bundle(N); do
  cp -R "$bundle" "$RESOURCES_DIR/"
done

# Copy dynamic libraries to Frameworks folder (if any exist)
for dylib in "$ROOT_DIR/.build/$BUILD_CONFIG"/*.dylib(N); do
  if [ -f "$dylib" ]; then
    cp "$dylib" "$FRAMEWORKS_DIR/"
    DYLIB_NAME=$(basename "$dylib")
    install_name_tool -id "@rpath/$DYLIB_NAME" "$FRAMEWORKS_DIR/$DYLIB_NAME"
  fi
done

# Update the executable's rpath to find libraries in Frameworks
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/NewsApp" 2>/dev/null || true

cat <<'PLIST' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>NewsApp</string>
  <key>CFBundleDisplayName</key>
  <string>NewsApp</string>
  <key>CFBundleIdentifier</key>
  <string>com.hudleyholdings.newsapp</string>
  <key>CFBundleExecutable</key>
  <string>NewsApp</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>NSHumanReadableCopyright</key>
  <string>© 2024-2026 Hudley Holdings LLC. All rights reserved.</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.news</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
</dict>
</plist>
PLIST

# Re-sign the app bundle (required after modifying the bundle)
codesign --force --deep --sign - "$APP_DIR"

echo "Built: $APP_DIR"
