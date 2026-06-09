//
//  TestRunner.swift
//  LoomitOfferwallCoreTests
//
//  Test runner for isolated component testing without UIKit dependencies.
//

import Foundation
import XCTest

/// Test runner for isolated component testing
class TestRunner {
    
    /// Run NetworkDiagnostics tests in isolation
    static func runNetworkDiagnosticsTests() {
        print("🧪 Running NetworkDiagnostics tests...")
        
        let testSuite = XCTestSuite(name: "NetworkDiagnosticsTests")
        
        // Add individual test methods
        testSuite.addTest(NetworkDiagnosticsTests(name: "testNetworkConnectivityDetection"))
        testSuite.addTest(NetworkDiagnosticsTests(name: "testCellularConnectivityDetection"))
        testSuite.addTest(NetworkDiagnosticsTests(name: "testNoNetworkConnectivity"))
        testSuite.addTest(NetworkDiagnosticsTests(name: "testHostConnectivityCheckSuccess"))
        testSuite.addTest(NetworkDiagnosticsTests(name: "testHostConnectivityCheckFailure"))
        testSuite.addTest(NetworkDiagnosticsTests(name: "testMultipleHostConnectivity"))
        testSuite.addTest(NetworkDiagnosticsTests(name: "testHostExtractionFromURL"))
        testSuite.addTest(NetworkDiagnosticsTests(name: "testDuplicateHostHandling"))
        testSuite.addTest(NetworkDiagnosticsTests(name: "testEmptyHostsList"))
        testSuite.addTest(NetworkDiagnosticsTests(name: "testNetworkDiagnosticsSummary"))
        testSuite.addTest(NetworkDiagnosticsTests(name: "testNetworkDiagnosticsPerformance"))
        testSuite.addTest(NetworkDiagnosticsTests(name: "testHostCheckTimeoutPerformance"))
        
        let testRun = XCTestSuiteRun(test: testSuite)
        testSuite.run(testRun)
        
        print("✅ NetworkDiagnostics tests completed")
        print("📊 Tests run: \(testRun.testCaseCount)")
        print("❌ Failures: \(testRun.failureCount)")
        print("⏱️ Duration: \(testRun.testDuration)s")
    }
    
    /// Run PrivacyResolver tests in isolation
    static func runPrivacyResolverTests() {
        print("🧪 Running PrivacyResolver tests...")
        
        let testSuite = XCTestSuite(name: "PrivacyResolverTests")
        
        testSuite.addTest(PrivacyResolverTests(name: "testTCFConsentStringReading"))
        testSuite.addTest(PrivacyResolverTests(name: "testTCFConsentStringEmpty"))
        testSuite.addTest(PrivacyResolverTests(name: "testTCFConsentStringWhitespace"))
        testSuite.addTest(PrivacyResolverTests(name: "testTCFGdprAppliesTrue"))
        testSuite.addTest(PrivacyResolverTests(name: "testTCFGdprAppliesFalse"))
        testSuite.addTest(PrivacyResolverTests(name: "testTCFGdprAppliesInvalid"))
        testSuite.addTest(PrivacyResolverTests(name: "testTCFGdprAppliesMissing"))
        testSuite.addTest(PrivacyResolverTests(name: "testUSPrivacyStringReading"))
        testSuite.addTest(PrivacyResolverTests(name: "testUSPrivacyStringEmpty"))
        testSuite.addTest(PrivacyResolverTests(name: "testUSPrivacyStringWhitespace"))
        testSuite.addTest(PrivacyResolverTests(name: "testAllSignalsPresent"))
        testSuite.addTest(PrivacyResolverTests(name: "testNoSignalsPresent"))
        testSuite.addTest(PrivacyResolverTests(name: "testGDPRInferenceEUCountry"))
        testSuite.addTest(PrivacyResolverTests(name: "testGDPRInferenceUKCountry"))
        testSuite.addTest(PrivacyResolverTests(name: "testGDPRInferenceNoLocale"))
        testSuite.addTest(PrivacyResolverTests(name: "testATTStatusAuthorized"))
        testSuite.addTest(PrivacyResolverTests(name: "testATTStatusNotSupported"))
        testSuite.addTest(PrivacyResolverTests(name: "testPrivacyStateEquality"))
        testSuite.addTest(PrivacyResolverTests(name: "testPrivacyStateWithNilValues"))
        testSuite.addTest(PrivacyResolverTests(name: "testPrivacyStateWithPartialValues"))
        testSuite.addTest(PrivacyResolverTests(name: "testPrivacyResolverPerformance"))
        testSuite.addTest(PrivacyResolverTests(name: "testGDPRInferencePerformance"))
        
        let testRun = XCTestSuiteRun(test: testSuite)
        testSuite.run(testRun)
        
        print("✅ PrivacyResolver tests completed")
        print("📊 Tests run: \(testRun.testCaseCount)")
        print("❌ Failures: \(testRun.failureCount)")
        print("⏱️ Duration: \(testRun.testDuration)s")
    }
    
    /// Run EmergencyConfigLoader tests in isolation
    static func runEmergencyConfigLoaderTests() {
        print("🧪 Running EmergencyConfigLoader tests...")
        
        let testSuite = XCTestSuite(name: "EmergencyConfigLoaderTests")
        
        testSuite.addTest(EmergencyConfigLoaderTests(name: "testLoadValidEmergencyConfig"))
        testSuite.addTest(EmergencyConfigLoaderTests(name: "testLoadEmergencyConfigWithProviders"))
        testSuite.addTest(EmergencyConfigLoaderTests(name: "testLoadConfigFileNotFound"))
        testSuite.addTest(EmergencyConfigLoaderTests(name: "testLoadConfigFileCorrupted"))
        testSuite.addTest(EmergencyConfigLoaderTests(name: "testLoadConfigFileEmpty"))
        testSuite.addTest(EmergencyConfigLoaderTests(name: "testLoadConfigFileReadError"))
        testSuite.addTest(EmergencyConfigLoaderTests(name: "testLoadConfigFileInvalidEncoding"))
        testSuite.addTest(EmergencyConfigLoaderTests(name: "testChecksumCalculation"))
        testSuite.addTest(EmergencyConfigLoaderTests(name: "testChecksumConsistency"))
        testSuite.addTest(EmergencyConfigLoaderTests(name: "testTimestampGeneration"))
        testSuite.addTest(EmergencyConfigLoaderTests(name: "testConfigSourceSet"))
        testSuite.addTest(EmergencyConfigLoaderTests(name: "testLoadPerformance"))
        testSuite.addTest(EmergencyConfigLoaderTests(name: "testChecksumPerformance"))
        
        let testRun = XCTestSuiteRun(test: testSuite)
        testSuite.run(testRun)
        
        print("✅ EmergencyConfigLoader tests completed")
        print("📊 Tests run: \(testRun.testCaseCount)")
        print("❌ Failures: \(testRun.failureCount)")
        print("⏱️ Duration: \(testRun.testDuration)s")
    }
    
    /// Run all component tests
    static func runAllComponentTests() {
        print("🚀 Starting Backend Client component tests...")
        print("=" * 50)
        
        runNetworkDiagnosticsTests()
        print("-" * 50)
        
        runPrivacyResolverTests()
        print("-" * 50)
        
        runEmergencyConfigLoaderTests()
        print("=" * 50)
        
        print("🎉 All component tests completed!")
    }
}

// MARK: - String Extension for Repetition

extension String {
    static func *(lhs: String, rhs: Int) -> String {
        return String(repeating: lhs, count: rhs)
    }
}
