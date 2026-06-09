#!/usr/bin/env bash
# =============================================================================
# build_unity_xcframeworks.sh
#
# Compila los Swift packages del iOS SDK como xcframeworks listos para
# embedear en el proyecto Unity 6.
#
# Produce en UNITY_PLUGINS_DIR:
#   - LoomitOfferwallCore.xcframework
#   - LoomitOfferwallAdapterAPI.xcframework
#   - LoomitOfferwallAdapterMyChips.xcframework
#   - LoomitOfferwallAdapterTapjoy.xcframework
#
# Uso:
#   ./ios/scripts/build_unity_xcframeworks.sh
#
# Requiere: Xcode 15+ con Command Line Tools
# =============================================================================
# STRATEGY: Each SPM package is built via xcodebuild with explicit -destination
# for both device (arm64) and simulator (arm64+x86_64), then assembled into
# an xcframework. No -workspace / -project needed for SPM packages in Xcode 14+.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$IOS_ROOT/.." && pwd)"

UNITY_PLUGINS_DIR="$REPO_ROOT/unity-sample-app-unity6/Assets/Plugins/iOS"
SWIFT_MODULES_DIR="$UNITY_PLUGINS_DIR/SwiftModules"
BUILD_DIR="$IOS_ROOT/build/unity_xcframeworks"

# iOS platforms to build for
DEVICE_SDK="iphoneos"
SIM_SDK="iphonesimulator"
MIN_IOS="14.0"

# Build order: dependencies first
BUILD_ORDER=(
    "LoomitOfferwallAdapterAPI"
    "LoomitOfferwallCore"
    "LoomitOfferwallDebug"
    "LoomitOfferwallAdapterMyChips"
    "LoomitOfferwallAdapterTapjoy"
)

# All targets now use BUILD_LIBRARY_FOR_DISTRIBUTION for Swift version compatibility
# (Previous Tapjoy swiftinterface bug appears resolved in current SDK versions)
no_lib_evolution() {
    # All targets use library evolution for cross-Swift-version compatibility
    return 1
}

# Package path lookup (bash 3.2 compatible)
pkg_path() {
    case "$1" in
        LoomitOfferwallAdapterAPI)   echo "$IOS_ROOT/LoomitOfferwallAdapterAPI" ;;
        LoomitOfferwallCore)         echo "$IOS_ROOT/LoomitOfferwallCore" ;;
        LoomitOfferwallDebug)        echo "$IOS_ROOT/LoomitOfferwallDebug" ;;
        LoomitOfferwallAdapterMyChips) echo "$IOS_ROOT/LoomitOfferwallAdapterMyChips" ;;
        LoomitOfferwallAdapterTapjoy) echo "$IOS_ROOT/LoomitOfferwallAdapterTapjoy" ;;
    esac
}

echo "============================================"
echo " Loomit iOS Unity xcframework builder"
echo "============================================"
echo " IOS_ROOT:          $IOS_ROOT"
echo " BUILD_DIR:         $BUILD_DIR"
echo " UNITY_PLUGINS_DIR: $UNITY_PLUGINS_DIR"
echo " SWIFT_MODULES_DIR: $SWIFT_MODULES_DIR"
echo ""

mkdir -p "$BUILD_DIR"
mkdir -p "$UNITY_PLUGINS_DIR"
rm -rf "$SWIFT_MODULES_DIR"
mkdir -p "$SWIFT_MODULES_DIR/iphoneos"
mkdir -p "$SWIFT_MODULES_DIR/iphonesimulator"

