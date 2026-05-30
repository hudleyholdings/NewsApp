#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

BUILD_CONFIG="${1:-release}"
APP_NAME="${APP_NAME:-NewsApp}"
DISPLAY_NAME="${DISPLAY_NAME:-News App: RSS Reader & More}"
# Shown in the menu bar app menu and Dock. Kept separate from APP_NAME (the
# executable/bundle file name) so the user-facing name can have a space.
MENU_NAME="${MENU_NAME:-News App}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.hudleyholdings.newsapp}"
APP_VERSION="${APP_VERSION:-1.2}"
BUILD_NUMBER="${BUILD_NUMBER:-4}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
ENTITLEMENTS_FILE="${ENTITLEMENTS_FILE:-$ROOT_DIR/NewsApp.entitlements}"
PROVISIONING_PROFILE="${PROVISIONING_PROFILE:-}"
TEAM_ID="${TEAM_ID:-}"
SIGNING_KEYCHAIN="${SIGNING_KEYCHAIN:-}"
UNIVERSAL="${UNIVERSAL:-0}"

case "$BUILD_CONFIG" in
  release)
    XCODE_BUILD_CONFIG="Release"
    ;;
  debug)
    XCODE_BUILD_CONFIG="Debug"
    ;;
  *)
    echo "Unsupported build config: $BUILD_CONFIG"
    exit 64
    ;;
esac

if [[ "$UNIVERSAL" == "1" || "$UNIVERSAL" == "true" || "$UNIVERSAL" == "YES" ]]; then
  swift build -c "$BUILD_CONFIG" --arch arm64 --arch x86_64
  BUILT_EXECUTABLE="$ROOT_DIR/.build/apple/Products/$XCODE_BUILD_CONFIG/NewsApp"
else
  swift build -c "$BUILD_CONFIG"
  BUILT_EXECUTABLE="$ROOT_DIR/.build/$BUILD_CONFIG/NewsApp"
fi

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  value="${value//\'/&apos;}"
  print -r -- "$value"
}

XML_APP_NAME="$(xml_escape "$APP_NAME")"
XML_DISPLAY_NAME="$(xml_escape "$DISPLAY_NAME")"
XML_MENU_NAME="$(xml_escape "$MENU_NAME")"
XML_BUNDLE_IDENTIFIER="$(xml_escape "$BUNDLE_IDENTIFIER")"
XML_APP_VERSION="$(xml_escape "$APP_VERSION")"
XML_BUILD_NUMBER="$(xml_escape "$BUILD_NUMBER")"

APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

cp "$BUILT_EXECUTABLE" "$MACOS_DIR/NewsApp"

# Generate app icon from the white-backed icon art. The onboarding flow uses
# the transparent artwork separately so the Dock/App Store icon can stay opaque.
ICON_SOURCE="$ROOT_DIR/app_icon_white.png"
if [ -f "$ICON_SOURCE" ]; then
  ICONSET_DIR="$ROOT_DIR/build/AppIcon.iconset"
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"

  # Generate all required icon sizes
  sips -z 16 16     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" > /dev/null
  sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null
  sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" > /dev/null
  sips -z 64 64     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null
  sips -z 128 128   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" > /dev/null
  sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null
  sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" > /dev/null
  sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null
  sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" > /dev/null
  sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null

  # Convert iconset to icns
  iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
  rm -rf "$ICONSET_DIR"
  echo "Generated app icon from $(basename "$ICON_SOURCE")"
fi
chmod +x "$MACOS_DIR/NewsApp"

# Copy app resources into the native macOS bundle resource directory.
cp -R "$ROOT_DIR/Sources/NewsApp/Resources/." "$RESOURCES_DIR/"

if [ -f "$ROOT_DIR/Sources/NewsApp/Resources/PrivacyInfo.xcprivacy" ]; then
  cp "$ROOT_DIR/Sources/NewsApp/Resources/PrivacyInfo.xcprivacy" "$RESOURCES_DIR/PrivacyInfo.xcprivacy"
fi

if [ -n "$PROVISIONING_PROFILE" ]; then
  if [ ! -f "$PROVISIONING_PROFILE" ]; then
    echo "Missing provisioning profile: $PROVISIONING_PROFILE"
    exit 66
  fi
  cp "$PROVISIONING_PROFILE" "$CONTENTS_DIR/embedded.provisionprofile"
