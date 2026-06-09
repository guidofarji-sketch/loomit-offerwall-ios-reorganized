//
//  EmergencyConfigLoaderTests.swift
//  LoomitOfferwallCoreTests
//
//  Unit tests for EmergencyConfigLoader component.
//

import XCTest
@testable import LoomitOfferwallCore

final class EmergencyConfigLoaderTests: XCTestCase {
    
    // MARK: - Mock Classes
    
    class MockBundle {
        var mockURL: URL?
        var mockData: Data?
        var shouldThrowError = false
        var errorToThrow: Error?
        
        func url(forResource name: String, withExtension ext: String) -> URL? {
            return mockURL
        }
        
        func dataFromContents(of url: URL) throws -> Data {
            if shouldThrowError {
                throw errorToThrow ?? NSError(domain: "MockError", code: -1, userInfo: nil)
            }
            return mockData ?? Data()
        }
    }
    
    // MARK: - Test Properties
    
    private var mockBundle: MockBundle!
    private var emergencyConfigLoader: EmergencyConfigLoader!
    
    override func setUp() {
        super.setUp()
        mockBundle = MockBundle()
        emergencyConfigLoader = EmergencyConfigLoader()
    }
    
    override func tearDown() {
        mockBundle = nil
        emergencyConfigLoader = nil
        super.tearDown()
    }
    
    // MARK: - Valid Config Tests
    
    func testLoadValidEmergencyConfig() {
        // Given: Valid emergency config JSON
        let validConfigJSON = """
        {
            "configurations": [],
            "ab_tests": [],
            "ab_test": {
                "experiment_name": "Emergency Fallback",
                "group": "control",
                "experiment_id": "emergency-fallback"
            },
            "experiments": [],
            "segment": {
                "id": "emergency",
                "name": "Emergency Segment"
            },
            "logging": {
                "enabled": true,
                "sampling_rate": 0.1
            },
            "resilience": {
                "backend_circuit_breaker": {
                    "failure_threshold": 5,
                    "success_threshold": 2,
                    "open_duration_ms": 60000
                }
            }
        }
        """
        
        let configData = validConfigJSON.data(using: .utf8)!
        mockBundle.mockData = configData
        mockBundle.mockURL = URL(fileURLWithPath: "/tmp/EmergencyConfig.json")
        
        // When: Load emergency config
        let result = emergencyConfigLoader.load()
        
        // Then: Should load successfully
        XCTAssertNotNil(result, "Should load emergency config")
        XCTAssertEqual(result?.config.configurations.count, 0, "Should have 0 configurations")
        XCTAssertEqual(result?.config.ab_test.experiment_name, "Emergency Fallback", "Should have correct experiment name")
        XCTAssertEqual(result?.source, .emergency, "Should have emergency source")
        XCTAssertNotNil(result?.timestamp, "Should have timestamp")
        XCTAssertNotNil(result?.checksum, "Should have checksum")
    }
    
    func testLoadEmergencyConfigWithProviders() {
        // Given: Emergency config with provider configurations
        let configWithProviders = """
        {
            "configurations": [
                {
                    "provider_id": "tapjoy",
                    "is_active": true,
                    "segment_priority": 1,
                    "provider_priority": 1,
                    "credentials": {
                        "sdk_key": "test_key"
                    }
                },
                {
                    "provider_id": "dt",
                    "is_active": true,
                    "segment_priority": 2,
                    "provider_priority": 2,
                    "credentials": {
                        "app_id": "test_app_id"
                    }
                }
            ],
            "ab_tests": [],
            "ab_test": {
                "experiment_name": "Emergency Fallback",
                "group": "control",
                "experiment_id": "emergency-fallback"
            },
            "experiments": [],
            "segment": {
                "id": "emergency",
                "name": "Emergency Segment"
            },
            "logging": {
                "enabled": true,
                "sampling_rate": 0.1
            },
            "resilience": {
                "backend_circuit_breaker": {
                    "failure_threshold": 5,
                    "success_threshold": 2,
                    "open_duration_ms": 60000
                }
            }
        }
        """
        
        let configData = configWithProviders.data(using: .utf8)!
        mockBundle.mockData = configData
        mockBundle.mockURL = URL(fileURLWithPath: "/tmp/EmergencyConfig.json")
        
        // When: Load emergency config
        let result = emergencyConfigLoader.load()
        
        // Then: Should load providers correctly
        XCTAssertNotNil(result, "Should load emergency config")
        XCTAssertEqual(result?.config.configurations.count, 2, "Should have 2 configurations")
        
        let tapjoyConfig = result?.config.configurations.first { $0.provider_id == "tapjoy" }
        XCTAssertNotNil(tapjoyConfig, "Should have tapjoy configuration")
        XCTAssertEqual(tapjoyConfig?.provider_priority, 1, "Should have correct priority")
        
        let dtConfig = result?.config.configurations.first { $0.provider_id == "dt" }
        XCTAssertNotNil(dtConfig, "Should have dt configuration")
        XCTAssertEqual(dtConfig?.provider_priority, 2, "Should have correct priority")
    }
    
