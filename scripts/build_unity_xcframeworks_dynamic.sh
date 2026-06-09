#!/usr/bin/env bash
# =============================================================================
# build_unity_xcframeworks_dynamic.sh
#
# Compila los Swift packages del iOS SDK como xcframeworks DINÁMICOS con headers
# públicos para Unity 6. Esta versión es más robusta para resolver problemas
# de linkage entre Swift y Objective-C++.
#
# Produce en UNITY_PLUGINS_DIR:
#   - LoomitOfferwallCore.xcframework (dynamic framework)
#   - LoomitOfferwallAdapterAPI.xcframework (dynamic framework)
#   - LoomitOfferwallAdapterMyChips.xcframework (dynamic framework)
#   - LoomitOfferwallAdapterTapjoy.xcframework (dynamic framework)
#
# Uso:
#   ./ios/scripts/build_unity_xcframeworks_dynamic.sh
#
# Requiere: Xcode 15+ con Command Line Tools
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$IOS_ROOT/.." && pwd)"

UNITY_PLUGINS_DIR="$REPO_ROOT/unity-sample-app-unity6/Assets/Plugins/iOS"
BUILD_DIR="$IOS_ROOT/build/unity_xcframeworks_dynamic"

# iOS platforms to build for
DEVICE_SDK="iphoneos"
SIM_SDK="iphonesimulator"
MIN_IOS="14.0"

# -------------------------------------------------------------------------
# Only build LoomitUnityBridge (dynamic framework).
# All internal dependencies (Core, AdapterAPI, adapters, Debug) are
# statically linked INTO LoomitUnityBridge by Xcode.  The publisher only
# needs to embed: LoomitUnityBridge + Tapjoy + MyChipsSdk.
# -------------------------------------------------------------------------

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
rm -rf "$UNITY_PLUGINS_DIR"/*.xcframework

echo "🔨 Building LoomitUnityBridge dynamic xcframework for Unity..."

TARGET="LoomitUnityBridge"
PKG_PATH="$IOS_ROOT/$TARGET"

# Build for device (arm64)
echo "  🏗️  Building for iOS device (arm64)..."
DEVICE_ARCHIVE="$BUILD_DIR/${TARGET}-device.xcarchive"
(
    cd "$PKG_PATH"
    xcodebuild archive \
        -scheme "$TARGET" \
        -destination "generic/platform=iOS" \
        -configuration Release \
        -archivePath "$DEVICE_ARCHIVE" \
        -derivedDataPath "$BUILD_DIR/DerivedData" \
        SKIP_INSTALL=NO \
        BUILD_LIBRARY_FOR_DISTRIBUTION=NO \
        IPHONEOS_DEPLOYMENT_TARGET="$MIN_IOS" \
        ONLY_ACTIVE_ARCH=NO
)

# Build for simulator (arm64 + x86_64)
echo "  🏗️  Building for iOS simulator (arm64 + x86_64)..."
SIM_ARCHIVE="$BUILD_DIR/${TARGET}-sim.xcarchive"
(
    cd "$PKG_PATH"
    xcodebuild archive \
        -scheme "$TARGET" \
        -destination "generic/platform=iOS Simulator" \
        -configuration Release \
        -archivePath "$SIM_ARCHIVE" \
        -derivedDataPath "$BUILD_DIR/DerivedData" \
        SKIP_INSTALL=NO \
        BUILD_LIBRARY_FOR_DISTRIBUTION=NO \
        IPHONEOS_DEPLOYMENT_TARGET="$MIN_IOS" \
        ONLY_ACTIVE_ARCH=NO
)

# Create xcframework
echo "  📦 Creating xcframework..."
XCFRAMEWORK="$UNITY_PLUGINS_DIR/${TARGET}.xcframework"
rm -rf "$XCFRAMEWORK"

DEVICE_FRAMEWORK=$(find "$DEVICE_ARCHIVE/Products" -name "*.framework" -type d | head -1)
SIM_FRAMEWORK=$(find "$SIM_ARCHIVE/Products" -name "*.framework" -type d | head -1)

if [ -z "$DEVICE_FRAMEWORK" ] || [ -z "$SIM_FRAMEWORK" ]; then
    echo "❌ Failed to locate framework binaries in archives"
    exit 1
fi

xcodebuild -create-xcframework \
    -framework "$DEVICE_FRAMEWORK" \
    -framework "$SIM_FRAMEWORK" \
    -output "$XCFRAMEWORK"

echo "  ✅ Created $XCFRAMEWORK (dynamic framework)"

# -------------------------------------------------------------------------
# Copy generated Swift header into the xcframework
# (xcodebuild archive doesn't copy it automatically for SPM packages)
# -------------------------------------------------------------------------
HEADER_SRC=$(find "$BUILD_DIR/DerivedData" -name "${TARGET}-Swift.h" -path "*/GeneratedModuleMaps-*" | head -1)
if [ -n "$HEADER_SRC" ]; then
    for VARIANT in "$XCFRAMEWORK"/*/${TARGET}.framework; do
        mkdir -p "$VARIANT/Headers"
        cp "$HEADER_SRC" "$VARIANT/Headers/${TARGET}-Swift.h"
    done
    echo "  ✅ Copied generated Swift header into xcframework"
else
    echo "  ⚠️  Generated Swift header not found — Objective-C compilation may fail"
fi

rm -rf "$DEVICE_ARCHIVE" "$SIM_ARCHIVE"

# -------------------------------------------------------------------------
# Copy prebuilt Tapjoy.xcframework from CocoaPods cache
# -------------------------------------------------------------------------
echo ""
echo "📦 Copying prebuilt Tapjoy.xcframework..."
TAPJOY_SRC=$(find "$HOME/Library/Caches/CocoaPods/Pods/Release/TapjoySDK" \
    -path "*/Libraries/Tapjoy.xcframework" -type d 2>/dev/null | head -1)