# -----------------------------------------------------------------------------
# Helper: build one SPM target via swift build + assemble .framework
# Uses BUILD_LIBRARY_FOR_DISTRIBUTION via swiftc flags
# -----------------------------------------------------------------------------
# Build one SPM target for one platform via xcodebuild archive.
# Converts the resulting .o artifact into a proper .a static lib and
# writes its path to OUT_DIR/.static_lib.
build_spm_static() {
    local TARGET="$1"
    local PKG_PATH="$2"
    local PLATFORM="$3"   # "device" | "simulator"
    local OUT_DIR="$BUILD_DIR/$TARGET/$PLATFORM"
    local ARCHIVE="$OUT_DIR/${TARGET}.xcarchive"

    local DESTINATION
    local BUILD_SUFFIX
    if [ "$PLATFORM" = "device" ]; then
        DESTINATION="generic/platform=iOS"
        BUILD_SUFFIX="Release-iphoneos"
    else
        DESTINATION="generic/platform=iOS Simulator"
        BUILD_SUFFIX="Release-iphonesimulator"
    fi

    mkdir -p "$OUT_DIR"
    rm -f "$OUT_DIR/.static_lib" "$OUT_DIR/.swiftmodule_dir"
    rm -rf "$OUT_DIR/swiftmodules"

    echo "  [xcodebuild archive] $TARGET [$PLATFORM]"
    local LIB_DIST="YES"
    no_lib_evolution "$TARGET" && LIB_DIST="NO"

    local RC=0
    (
        cd "$PKG_PATH"
        xcodebuild archive \
            -scheme "$TARGET" \
            -destination "$DESTINATION" \
            -configuration Release \
            -archivePath "$ARCHIVE" \
            -clonedSourcePackagesDirPath "$BUILD_DIR/spm_cache" \
            SKIP_INSTALL=NO \
            BUILD_LIBRARY_FOR_DISTRIBUTION="$LIB_DIST" \
            IPHONEOS_DEPLOYMENT_TARGET="$MIN_IOS" \
            2>&1 | grep -E "(error:|FAILED|succeeded)" | grep -v "note:" | head -5 || true
    ) || RC=$?

    # Locate ALL .o artifacts in archive Products.
    # CRITICAL: SPM archives contain one .o per target dependency.
    # We must include ALL of them — the old `head -1` only took one,
    # which was often the wrong dependency.
    local ALL_OBJS
    ALL_OBJS=$(find "$ARCHIVE/Products" -name "*.o" 2>/dev/null || true)

    if [ -z "$ALL_OBJS" ]; then
        echo "  ⚠️  No .o artifact in archive for $TARGET [$PLATFORM]"
        return
    fi

    # Convert all .o → .a so xcodebuild -create-xcframework accepts it.
    # Use libtool instead of ar because the .o files may be fat (multi-arch).
    local STATIC_LIB="$OUT_DIR/lib${TARGET}.a"
    # shellcheck disable=SC2086
    libtool -static -o "$STATIC_LIB" $ALL_OBJS 2>/dev/null || true
    echo "$STATIC_LIB" > "$OUT_DIR/.static_lib"
    echo "  ✓ [$PLATFORM] lib=$STATIC_LIB"

    # Locate swiftmodule in DerivedData and copy to SwiftModules export dir
    local DD
    DD=$(find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 1 -type d -name "${TARGET}-*" 2>/dev/null | sort | tail -1 || true)
    if [ -n "$DD" ]; then
        local SM_DIR
        SM_DIR=$(find "$DD/Build/Intermediates.noindex/ArchiveIntermediates/$TARGET/BuildProductsPath/$BUILD_SUFFIX" \
            -maxdepth 1 -name "${TARGET}.swiftmodule" -type d 2>/dev/null | head -1 || true)
        if [ -n "$SM_DIR" ]; then
            # Export swiftmodule to the Unity plugin's SwiftModules directory
            # (split by platform so the PostProcessBuild script can set the right path)
            local SM_EXPORT
            if [ "$PLATFORM" = "device" ]; then
                SM_EXPORT="$SWIFT_MODULES_DIR/iphoneos"
            else
                SM_EXPORT="$SWIFT_MODULES_DIR/iphonesimulator"
            fi
            mkdir -p "$SM_EXPORT"
            cp -R "$SM_DIR" "$SM_EXPORT/${TARGET}.swiftmodule"
            # Remove binary .swiftmodule files - keep only .swiftinterface for cross-version compatibility
            find "$SM_EXPORT/${TARGET}.swiftmodule" -name "*.swiftmodule" -type f -delete
            echo "  ✓ swiftmodule exported [$PLATFORM]"
        else
            echo "  ⚠️  swiftmodule not found for $TARGET [$PLATFORM]"
        fi
    else
        echo "  ⚠️  DerivedData entry not found for $TARGET"
    fi
}

# -----------------------------------------------------------------------------
# Build each package and create xcframework
# -----------------------------------------------------------------------------
for TARGET in "${BUILD_ORDER[@]}"; do
    PKG_PATH="$(pkg_path "$TARGET")"
    echo ""
    echo "── $TARGET ──────────────────────────────────"

    build_spm_static "$TARGET" "$PKG_PATH" "device"
    build_spm_static "$TARGET" "$PKG_PATH" "simulator"

    XCFW_OUT="$UNITY_PLUGINS_DIR/${TARGET}.xcframework"
    rm -rf "$XCFW_OUT"

    XCFW_CMD=""

    for PLATFORM_LABEL in "device" "simulator"; do
        STATIC_LIB_FILE="$BUILD_DIR/$TARGET/$PLATFORM_LABEL/.static_lib"
        [ -f "$STATIC_LIB_FILE" ] || continue
        STATIC_LIB=$(cat "$STATIC_LIB_FILE")
        [ -f "$STATIC_LIB" ] || continue
        XCFW_CMD="$XCFW_CMD -library $STATIC_LIB"
    done

    if [ -n "$XCFW_CMD" ]; then
        # shellcheck disable=SC2086
        xcodebuild -create-xcframework \
            $XCFW_CMD \
            -output "$XCFW_OUT" 2>&1 | grep -v "^$" | tail -5 || true

        if [ -d "$XCFW_OUT" ]; then
            echo "  ✅ $XCFW_OUT"
        else
            echo "  ⚠️  xcframework creation failed for $TARGET"
        fi
    else
        echo "  ⚠️  No artifacts for $TARGET — xcframework NOT created"
    fi