    // MARK: - Error Handling Tests
    
    func testLoadConfigFileNotFound() {
        // Given: No config file in bundle
        mockBundle.mockURL = nil
        
        // When: Load emergency config
        let result = emergencyConfigLoader.load()
        
        // Then: Should return nil
        XCTAssertNil(result, "Should return nil when file not found")
    }
    
    func testLoadConfigFileCorrupted() {
        // Given: Invalid JSON data
        let invalidJSON = """
        {
            "configurations": [
                {
                    "provider_id": "tapjoy",
                    "is_active": true,
                    // Missing required fields - invalid JSON
        """
        
        let configData = invalidJSON.data(using: .utf8)!
        mockBundle.mockData = configData
        mockBundle.mockURL = URL(fileURLWithPath: "/tmp/EmergencyConfig.json")
        
        // When: Load emergency config
        let result = emergencyConfigLoader.load()
        
        // Then: Should return nil due to JSON parsing error
        XCTAssertNil(result, "Should return nil for invalid JSON")
    }
    
    func testLoadConfigFileEmpty() {
        // Given: Empty config file
        let emptyData = Data()
        mockBundle.mockData = emptyData
        mockBundle.mockURL = URL(fileURLWithPath: "/tmp/EmergencyConfig.json")
        
        // When: Load emergency config
        let result = emergencyConfigLoader.load()
        
        // Then: Should return nil for empty file
        XCTAssertNil(result, "Should return nil for empty file")
    }
    