if [ -n "$TAPJOY_SRC" ]; then
    cp -R "$TAPJOY_SRC" "$UNITY_PLUGINS_DIR/Tapjoy.xcframework"
    echo "  ✅ $UNITY_PLUGINS_DIR/Tapjoy.xcframework"
else
    echo "  ⚠️  Tapjoy.xcframework not found in CocoaPods cache."
    echo "      Run 'pod install' in the native iOS sample app to download it."
fi

# Same for MyChipsSdk
echo "📦 Copying prebuilt MyChipsSdk.xcframework..."
MYCHIPS_SRC=$(find "$HOME/Library/Caches/CocoaPods/Pods/External" \
    -path "*/MyChipsSdk.xcframework" -type d 2>/dev/null | head -1)
if [ -n "$MYCHIPS_SRC" ]; then
    cp -R "$MYCHIPS_SRC" "$UNITY_PLUGINS_DIR/MyChipsSdk.xcframework"
    echo "  ✅ $UNITY_PLUGINS_DIR/MyChipsSdk.xcframework"
else
    echo "  ⚠️  MyChipsSdk.xcframework not found in CocoaPods cache."
fi

# -------------------------------------------------------------------------
# Generate Unity .meta files for ALL xcframeworks
# -------------------------------------------------------------------------
echo ""
echo "📝 Generating Unity .meta files..."

for NAME in LoomitUnityBridge Tapjoy MyChipsSdk; do
    XCFW="$UNITY_PLUGINS_DIR/${NAME}.xcframework"
    [ -d "$XCFW" ] || continue
    META="$XCFW.meta"
    GUID=$(echo -n "$NAME" | md5 | cut -c1-32)
    cat > "$META" <<METAEOF
fileFormatVersion: 2
guid: $GUID
PluginImporter:
  externalObjects: {}
  serializedVersion: 2
  iconMap: {}
  executionOrder: {}
  defineConstraints: []
  isPreloaded: 0
  isOverridable: 0
  isExplicitlyReferenced: 0
  validateReferences: 1
  platformData:
  - first:
      iPhone: iOS
    second:
      enabled: 1
      settings:
        AddToEmbeddedBinaries: 1
        iOSSharedLibrary: 0
  - first:
      Editor: Editor
    second:
      enabled: 0
      settings:
        DefaultValueInitialized: true
  - first:
      Any:
    second:
      enabled: 0
      settings: {}
  userData:
  nameMeta:
  assetBundleName:
  assetBundleVariant:
METAEOF
    echo "  ✓ $META"
done

echo ""
echo "✅ All dynamic xcframeworks built successfully!"
echo ""
echo "📁 Generated frameworks:"
ls -la "$UNITY_PLUGINS_DIR"/*.xcframework
echo ""
echo "🎯 Next steps:"
echo "   1. Build Unity project to iOS"
echo "   2. Open generated .xcodeproj in Xcode"
echo "   3. Build and run on device/simulator"
