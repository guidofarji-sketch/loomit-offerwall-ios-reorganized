# Unity iOS Bridge — Technical Analysis & Architecture Plan

> **Author**: Technical Owner Sr  
> **Date**: May 2026  
> **Status**: Draft — awaiting approval before implementation  
> **Scope**: Loomit Offerwall SDK iOS → Unity 6 integration

---

## 1. Executive Summary

The Unity iOS bridge has been failing repeatedly due to a **fundamentally broken 
xcframework build pipeline** and an **ad-hoc bridge design** that doesn't follow 
the proven patterns for Swift → Unity integration.

This document:
1. Diagnoses the root causes with evidence.
2. Defines the correct architecture based on industry best practices.
3. Provides a phased implementation plan.

---

## 2. Root Cause Analysis

### 2.1. The xcframework build script is fundamentally broken

**File**: `ios/scripts/build_unity_xcframeworks.sh`

**Critical bug** (line 130):
```bash
OBJ=$(find "$ARCHIVE/Products" -name "*.o" 2>/dev/null | head -1 || true)
```

This takes **only the first .o** file from the archive. An SPM package with N source 
files produces N object files. The script discards all but one, so the resulting `.a` 
contains a tiny fraction of the actual code.

**Evidence**: `nm -g` on the produced `libLoomitOfferwallCore.a` returns **zero symbols** 
matching `OfferwallSdk`, `fetchConfig`, or `setLoomitApiKey`.

**Second critical bug**: The xcframeworks are created **without `.swiftmodule` files 
embedded**. The `.swiftmodule` is copied to a separate `SwiftModules/` directory, but:
- Unity doesn't know about this directory
- Xcode's build system doesn't pick it up via `SWIFT_INCLUDE_PATHS`
- Without `.swiftmodule`, Swift can't find the module's type metadata at link time

### 2.2. The bridge architecture is ad-hoc

The current approach was:
```
C# (DllImport) → ObjC++ (.mm) → Swift (@_cdecl) → OfferwallSdk (actor)
```

Problems with this approach:
- **Four layers** instead of three (the .mm → Swift hop is unnecessary complexity)
- `@_cdecl` is an **unstable Swift attribute** — not guaranteed across Swift versions
- The Swift bridge file imports `LoomitOfferwallCore` but the xcframeworks don't 
  provide linkable symbols, so every `import` causes undefined symbol errors
- Actor isolation (`OfferwallSdk` is a Swift `actor`) adds concurrency complexity 
  that `@_cdecl` synchronous functions can't handle cleanly

### 2.3. Comparison with the working Android bridge

The Android bridge works because:

```
C# (AndroidJavaClass) → Kotlin (UnityOfferwallBridge object, @JvmStatic) → OfferwallSdk
```

Key differences:
| Aspect | Android (works) | iOS (broken) |
|--------|----------------|--------------|
| Distribution | AAR (complete, self-contained) | xcframework (broken build) |
| Bridge location | Inside offerwall-core module | External Swift file copied by Unity |
| Linking | Gradle resolves everything | Manual xcframework + manual Xcode config |
| Concurrency | Coroutines (bridge manages scope) | Actor isolation (no clean @_cdecl path) |
| API key | gradle.properties → BuildConfig | Not implemented |

---

## 3. Industry Best Practices for Swift → Unity

### 3.1. Proven pattern: Objective-C façade + static framework

The industry-standard approach for wrapping a Swift SDK for Unity iOS is:

```
┌────────────────────────────────────────────────────────────────┐
│  Unity C# Layer                                                │
│  OfferwallSDKUnity.cs  [DllImport("__Internal")]              │
└───────────────────────────┬────────────────────────────────────┘
                            │ C function calls
                            ▼
┌────────────────────────────────────────────────────────────────┐
│  Objective-C Façade (.m file, compiled into Unity's Xcode)     │
│  LoomitOfferwallBridge.m                                       │
│  - Pure C functions (extern "C")                               │
│  - Calls @objc-marked Swift wrapper class                      │
│  - Manages memory (strdup for returned strings)                │
└───────────────────────────┬────────────────────────────────────┘
                            │ @objc method calls
                            ▼
┌────────────────────────────────────────────────────────────────┐
│  Swift Wrapper Class (inside the static framework)             │
│  LoomitUnityBridge.swift — @objc class, NOT actor              │
│  - Wraps async OfferwallSdk calls in Task {}                   │
│  - Serializes responses to JSON                                │
│  - Calls UnitySendMessage for callbacks                        │
└───────────────────────────┬────────────────────────────────────┘
                            │ await
                            ▼
┌────────────────────────────────────────────────────────────────┐
│  OfferwallSdk (actor)                                          │
│  LoomitOfferwallCore framework                                 │
└────────────────────────────────────────────────────────────────┘
```

