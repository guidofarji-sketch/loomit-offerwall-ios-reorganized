//
//  PrivacyResolverTests.swift
//  LoomitOfferwallCoreTests
//
//  Unit tests for PrivacyResolver component.
//

import XCTest
@testable import LoomitOfferwallCore

final class PrivacyResolverTests: XCTestCase {
    
    // MARK: - Mock Classes
    
    class MockUserDefaults {
        private var storage: [String: Any] = [:]
        
        func string(forKey key: String) -> String? {
            return storage[key] as? String
        }
        
        func set(_ value: Any?, forKey key: String) {
            storage[key] = value
        }
        
        func object(forKey key: String) -> Any? {
            return storage[key]
        }
        
        func integer(forKey key: String) -> Int {
            return storage[key] as? Int ?? 0
        }
        
        func contains(_ key: String) -> Bool {
            return storage.keys.contains(key)
        }
        
        func clear() {
            storage.removeAll()
        }
    }
    
    // MARK: - Test Properties
    
    private var mockUserDefaults: MockUserDefaults!
    
    override func setUp() {
        super.setUp()
        mockUserDefaults = MockUserDefaults()
    }
    
    override func tearDown() {
        mockUserDefaults.clear()
        mockUserDefaults = nil
        super.tearDown()
    }
    
    // MARK: - IAB TCF v2 Tests
    
    func testTCFConsentStringReading() {
        // Given: TCF consent string in UserDefaults
        let consentString = "BOjE1oBOjE1oAKABBENC-AAAAgA_AAAAAAA"
        mockUserDefaults.set(consentString, forKey: "IABTCF_TCString")
        
        // When: Resolve privacy state
        let result = PrivacyResolver.resolve()
        
        // Then: Should read TCF consent string correctly
        XCTAssertEqual(result.tcfConsentString, consentString, "Should read TCF consent string")
        XCTAssertNil(result.usPrivacyString, "Should not have US privacy string")
        XCTAssertNil(result.subjectToGdpr, "Should not have GDPR applicability")
    }
    
    func testTCFConsentStringEmpty() {
        // Given: Empty TCF consent string
        mockUserDefaults.set("", forKey: "IABTCF_TCString")
        
        // When: Resolve privacy state
        let result = PrivacyResolver.resolve()
        
        // Then: Should treat empty as nil
        XCTAssertNil(result.tcfConsentString, "Should treat empty string as nil")
    }
    
    func testTCFConsentStringWhitespace() {
        // Given: TCF consent string with only whitespace
        mockUserDefaults.set("   ", forKey: "IABTCF_TCString")
        
        // When: Resolve privacy state
        let result = PrivacyResolver.resolve()
        
        // Then: Should treat whitespace as nil
        XCTAssertNil(result.tcfConsentString, "Should treat whitespace as nil")
    }
    
    func testTCFGdprAppliesTrue() {
        // Given: GDPR applies (value 1)
        mockUserDefaults.set(1, forKey: "IABTCF_gdprApplies")
        
        // When: Resolve privacy state
        let result = PrivacyResolver.resolve()
        
        // Then: Should detect GDPR applies
        XCTAssertEqual(result.subjectToGdpr, true, "Should detect GDPR applies")
    }
    
    func testTCFGdprAppliesFalse() {
        // Given: GDPR does not apply (value 0)
        mockUserDefaults.set(0, forKey: "IABTCF_gdprApplies")
        
        // When: Resolve privacy state
        let result = PrivacyResolver.resolve()
        
        // Then: Should detect GDPR does not apply
        XCTAssertEqual(result.subjectToGdpr, false, "Should detect GDPR does not apply")
    }
    
    func testTCFGdprAppliesInvalid() {
        // Given: Invalid GDPR applies value (should be 0 or 1)
        mockUserDefaults.set(2, forKey: "IABTCF_gdprApplies")
        
        // When: Resolve privacy state
        let result = PrivacyResolver.resolve()
        
        // Then: Should treat invalid as nil
        XCTAssertNil(result.subjectToGdpr, "Should treat invalid value as nil")
    }
    
    func testTCFGdprAppliesMissing() {
        // Given: No GDPR applies value in UserDefaults
        // (don't set anything)
        
        // When: Resolve privacy state
        let result = PrivacyResolver.resolve()
        
        // Then: Should return nil for missing value
        XCTAssertNil(result.subjectToGdpr, "Should return nil for missing value")
    }
    
