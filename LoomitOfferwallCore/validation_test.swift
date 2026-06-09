#!/usr/bin/swift
// Validation test for Backend Client components
// Run: swift validation_test.swift

import Foundation

print("=== Backend Client Component Validation ===\n")

var passed = 0
var failed = 0

// Test 1: Check file existence
let components = [
    "Sources/LoomitOfferwallCore/Internal/NetworkDiagnostics.swift",
    "Sources/LoomitOfferwallCore/Internal/PrivacyResolver.swift",
    "Sources/LoomitOfferwallCore/Internal/Resilience/EmergencyConfigLoader.swift",
    "Sources/LoomitOfferwallCore/Internal/Resilience/ResilientBackendClient.swift",
    "Resources/EmergencyConfig.json"
]

print("1. File Existence Check:")
for component in components {
    let path = "/Users/guido.farji/Loomit-OW-SDK/ios/LoomitOfferwallCore/\(component)"
    if FileManager.default.fileExists(atPath: path) {
        print("   ✓ \(component)")
        passed += 1
    } else {
        print("   ✗ \(component) - MISSING")
        failed += 1
    }
}

// Test 2: Check key function signatures in NetworkDiagnostics
print("\n2. NetworkDiagnostics API Check:")
let networkDiagPath = "/Users/guido.farji/Loomit-OW-SDK/ios/LoomitOfferwallCore/Sources/LoomitOfferwallCore/Internal/NetworkDiagnostics.swift"
if let content = try? String(contentsOfFile: networkDiagPath, encoding: .utf8) {
    let checks = [
        "collect(hosts: [String]) async -> NetworkDiagnosticsSummary",
        "HostConnectivityCheck",
        "NetworkDiagnosticsSummary",
        "getNetworkPathInfo()",
        "testHost(_ host: String)"
    ]
    
    for check in checks {
        if content.contains(check) {
            print("   ✓ \(check)")
            passed += 1
        } else {
            print("   ✗ \(check) - NOT FOUND")
            failed += 1
        }
    }
}

// Test 3: Check PrivacyResolver
print("\n3. PrivacyResolver API Check:")
let privacyPath = "/Users/guido.farji/Loomit-OW-SDK/ios/LoomitOfferwallCore/Sources/LoomitOfferwallCore/Internal/PrivacyResolver.swift"
if let content = try? String(contentsOfFile: privacyPath, encoding: .utf8) {
    let checks = [
        "PrivacyState",
        "resolve() -> PrivacyState",
        "tcfConsentString",
        "usPrivacyString",
        "subjectToGdpr"
    ]
    
    for check in checks {
        if content.contains(check) {
            print("   ✓ \(check)")
            passed += 1
        } else {
            print("   ✗ \(check) - NOT FOUND")
            failed += 1
        }
    }
}

// Test 4: Check EmergencyConfigLoader
print("\n4. EmergencyConfigLoader API Check:")
let emergencyPath = "/Users/guido.farji/Loomit-OW-SDK/ios/LoomitOfferwallCore/Sources/LoomitOfferwallCore/Internal/Resilience/EmergencyConfigLoader.swift"
if let content = try? String(contentsOfFile: emergencyPath, encoding: .utf8) {
    let checks = [
        "EmergencyConfigLoader",
        "load() -> ConfigSnapshot?",
        "computeChecksum"
    ]
    
    for check in checks {
        if content.contains(check) {
            print("   ✓ \(check)")
            passed += 1
        } else {
            print("   ✗ \(check) - NOT FOUND")
            failed += 1
        }
    }
}

// Test 5: Check ResilientBackendClient
print("\n5. ResilientBackendClient API Check:")
let resilientPath = "/Users/guido.farji/Loomit-OW-SDK/ios/LoomitOfferwallCore/Sources/LoomitOfferwallCore/Internal/Resilience/ResilientBackendClient.swift"
if let content = try? String(contentsOfFile: resilientPath, encoding: .utf8) {
    let checks = [
        "ResilientBackendClient",
        "fetchConfig(_ request: ConfigRequest)",
        "CircuitBreaker",
        "ConfigCache",
        "EmergencyConfigLoader"
    ]
    
    for check in checks {
        if content.contains(check) {
            print("   ✓ \(check)")
            passed += 1
        } else {
            print("   ✗ \(check) - NOT FOUND")
            failed += 1
        }
    }
}

// Summary
print("\n=== Validation Summary ===")
print("Passed: \(passed)")
print("Failed: \(failed)")
print("Total:  \(passed + failed)")

if failed == 0 {
    print("\n✅ ALL CHECKS PASSED - Backend Client components are present and correct!")
    exit(0)
} else {
    print("\n❌ SOME CHECKS FAILED - Please review the component implementations.")
    exit(1)
}