done

# -----------------------------------------------------------------------------
# Copy prebuilt Tapjoy.xcframework from SPM artifacts cache
# -----------------------------------------------------------------------------
echo ""
echo "── Copying prebuilt Tapjoy.xcframework ─────"
TAPJOY_SRC=$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path "*/SourcePackages/artifacts/swift-packages/Tapjoy/Tapjoy.xcframework" \
    -type d 2>/dev/null | head -1 || true)
TAPJOY_DEST="$UNITY_PLUGINS_DIR/Tapjoy.xcframework"
if [ -n "$TAPJOY_SRC" ]; then
    rm -rf "$TAPJOY_DEST"
    cp -R "$TAPJOY_SRC" "$TAPJOY_DEST"
    echo "  ✅ $TAPJOY_DEST"
else
    echo "  ⚠️  Tapjoy.xcframework not found in DerivedData SPM cache."
    echo "      Open the iOS SampleApp in Xcode once to resolve SPM packages, then re-run."
fi

# Same for MyChipsSdk (prebuilt xcframework bundled by SPM)
MYCHIPS_SRC=$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path "*/SourcePackages/artifacts/*/MyChipsSdk.xcframework" \
    -type d 2>/dev/null | head -1 || true)
MYCHIPS_DEST="$UNITY_PLUGINS_DIR/MyChipsSdk.xcframework"
if [ -n "$MYCHIPS_SRC" ]; then
    rm -rf "$MYCHIPS_DEST"
    cp -R "$MYCHIPS_SRC" "$MYCHIPS_DEST"
    echo "  ✅ $MYCHIPS_DEST"
else
    echo "  ⚠️  MyChipsSdk.xcframework not found in DerivedData SPM cache."
fi

# -----------------------------------------------------------------------------
# Generate Unity .meta files for ALL xcframeworks in the Plugins dir
# -----------------------------------------------------------------------------
echo ""
echo "── Generating Unity .meta files ────────────"

# Collect all xcframeworks (built + prebuilt) — bash 3.2 compatible
ALL_XCFW=(
    "LoomitOfferwallAdapterAPI"
    "LoomitOfferwallCore"
    "LoomitOfferwallDebug"
    "LoomitOfferwallAdapterMyChips"
    "LoomitOfferwallAdapterTapjoy"
    "Tapjoy"
    "MyChipsSdk"
)

generate_meta() {
    local NAME="$1"
    local XCFW="$UNITY_PLUGINS_DIR/${NAME}.xcframework"
    local META="$XCFW.meta"
    [ -d "$XCFW" ] || return
    local GUID
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
}

for NAME in "${ALL_XCFW[@]}"; do
    generate_meta "$NAME"
done

# Generate .meta for SwiftModules directory so Unity copies it to the Xcode project
SM_META="$SWIFT_MODULES_DIR.meta"
SM_GUID=$(echo -n "SwiftModules" | md5 | cut -c1-32)
cat > "$SM_META" <<SMMEOF
fileFormatVersion: 2
guid: $SM_GUID
folderAsset: yes
DefaultImporter:
  externalObjects: {}
  userData:
  assetBundleName:
  assetBundleVariant:
SMMEOF
echo "  ✓ $SM_META"

echo ""
echo "── Post-build symbol validation ─────────────"
VALIDATION_FAILED=0
for TARGET in "${BUILD_ORDER[@]}"; do
    XCFW="$UNITY_PLUGINS_DIR/${TARGET}.xcframework"
    [ -d "$XCFW" ] || continue
    # Find simulator .a (preferred for validation since we dev on Mac)
    LIB=$(find "$XCFW" -name "lib${TARGET}.a" -path "*simulator*" 2>/dev/null | head -1)
    [ -z "$LIB" ] && LIB=$(find "$XCFW" -name "lib${TARGET}.a" 2>/dev/null | head -1)
    if [ -n "$LIB" ]; then
        SYM_COUNT=$(nm "$LIB" 2>/dev/null | grep -c "${TARGET}" || true)
        if [ "$SYM_COUNT" -gt 0 ]; then
            echo "  ✅ $TARGET: $SYM_COUNT symbols found"
        else
            echo "  ❌ $TARGET: NO symbols found — xcframework is broken!"
            VALIDATION_FAILED=1
        fi
    else
        echo "  ⚠️  $TARGET: .a not found in xcframework"
    fi
done

if [ "$VALIDATION_FAILED" -ne 0 ]; then
    echo ""
    echo "❌ VALIDATION FAILED: Some xcframeworks have no symbols."
    echo "   The Unity build WILL fail with 'Undefined symbol' errors."
    exit 1
fi

echo ""
echo "============================================"
echo " Build complete."
echo " xcframeworks   → $UNITY_PLUGINS_DIR"
echo " swiftmodules   → $SWIFT_MODULES_DIR"
echo "============================================"