### 3.2. Key principles

1. **Swift wrapper class MUST be `@objc class`, NOT actor, NOT `@_cdecl`**
   - `@objc` is stable, supported, and testable
   - The class bridges actor isolation internally via `Task {}`
   - The ObjC layer calls it via normal method dispatch

2. **The SDK MUST be distributed as a proper static xcframework**
   - Built with `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`
   - Contains the `.swiftmodule` inside the xcframework bundle
   - Contains ALL object files (not just the first one)

3. **The ObjC façade MUST use pure C linkage**
   - `extern "C"` for all functions called by C#
   - No C++ mangling, no Swift mangling
   - Returns `const char*` (strdup'd) for strings

4. **API key storage MUST follow the same pattern as Android**
   - Android: `gradle.properties` → `BuildConfig.LOOMIT_API_KEY`
   - iOS equivalent: `Info.plist` entry `LoomitApiKey`
   - The bridge reads it automatically, no hardcoded keys in code

### 3.3. Why NOT `@_cdecl`?

| `@_cdecl` | `@objc` class |
|-----------|---------------|
| Unstable Swift attribute | Stable, Apple-supported |
| Can't use Swift types in params | Full Swift type support |
| No class context (free functions) | Instance methods with state |
| Hard to test | Easy to unit test |
| Linker issues with optimizations | Standard ObjC dispatch |

---

## 4. Proposed Architecture

### 4.1. Module structure

```
ios/
├── LoomitOfferwallCore/          ← existing, no changes needed
├── LoomitOfferwallAdapterAPI/    ← existing, no changes needed  
├── LoomitOfferwallAdapterMyChips/
├── LoomitOfferwallAdapterTapjoy/
├── LoomitUnityBridge/            ← NEW: SPM package
│   ├── Package.swift
│   └── Sources/
│       └── LoomitUnityBridge/
│           └── LoomitUnityBridge.swift    ← @objc wrapper class
└── scripts/
    └── build_unity_xcframeworks.sh        ← REWRITE

unity-sample-app-unity6/Assets/Plugins/iOS/
├── LoomitOfferwallBridge.m               ← REWRITE (pure ObjC, not ObjC++)
├── LoomitOfferwallBridge.h               ← UPDATE
├── LoomitOfferwallCore.xcframework       ← fixed build
├── LoomitOfferwallAdapterAPI.xcframework
├── LoomitUnityBridge.xcframework         ← NEW
└── ... (other xcframeworks)
```

### 4.2. LoomitUnityBridge.swift (inside the framework)

```swift
import Foundation
import LoomitOfferwallCore
import LoomitOfferwallAdapterAPI

/// @objc wrapper that bridges Unity ↔ OfferwallSdk actor.
/// Lives INSIDE the xcframework so it links against the SDK at build time.
@objc public class LoomitUnityBridge: NSObject {

    @objc public static let shared = LoomitUnityBridge()
    
    private let sdk = OfferwallSdk.shared
    private var unityGameObject: String = "LoomitOfferwallManager"
    
    // MARK: - Initialization
    
    @objc public func initialize(gameObject: String, clientId: String, 
                                  userId: String?, appId: String?) {
        unityGameObject = gameObject
        Task {
            if let apiKey = self.resolveApiKey() {
                await sdk.setLoomitApiKey(apiKey)
            }
            if let cid = clientId.nilIfEmpty { await sdk.setClientId(cid) }
            if let uid = userId?.nilIfEmpty { await sdk.setPublisherUserId(uid) }
            if let aid = appId?.nilIfEmpty { await sdk.setAppId(aid) }
            await sdk.setListener(self)
        }
    }
    
    // MARK: - Fetch Config
    
    @objc public func fetchConfig(clientId: String, appId: String?) {
        Task {
            do {
                let config = try await sdk.fetchConfig()
                let json = try String(data: JSONEncoder().encode(config), encoding: .utf8) ?? "{}"
                self.sendToUnity("OnConfigFetched", message: json)
            } catch {
                self.sendToUnity("OnConfigFetchFailed", message: error.localizedDescription)
            }
        }
    }
    
    // MARK: - API Key Resolution (mirrors Android pattern)
    
    private func resolveApiKey() -> String? {
        // Read from Info.plist (equivalent of gradle.properties on Android)
        return Bundle.main.object(forInfoDictionaryKey: "LoomitApiKey") as? String
    }
    
    // MARK: - Unity Communication
    
    private func sendToUnity(_ method: String, message: String) {
        let goName = unityGameObject
        DispatchQueue.main.async {
            goName.withCString { go in
                method.withCString { m in
                    message.withCString { msg in
                        UnitySendMessage(go, m, msg)
                    }
                }
            }
        }
    }
}
```

### 4.3. LoomitOfferwallBridge.m (ObjC façade, in Unity project)

```objc
#import <Foundation/Foundation.h>

// Forward declaration — resolved at link time from LoomitUnityBridge.xcframework
@class LoomitUnityBridge;

// Unity's UnitySendMessage (provided by Unity runtime)
extern void UnitySendMessage(const char* obj, const char* method, const char* msg);

extern "C" {

void loomit_initialize(const char* gameObject, const char* clientId, 
                        const char* userId, const char* appId) {
    NSString *go   = [NSString stringWithUTF8String:gameObject ?: ""];
    NSString *cid  = [NSString stringWithUTF8String:clientId ?: ""];
    NSString *uid  = userId ? [NSString stringWithUTF8String:userId] : nil;
    NSString *aid  = appId ? [NSString stringWithUTF8String:appId] : nil;
    
    [[LoomitUnityBridge shared] initializeWithGameObject:go 
                                                clientId:cid 
                                                  userId:uid 
                                                   appId:aid];
}

void loomit_fetchConfig(const char* clientId, const char* appId) {
    NSString *cid = [NSString stringWithUTF8String:clientId ?: ""];
    NSString *aid = appId ? [NSString stringWithUTF8String:appId] : nil;
    [[LoomitUnityBridge shared] fetchConfigWithClientId:cid appId:aid];
}

// ... remaining functions follow the same pattern

} // extern "C"
```

### 4.4. API Key in Info.plist

For iOS Unity, the API key goes in `Info.plist` (set via Unity's Player Settings 
or a PostProcessBuild script):

```xml
<key>LoomitApiKey</key>
<string>YOUR_LOOMIT_API_KEY</string>
```

This mirrors the Android pattern where `gradle.properties` holds `loomitApiKey`.

The bridge reads it automatically via `Bundle.main.object(forInfoDictionaryKey:)`.

**PostProcessBuild script** can inject it from a Unity ScriptableObject config:
```csharp
[PostProcessBuild]
static void OnPostProcessBuild(BuildTarget target, string path) {
    if (target == BuildTarget.iOS) {
        string plistPath = Path.Combine(path, "Info.plist");
        var plist = new PlistDocument();
        plist.ReadFromFile(plistPath);
        plist.root.SetString("LoomitApiKey", LoomitConfig.ApiKey);
        plist.WriteToFile(plistPath);
    }
}
```

---

## 5. Fix for xcframework build script

### 5.1. Core fix: collect ALL object files

Replace the broken `head -1` pattern with proper library extraction:

```bash
# Instead of finding one .o, find the built static library directly
# xcodebuild archive with SKIP_INSTALL=NO produces a proper .a in the archive
STATIC_LIB=$(find "$ARCHIVE/Products" -name "lib${TARGET}.a" 2>/dev/null | head -1)

# If no .a, collect ALL .o files and create a proper archive
if [ -z "$STATIC_LIB" ]; then
    ALL_OBJS=$(find "$ARCHIVE/Products" -name "*.o" 2>/dev/null)
    if [ -n "$ALL_OBJS" ]; then
        STATIC_LIB="$OUT_DIR/lib${TARGET}.a"
        ar cr "$STATIC_LIB" $ALL_OBJS
        ranlib "$STATIC_LIB"
    fi
fi
```

### 5.2. Include swiftmodule in xcframework

```bash
# When creating xcframework, include -headers for the swiftmodule
xcodebuild -create-xcframework \
    -library "$DEVICE_LIB" -headers "$DEVICE_SWIFTMODULE_DIR" \
    -library "$SIM_LIB" -headers "$SIM_SWIFTMODULE_DIR" \
    -output "$XCFW_OUT"
```

### 5.3. Validation step

Add a post-build validation:
```bash
# Verify the xcframework has the expected symbols
nm -g "$XCFW_OUT/ios-arm64_x86_64-simulator/lib${TARGET}.a" | grep "OfferwallSdk" || {
    echo "❌ FATAL: xcframework for $TARGET has no OfferwallSdk symbols"
    exit 1
}
```

---

## 6. Implementation Plan (Phased)

### Phase 0: Validate the theory (1 hour)
- [ ] Fix the build script to collect ALL .o files
- [ ] Rebuild xcframeworks
- [ ] Verify with `nm -g` that symbols exist
- [ ] If symbols exist → the xcframework approach IS viable, proceed to Phase 1
- [ ] If symbols don't exist → need alternative approach (see §7)

### Phase 1: Minimal viable bridge (half day)
- [ ] Create `LoomitUnityBridge` SPM package with @objc wrapper class
- [ ] Implement only: `initialize()`, `fetchConfig()`, `sendToUnity()`
- [ ] Rewrite build script to produce proper xcframeworks with swiftmodule
- [ ] Rewrite `LoomitOfferwallBridge.m` (pure ObjC façade, 3 functions only)
- [ ] Build from Unity → Xcode → verify BUILD SUCCEEDED
- [ ] Run on simulator → verify fetchConfig callback reaches Unity C#

### Phase 2: Complete bridge parity (1 day)
- [ ] Add all remaining functions (show, close, setUserId, etc.)
- [ ] Implement OfferwallListener → UnitySendMessage forwarding
- [ ] Implement API key resolution from Info.plist
- [ ] Create PostProcessBuild script for API key injection
- [ ] Verify all DllImport functions in OfferwallSDKUnity.cs have matching C functions

### Phase 3: Automate & harden (half day)
- [ ] PostProcessBuild script auto-adds xcframeworks to Xcode project
- [ ] PostProcessBuild script sets SWIFT_INCLUDE_PATHS if needed
- [ ] CI validation: build script → Unity build → Xcode build → all green
- [ ] Update dist-unity scripts to include iOS xcframeworks

### Phase 4: Documentation & sample app (half day)
- [ ] Update Unity iOS integration guide
- [ ] Update sample app to demo iOS flow
- [ ] Document API key configuration for iOS
- [ ] Update ARCHITECTURE.md §6 with iOS Unity distribution

---

## 7. Contingency: If xcframeworks can't work

If Phase 0 reveals that xcframeworks fundamentally can't carry Swift actor symbols 
for Unity linking, the fallback is:

**Option B: Source-level inclusion**
- Copy the LoomitOfferwallCore Swift source files into the Unity project
- They compile as part of the Xcode project (no linking issues)
- Downside: exposes source code to publishers
- Upside: zero linking complexity, always up-to-date

This is actually what many Swift SDKs do for Unity (e.g., Firebase iOS uses 
source-level inclusion for some modules).

---

## 8. Decision Matrix

| Approach | Linking | Maintenance | Source Privacy | Complexity |
|----------|---------|-------------|----------------|------------|
| xcframework (fixed) | ✅ Proper | Medium | ✅ Binary | Medium |
| Source inclusion | ✅ Trivial | High (sync) | ❌ Exposed | Low |
| Dynamic framework | ❌ Unity issues | Low | ✅ Binary | High |
| CocoaPods/SPM | ❌ Unity incompatible | Low | ✅ Binary | Very High |

**Recommendation**: xcframework (fixed) as primary, source inclusion as fallback.

---

## 9. Immediate Next Step

**Phase 0**: Fix the build script and verify symbols exist. This takes ~1 hour 
and tells us definitively whether the xcframework approach is viable.

If you approve this plan, I'll start with Phase 0 immediately.