    func testLoadConfigFileReadError() {
        // Given: File read error
        mockBundle.mockURL = URL(fileURLWithPath: "/tmp/EmergencyConfig.json")
        mockBundle.shouldThrowError = true
        mockBundle.errorToThrow = NSError(domain: "FileError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
        
        // When: Load emergency config
        let result = emergencyConfigLoader.load()
        
        // Then: Should return nil due to read error
        XCTAssertNil(result, "Should return nil for file read error")
    }
    
    func testLoadConfigFileInvalidEncoding() {
        // Given: Invalid UTF-8 data
        let invalidData = Data([0xFF, 0xFE, 0xFD]) // Invalid UTF-8 sequence
        mockBundle.mockData = invalidData
        mockBundle.mockURL = URL(fileURLWithPath: "/tmp/EmergencyConfig.json")
        
        // When: Load emergency config
        let result = emergencyConfigLoader.load()
        
        // Then: Should return nil due to encoding error
        XCTAssertNil(result, "Should return nil for invalid encoding")
    }
    
    // MARK: - Checksum Tests
    
    func testChecksumCalculation() {
        // Given: Valid config JSON
        let validConfigJSON = """
        {
            "configurations": [],
            "ab_tests": [],
            "ab_test": {
                "experiment_name": "Emergency Fallback",
                "group": "control",
                "experiment_id": "emergency-fallback"
            }
        }
        """
        
        let configData = validConfigJSON.data(using: .utf8)!
        mockBundle.mockData = configData
        mockBundle.mockURL = URL(fileURLWithPath: "/tmp/EmergencyConfig.json")
        
        // When: Load emergency config
        let result = emergencyConfigLoader.load()
        
        // Then: Should calculate checksum correctly
        XCTAssertNotNil(result, "Should load emergency config")
        XCTAssertNotNil(result?.checksum, "Should have checksum")
        XCTAssertFalse(result?.checksum.isEmpty == true, "Checksum should not be empty")
        
        // Verify checksum is consistent SHA-256 hash
        let expectedChecksum = SHA256.hash(data: configData)
        let expectedHash = expectedChecksum.compactMap { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(result?.checksum, expectedHash, "Should calculate correct SHA-256 checksum")
    }
    
    func testChecksumConsistency() {
        // Given: Same config JSON loaded multiple times
        let validConfigJSON = """
        {
            "configurations": [],
            "ab_tests": [],
            "ab_test": {
                "experiment_name": "Emergency Fallback",
                "group": "control",
                "experiment_id": "emergency-fallback"
            }
        }
        """
        
        let configData = validConfigJSON.data(using: .utf8)!
        mockBundle.mockData = configData
        mockBundle.mockURL = URL(fileURLWithPath: "/tmp/EmergencyConfig.json")
        
        // When: Load emergency config multiple times
        let result1 = emergencyConfigLoader.load()
        let result2 = emergencyConfigLoader.load()
        
        // Then: Checksums should be identical
        XCTAssertEqual(result1?.checksum, result2?.checksum, "Checksums should be consistent")
    }
    
    // MARK: - Timestamp Tests
    
    func testTimestampGeneration() {
        // Given: Valid config
        let validConfigJSON = """
        {
            "configurations": [],
            "ab_tests": [],
            "ab_test": {
                "experiment_name": "Emergency Fallback",
                "group": "control",
                "experiment_id": "emergency-fallback"
            }
        }
        """
        
        let configData = validConfigJSON.data(using: .utf8)!
        mockBundle.mockData = configData
        mockBundle.mockURL = URL(fileURLWithPath: "/tmp/EmergencyConfig.json")
        
        // When: Load emergency config
        let beforeLoad = Date()
        let result = emergencyConfigLoader.load()
        let afterLoad = Date()
        
        // Then: Timestamp should be within loading time window
        XCTAssertNotNil(result, "Should load emergency config")
        XCTAssertNotNil(result?.timestamp, "Should have timestamp")
        XCTAssertTrue(result?.timestamp ?? Date() >= beforeLoad, "Timestamp should be after load start")
        XCTAssertTrue(result?.timestamp ?? Date() <= afterLoad, "Timestamp should be before load end")
    }
    
    // MARK: - Source Tests
    
    func testConfigSourceSet() {
        // Given: Valid config
        let validConfigJSON = """
        {
            "configurations": [],
            "ab_tests": [],
            "ab_test": {
                "experiment_name": "Emergency Fallback",
                "group": "control",
                "experiment_id": "emergency-fallback"
            }
        }
        """
        
        let configData = validConfigJSON.data(using: .utf8)!
        mockBundle.mockData = configData
        mockBundle.mockURL = URL(fileURLWithPath: "/tmp/EmergencyConfig.json")
        
        // When: Load emergency config
        let result = emergencyConfigLoader.load()
        
        // Then: Source should be set to emergency
        XCTAssertNotNil(result, "Should load emergency config")
        XCTAssertEqual(result?.source, .emergency, "Source should be emergency")
    }
    
    // MARK: - Performance Tests
    
    func testLoadPerformance() {
        // Given: Large emergency config
        let largeConfigJSON = generateLargeConfigJSON()
        let configData = largeConfigJSON.data(using: .utf8)!
        mockBundle.mockData = configData
        mockBundle.mockURL = URL(fileURLWithPath: "/tmp/EmergencyConfig.json")
        
        // When: Measure load performance
        measure {
            _ = emergencyConfigLoader.load()
        }
    }
    
    func testChecksumPerformance() {
        // Given: Large config data
        let largeConfigJSON = generateLargeConfigJSON()
        let configData = largeConfigJSON.data(using: .utf8)!
        
        // When: Measure checksum performance
        measure {
            let hash = SHA256.hash(data: configData)
            _ = hash.compactMap { String(format: "%02x", $0) }.joined()
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateLargeConfigJSON() -> String {
        var configurations: [String] = []
        
        // Generate 100 provider configurations
        for i in 0..<100 {
            let config = """
            {
                "provider_id": "provider_\\(i)",
                "is_active": true,
                "segment_priority": \\(i),
                "provider_priority": \\(i),
                "credentials": {
                    "key_\\(i)": "value_\\(i)"
                }
            }
            """
            configurations.append(config)
        }
        
        return """
        {
            "configurations": [
                \(configurations.joined(separator: ","))
            ],
            "ab_tests": [],
            "ab_test": {
                "experiment_name": "Emergency Fallback",
                "group": "control",
                "experiment_id": "emergency-fallback"
            },
            "experiments": [],
            "segment": {
                "id": "emergency",
                "name": "Emergency Segment"
            },
            "logging": {
                "enabled": true,
                "sampling_rate": 0.1,
                "categories": {
                    "provider_init_failures": {
                        "enabled": true,
                        "max_per_hour": 50
                    }
                }
            },
            "resilience": {
                "backend_circuit_breaker": {
                    "failure_threshold": 5,
                    "success_threshold": 2,
                    "open_duration_ms": 60000
                }
            }
        }
        """
    }
}
