#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="${APP_NAME:-NewsApp}"
DISPLAY_NAME="${DISPLAY_NAME:-News App: RSS Reader & More}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.hudleyholdings.newsapp}"
APP_VERSION="${APP_VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-2}"
TEAM_ID="${TEAM_ID:-}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-3rd Party Mac Developer Application}"
INSTALLER_SIGN_IDENTITY="${INSTALLER_SIGN_IDENTITY:-3rd Party Mac Developer Installer}"
PROVISIONING_PROFILE="${PROVISIONING_PROFILE:-}"
SIGNING_KEYCHAIN="${SIGNING_KEYCHAIN:-}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/build/app-store}"
PKG_PATH="${PKG_PATH:-$OUTPUT_DIR/$APP_NAME-$APP_VERSION-$BUILD_NUMBER.pkg}"
UPLOAD="${UPLOAD:-0}"
VALIDATE="${VALIDATE:-0}"

error() {
  echo "error: $*" >&2
  exit 1
}

identity_exists() {
  local identity="$1"
  security find-identity -v -p codesigning | grep -F "$identity" >/dev/null 2>&1
}

certificate_exists() {
  local identity="$1"
  security find-certificate -a -c "$identity" >/dev/null 2>&1
}

find_profile() {
  local profiles_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
  [[ -d "$profiles_dir" ]] || return 1

  local profile plist app_identifier profile_uuid profile_name
  for profile in "$profiles_dir"/*.(provisionprofile|mobileprovision)(N); do
    plist="$(mktemp)"
    if security cms -D -i "$profile" > "$plist" 2>/dev/null; then
      app_identifier="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$plist" 2>/dev/null || true)"
      if [[ -z "$app_identifier" ]]; then
        app_identifier="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$plist" 2>/dev/null || true)"
      fi
      profile_uuid="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$plist" 2>/dev/null || true)"
      profile_name="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$plist" 2>/dev/null || true)"
      if [[ "$app_identifier" == "$TEAM_ID.$BUNDLE_IDENTIFIER" ]]; then
        rm -f "$plist"
        echo "$profile"
        return 0
      fi
      if [[ "$profile_name" == *"$BUNDLE_IDENTIFIER"* || "$profile_uuid" == "$BUNDLE_IDENTIFIER" ]]; then
        rm -f "$plist"
        echo "$profile"
        return 0
      fi
    fi
    rm -f "$plist"
  done

  return 1
}

if [[ -z "$TEAM_ID" ]]; then
  error "missing TEAM_ID. Set TEAM_ID=YOURTEAMID (your Apple Developer Team ID) in the environment before running this script."
fi

if ! identity_exists "$CODE_SIGN_IDENTITY"; then
  error "missing application signing identity matching '$CODE_SIGN_IDENTITY'. Install an Apple/Mac App Distribution certificate with its private key in this keychain."
fi

if ! certificate_exists "$INSTALLER_SIGN_IDENTITY"; then
  error "missing installer signing certificate matching '$INSTALLER_SIGN_IDENTITY'. Install a Mac Installer Distribution certificate with its private key in this keychain."
fi

if [[ -z "$PROVISIONING_PROFILE" ]]; then
  PROVISIONING_PROFILE="$(find_profile || true)"
fi

if [[ -z "$PROVISIONING_PROFILE" ]]; then
  error "missing Mac App Store provisioning profile for $BUNDLE_IDENTIFIER. Download it from Apple Developer and set PROVISIONING_PROFILE=/path/to/profile.provisionprofile."
fi

mkdir -p "$OUTPUT_DIR"

UNIVERSAL=1 \
APP_NAME="$APP_NAME" \
DISPLAY_NAME="$DISPLAY_NAME" \
BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
APP_VERSION="$APP_VERSION" \
BUILD_NUMBER="$BUILD_NUMBER" \
CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
PROVISIONING_PROFILE="$PROVISIONING_PROFILE" \
TEAM_ID="$TEAM_ID" \
SIGNING_KEYCHAIN="$SIGNING_KEYCHAIN" \
"$ROOT_DIR/scripts/make_app_bundle.sh" release

APP_DIR="$ROOT_DIR/build/$APP_NAME.app"

codesign --verify --deep --strict --verbose=4 "$APP_DIR"
codesign -dv --verbose=4 "$APP_DIR" 2>&1 | sed -n '1,80p'

rm -f "$PKG_PATH"
productbuild_args=(--component "$APP_DIR" /Applications --sign "$INSTALLER_SIGN_IDENTITY")
if [[ -n "$SIGNING_KEYCHAIN" ]]; then
  productbuild_args+=(--keychain "$SIGNING_KEYCHAIN")
fi
productbuild "${productbuild_args[@]}" "$PKG_PATH"
pkgutil --check-signature "$PKG_PATH"

if [[ "$VALIDATE" == "1" || "$UPLOAD" == "1" ]]; then
  AUTH_ARGS=()
  if [[ -n "${ASC_API_KEY:-}" && -n "${ASC_API_ISSUER:-}" ]]; then
    AUTH_ARGS=(--api-key "$ASC_API_KEY" --api-issuer "$ASC_API_ISSUER")
  elif [[ -n "${ASC_USERNAME:-}" && -n "${ASC_PASSWORD_KEYCHAIN_ITEM:-}" ]]; then
    AUTH_ARGS=(-u "$ASC_USERNAME" -p "@keychain:$ASC_PASSWORD_KEYCHAIN_ITEM")
  elif [[ -n "${ASC_USERNAME:-}" && -n "${ASC_PASSWORD:-}" ]]; then
    AUTH_ARGS=(-u "$ASC_USERNAME" -p "@env:ASC_PASSWORD")
  else
    error "VALIDATE/UPLOAD requested, but no App Store Connect auth was provided. Set ASC_API_KEY+ASC_API_ISSUER or ASC_USERNAME+ASC_PASSWORD_KEYCHAIN_ITEM."
  fi
fi

if [[ "$VALIDATE" == "1" ]]; then
  xcrun altool --validate-app -f "$PKG_PATH" -t macos "${AUTH_ARGS[@]}"
fi

if [[ "$UPLOAD" == "1" ]]; then
  [[ -n "${ASC_APPLE_ID:-}" ]] || error "UPLOAD requires ASC_APPLE_ID, the numeric App Store Connect Apple ID for the app."
  PROVIDER_ARGS=()
  if [[ -n "${ASC_PROVIDER_PUBLIC_ID:-}" ]]; then
    PROVIDER_ARGS=(--provider-public-id "$ASC_PROVIDER_PUBLIC_ID")
  elif [[ -n "$TEAM_ID" ]]; then
    PROVIDER_ARGS=(--team-id "$TEAM_ID")
  fi

  xcrun altool --upload-package "$PKG_PATH" \
    -t macos \
    "${PROVIDER_ARGS[@]}" \
    --apple-id "$ASC_APPLE_ID" \
    --bundle-version "$BUILD_NUMBER" \
    --bundle-short-version-string "$APP_VERSION" \
    --bundle-id "$BUNDLE_IDENTIFIER" \
    --wait \
    "${AUTH_ARGS[@]}"
fi

echo "Built App Store package: $PKG_PATH"