fi

# Copy dynamic libraries to Frameworks folder (if any exist)
if [[ "$UNIVERSAL" == "1" || "$UNIVERSAL" == "true" || "$UNIVERSAL" == "YES" ]]; then
  DYLIB_DIR="$ROOT_DIR/.build/apple/Products/$XCODE_BUILD_CONFIG"
else
  DYLIB_DIR="$ROOT_DIR/.build/$BUILD_CONFIG"
fi

for dylib in "$DYLIB_DIR"/*.dylib(N); do
  if [ -f "$dylib" ]; then
    cp "$dylib" "$FRAMEWORKS_DIR/"
    DYLIB_NAME=$(basename "$dylib")
    install_name_tool -id "@rpath/$DYLIB_NAME" "$FRAMEWORKS_DIR/$DYLIB_NAME"
    codesign_keychain_args=()
    if [[ -n "$SIGNING_KEYCHAIN" ]]; then
      codesign_keychain_args=(--keychain "$SIGNING_KEYCHAIN")
    fi
    codesign --force --sign "$CODE_SIGN_IDENTITY" "${codesign_keychain_args[@]}" "$FRAMEWORKS_DIR/$DYLIB_NAME"
  fi
done

# Update the executable's rpath to find libraries in Frameworks
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/NewsApp" 2>/dev/null || true

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$XML_MENU_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$XML_DISPLAY_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$XML_BUNDLE_IDENTIFIER</string>
  <key>CFBundleExecutable</key>
  <string>NewsApp</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>MacOSX</string>
  </array>
  <key>CFBundleShortVersionString</key>
  <string>$XML_APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$XML_BUILD_NUMBER</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>NSHumanReadableCopyright</key>
  <string>© 2024-2026 Hudley Holdings LLC. All rights reserved.</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSQuitAlwaysKeepsWindows</key>
  <false/>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.news</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>NSLocationUsageDescription</key>
  <string>$XML_DISPLAY_NAME uses your location only when you choose Use My Location to show local weather and nearby radio station distances.</string>
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>$XML_DISPLAY_NAME uses your location only when you choose Use My Location to show local weather and nearby radio station distances.</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
  </dict>
  <key>ITSAppUsesNonExemptEncryption</key>
  <false/>
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS_DIR/Info.plist" "$RESOURCES_DIR/PrivacyInfo.xcprivacy" >/dev/null

# Quarantine xattrs inherited from downloaded signing assets make App Store
# processing fail after productbuild packages the bundle.
xattr -cr "$APP_DIR" 2>/dev/null || true

# Re-sign the app bundle (required after modifying the bundle)
SIGNING_ENTITLEMENTS_FILE="$ENTITLEMENTS_FILE"
if [[ -n "$TEAM_ID" && -f "$ENTITLEMENTS_FILE" ]]; then
  SIGNING_ENTITLEMENTS_FILE="$(mktemp "$ROOT_DIR/build/$APP_NAME.entitlements.plist.XXXXXX")"
  cp "$ENTITLEMENTS_FILE" "$SIGNING_ENTITLEMENTS_FILE"

  /usr/libexec/PlistBuddy -c "Set :com.apple.application-identifier $TEAM_ID.$BUNDLE_IDENTIFIER" "$SIGNING_ENTITLEMENTS_FILE" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $TEAM_ID.$BUNDLE_IDENTIFIER" "$SIGNING_ENTITLEMENTS_FILE"
  /usr/libexec/PlistBuddy -c "Set :com.apple.developer.team-identifier $TEAM_ID" "$SIGNING_ENTITLEMENTS_FILE" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$SIGNING_ENTITLEMENTS_FILE"
fi

codesign_args=(--force --deep --sign "$CODE_SIGN_IDENTITY")
if [[ -n "$SIGNING_KEYCHAIN" ]]; then
  codesign_args+=(--keychain "$SIGNING_KEYCHAIN")
fi
if [ -f "$SIGNING_ENTITLEMENTS_FILE" ]; then
  codesign_args+=(--entitlements "$SIGNING_ENTITLEMENTS_FILE")
fi
codesign "${codesign_args[@]}" "$APP_DIR"

echo "Built: $APP_DIR"