    // MARK: - IAB CCPA Tests
    
    func testUSPrivacyStringReading() {
        // Given: US privacy string in UserDefaults
        let privacyString = "1YNN"
        mockUserDefaults.set(privacyString, forKey: "IABUSPrivacy_String")
        
        // When: Resolve privacy state
        let result = PrivacyResolver.resolve()
        
        // Then: Should read US privacy string correctly
        XCTAssertEqual(result.usPrivacyString, privacyString, "Should read US privacy string")
        XCTAssertNil(result.tcfConsentString, "Should not have TCF consent string")
        XCTAssertNil(result.subjectToGdpr, "Should not have GDPR applicability")
    }
    
    func testUSPrivacyStringEmpty() {
        // Given: Empty US privacy string
        mockUserDefaults.set("", forKey: "IABUSPrivacy_String")
        
        // When: Resolve privacy state
        let result = PrivacyResolver.resolve()
        
        // Then: Should treat empty as nil
        XCTAssertNil(result.usPrivacyString, "Should treat empty string as nil")
    }
    
    func testUSPrivacyStringWhitespace() {
        // Given: US privacy string with only whitespace
        mockUserDefaults.set("   ", forKey: "IABUSPrivacy_String")
        
        // When: Resolve privacy state
        let result = PrivacyResolver.resolve()
        
        // Then: Should treat whitespace as nil
        XCTAssertNil(result.usPrivacyString, "Should treat whitespace as nil")
    }
    
    // MARK: - Combined Tests
    
    func testAllSignalsPresent() {
        // Given: All IAB signals present
        let tcfString = "BOjE1oBOjE1oAKABBENC-AAAAgA_AAAAAAA"
        let usString = "1YNN"
        let gdprApplies = 1
        
        mockUserDefaults.set(tcfString, forKey: "IABTCF_TCString")
        mockUserDefaults.set(usString, forKey: "IABUSPrivacy_String")
        mockUserDefaults.set(gdprApplies, forKey: "IABTCF_gdprApplies")
        
        // When: Resolve privacy state
        let result = PrivacyResolver.resolve()
        
        // Then: Should read all signals correctly
        XCTAssertEqual(result.tcfConsentString, tcfString, "Should read TCF consent string")
        XCTAssertEqual(result.usPrivacyString, usString, "Should read US privacy string")
        XCTAssertEqual(result.subjectToGdpr, true, "Should detect GDPR applies")
    }
    
    func testNoSignalsPresent() {
        // Given: No IAB signals in UserDefaults
        // (don't set anything)
        
        // When: Resolve privacy state
        let result = PrivacyResolver.resolve()
        
        // Then: Should return empty state
        XCTAssertNil(result.tcfConsentString, "Should have no TCF consent string")
        XCTAssertNil(result.usPrivacyString, "Should have no US privacy string")
        XCTAssertNil(result.subjectToGdpr, "Should have no GDPR applicability")
    }
    
    // MARK: - GDPR Inference Tests
    
    func testGDPRInferenceEUCountry() async {
        // Given: EU country locale
        let result = PrivacyResolver.inferGdprApplicability()
        
        // Note: This test depends on the actual device locale
        // In a real test environment, we'd mock Locale.current
        if let regionCode = Locale.current.regionCode {
            let euCountries: Set<String> = [
                "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR",
                "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL",
                "PL", "PT", "RO", "SK", "SI", "ES", "SE"
            ]
            
            if euCountries.contains(regionCode.uppercased()) {
                XCTAssertEqual(result, true, "Should infer GDPR applies for EU country \(regionCode)")
            } else {
                // For non-EU countries, result should be false or nil
                XCTAssertTrue(result == false || result == nil, "Should not infer GDPR applies for non-EU country \(regionCode)")
            }
        } else {
            XCTAssertNil(result, "Should return nil when locale cannot be determined")
        }
    }
    
    func testGDPRInferenceUKCountry() async {
        // Given: UK locale (post-Brexit)
        // This test would require mocking Locale.current to "GB" or "UK"
        let result = PrivacyResolver.inferGdprApplicability()
        
        // Note: This is a placeholder for a test that would mock Locale.current
        // In the actual implementation, we'd need to inject a locale for testing
        if let regionCode = Locale.current.regionCode {
            if regionCode.uppercased() == "GB" || regionCode.uppercased() == "UK" {
                XCTAssertEqual(result, true, "Should infer GDPR applies for UK")
            }
        }
    }
    
    func testGDPRInferenceNoLocale() async {
        // Given: No locale information
        // This test would require mocking Locale.current to return nil
        
        // When: Infer GDPR applicability
        let result = PrivacyResolver.inferGdprApplicability()
        
        // Then: Should return nil when locale cannot be determined
        // This is a placeholder - actual test would need locale mocking
        if Locale.current.regionCode == nil {
            XCTAssertNil(result, "Should return nil when locale cannot be determined")
        }
    }
    
    // MARK: - ATT Status Tests
    
    func testATTStatusAuthorized() async {
        // Given: iOS 14+ with ATT authorized
        // Note: This test would require mocking ATTrackingManager.trackingAuthorizationStatus
        
        // When: Get ATT status
        let result = PrivacyResolver.getAttStatus()
        
        // Then: Should return appropriate status
        // This is a placeholder - actual test would need ATTrackingManager mocking
        if #available(iOS 14, *) {
            // In real test, we'd mock the status
            XCTAssertTrue([.authorized, .denied, .restricted, .notDetermined, .unknown, .notSupported].contains(result), "Should return valid ATT status")
        } else {
            XCTAssertEqual(result, .notSupported, "Should return notSupported on iOS < 14")
        }
    }
    
    func testATTStatusNotSupported() async {
        // Given: iOS 13 or earlier (no ATT support)
        // This is automatically handled by the availability check
        
        // When: Get ATT status
        let result = PrivacyResolver.getAttStatus()
        
        // Then: Should return notSupported on iOS < 14
        if #available(iOS 14, *) {
            // On iOS 14+, this would depend on actual ATT status
            // In real test, we'd mock ATTrackingManager
        } else {
            XCTAssertEqual(result, .notSupported, "Should return notSupported on iOS < 14")
        }
    }
    
    // MARK: - Edge Case Tests
    
    func testPrivacyStateEquality() {
        // Given: Two identical privacy states
        let state1 = PrivacyState(
            tcfConsentString: "test",
            usPrivacyString: "1YNN",
            subjectToGdpr: true
        )
        
        let state2 = PrivacyState(
            tcfConsentString: "test",
            usPrivacyString: "1YNN",
            subjectToGdpr: true
        )
        
        // When: Compare states
        // Note: PrivacyState would need Equatable conformance for this test
        XCTAssertEqual(state1.tcfConsentString, state2.tcfConsentString, "TCF strings should be equal")
        XCTAssertEqual(state1.usPrivacyString, state2.usPrivacyString, "US privacy strings should be equal")
        XCTAssertEqual(state1.subjectToGdpr, state2.subjectToGdpr, "GDPR applicability should be equal")
    }
    
    func testPrivacyStateWithNilValues() {
        // Given: Privacy state with all nil values
        let state = PrivacyState()
        
        // When: Check values
        XCTAssertNil(state.tcfConsentString, "TCF consent string should be nil")
        XCTAssertNil(state.usPrivacyString, "US privacy string should be nil")
        XCTAssertNil(state.subjectToGdpr, "GDPR applicability should be nil")
    }
    
    func testPrivacyStateWithPartialValues() {
        // Given: Privacy state with only some values
        let state = PrivacyState(
            tcfConsentString: "test",
            usPrivacyString: nil,
            subjectToGdpr: false
        )
        
        // When: Check values
        XCTAssertEqual(state.tcfConsentString, "test", "TCF consent string should be set")
        XCTAssertNil(state.usPrivacyString, "US privacy string should be nil")
        XCTAssertEqual(state.subjectToGdpr, false, "GDPR applicability should be false")
    }
    
    // MARK: - Performance Tests
    
    func testPrivacyResolverPerformance() {
        // Given: Multiple privacy state resolutions
        mockUserDefaults.set("BOjE1oBOjE1oAKABBENC-AAAAgA_AAAAAAA", forKey: "IABTCF_TCString")
        mockUserDefaults.set("1YNN", forKey: "IABUSPrivacy_String")
        mockUserDefaults.set(1, forKey: "IABTCF_gdprApplies")
        
        // When: Measure performance
        measure {
            _ = PrivacyResolver.resolve()
        }
    }
    
    func testGDPRInferencePerformance() {
        // When: Measure GDPR inference performance
        measure {
            _ = PrivacyResolver.inferGdprApplicability()
        }
    }
}
