//
//  ResilientBackendClientIntegrationTests.swift
//  LoomitOfferwallCoreTests
//
//  Integration tests for complete fallback chain testing.
//

import XCTest
@testable import LoomitOfferwallCore

final class ResilientBackendClientIntegrationTests: XCTestCase {
    
    // MARK: - Mock Classes
    
    class MockHTTPBackendClient: BackendClient {
        var shouldFail = false
        var failureError: Error?
        var responseDelay: TimeInterval = 0
        var callCount = 0
        
        func fetchConfig(_ request: ConfigRequest) async throws -> ConfigResponse {
            callCount += 1
            
            if responseDelay > 0 {
                try await Task.sleep(nanoseconds: UInt64(responseDelay * 1_000_000_000))
            }
            
            if shouldFail {
                throw failureError ?? NSError(domain: "MockError", code: -1, userInfo: nil)
            }
            
            return ConfigResponse(
                configurations: [],
                ab_tests: [],
                ab_test: nil,
                experiments: [],
                segment: nil,
                logging: nil,
                resilience: nil,
                debugging: nil,
                privacy: nil,
                network: nil
            )
        }
    }
    
    class MockConfigCache: ConfigCache {
        private var snapshot: ConfigSnapshot?
        private var shouldFailSave = false
        private var shouldFailLoad = false
        private var age: TimeInterval = 0
        
        func setSnapshot(_ snapshot: ConfigSnapshot?, age: TimeInterval = 0) {
            self.snapshot = snapshot
            self.age = age
        }
        
        func setShouldFailSave(_ shouldFail: Bool) {
            self.shouldFailSave = shouldFail
        }
        
        func setShouldFailLoad(_ shouldFail: Bool) {
            self.shouldFailLoad = shouldFail
        }
        
        func save(_ snapshot: ConfigSnapshot) -> Bool {
            if shouldFailSave { return false }
            self.snapshot = snapshot
            self.age = 0
            return true
        }
        
        func load() -> ConfigSnapshot? {
            if shouldFailLoad { return nil }
            return snapshot
        }
        
        func getAge() -> TimeInterval? {
            return age
        }
        
        func isStale(maxAge: TimeInterval) -> Bool {
            guard let age = getAge() else { return true }
            return age >= maxAge
        }
        
        func clear() {
            snapshot = nil
            age = 0
        }
    }
    
    class MockCircuitBreaker: CircuitBreaker {
        private var isOpen: Bool = false
        private var shouldTrip: Bool = false
        private var executeCallCount = 0
        
        func setOpen(_ open: Bool) {
            isOpen = open
        }
        
        func setShouldTrip(_ shouldTrip: Bool) {
            self.shouldTrip = shouldTrip
        }
        
        func getExecuteCallCount() -> Int {
            return executeCallCount
        }
        
        func execute<T>(_ operation: () async throws -> T) async throws -> T {
            executeCallCount += 1
            
            if isOpen || shouldTrip {
                throw CircuitOpenError()
            }
            
            return try await operation()
        }
        
        func reset() async {
            isOpen = false
            shouldTrip = false
            executeCallCount = 0
        }
        
        func getState() async -> CircuitState {
            return isOpen ? .open : .closed
        }
    }
    
    class MockEmergencyConfigLoader: Sendable {
        var shouldFail = false
        var loadCallCount = 0
        var mockSnapshot: ConfigSnapshot?
        
        func load() -> ConfigSnapshot? {
            loadCallCount += 1
            
            if shouldFail { return nil }
            return mockSnapshot
        }
        
        func setMockSnapshot(_ snapshot: ConfigSnapshot?) {
            self.mockSnapshot = snapshot
        }
        
        func setShouldFail(_ shouldFail: Bool) {
            self.shouldFail = shouldFail
        }
    }
    
    // MARK: - Test Properties
    
    private var mockHTTPClient: MockHTTPBackendClient!
    private var mockCache: MockConfigCache!
    private var mockCircuitBreaker: MockCircuitBreaker!
    private var mockEmergencyLoader: MockEmergencyConfigLoader!
    private var resilientClient: ResilientBackendClient!
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockHTTPClient = MockHTTPBackendClient()
        mockCache = MockConfigCache()
        mockCircuitBreaker = MockCircuitBreaker()
        mockEmergencyLoader = MockEmergencyConfigLoader()
        
        resilientClient = ResilientBackendClient(
            wrapping: mockHTTPClient,
            cache: mockCache,
            breaker: mockCircuitBreaker,
            emergencyLoader: mockEmergencyLoader
        )
    }
    
    override func tearDown() async throws {
        resilientClient = nil
        mockEmergencyLoader = nil
        mockCircuitBreaker = nil
        mockCache = nil
        mockHTTPClient = nil
        try await super.tearDown()
    }
    
    // MARK: - Success Path Tests
    
    func testNetworkRequestSuccess() async throws {
        // Given: Network request succeeds
        mockHTTPClient.shouldFail = false
        
        let request = ConfigRequest(
            clientId: "test_client",
            appId: "test_app",
            xifa: "test_xifa",
            deviceFingerprint: "test_fingerprint",
            country: "US",
            platform: "ios",
            sdkVersion: "1.0.0",
            appVersion: "1.0",
            bundleId: "com.test.app",
            abTestOverride: nil
        )
        
        // When: Fetch config
        let result = await resilientClient.fetchConfigDetailed(request)
        
        // Then: Should succeed from network
        switch result {
        case .success(let config, let source):
            XCTAssertNotNil(config, "Should return config")
            XCTAssertEqual(source, .network, "Should indicate network source")
        case .failure:
            XCTFail("Should not fail")
        }
        
        XCTAssertEqual(mockHTTPClient.callCount, 1, "Should make one HTTP call")
        XCTAssertEqual(mockCircuitBreaker.getExecuteCallCount(), 1, "Should execute circuit breaker once")
    }
    
    func testNetworkSuccessCachesResponse() async throws {
        // Given: Network request succeeds
        mockHTTPClient.shouldFail = false
        
        let request = ConfigRequest(
            clientId: "test_client",
            appId: "test_app",
            xifa: "test_xifa",
            deviceFingerprint: "test_fingerprint",
            country: "US",
            platform: "ios",
            sdkVersion: "1.0.0",
            appVersion: "1.0",
            bundleId: "com.test.app",
            abTestOverride: nil
        )
        
        // When: Fetch config twice
        let result1 = await resilientClient.fetchConfigDetailed(request)
        let result2 = await resilientClient.fetchConfigDetailed(request)
        
        // Then: Both should succeed, second from cache
        switch result1 {
        case .success(_, let source):
            XCTAssertEqual(source, .network, "First should be from network")
        case .failure:
            XCTFail("First should not fail")
        }
        
        switch result2 {
        case .success(_, let source):
            XCTAssertEqual(source, .network, "Second should also be from network (cache not used in success path)")
        case .failure:
            XCTFail("Second should not fail")
        }
        
        XCTAssertEqual(mockHTTPClient.callCount, 2, "Should make two HTTP calls")
        XCTAssertNotNil(mockCache.load(), "Should have cached response")
    }
    
    // MARK: - Fallback Chain Tests
    
    func testNetworkFailureCacheFreshFallback() async throws {
        // Given: Network fails but cache has fresh data
        mockHTTPClient.shouldFail = true
        mockHTTPClient.failureError = NSError(domain: "NetworkError", code: -1, userInfo: nil)
        
        let freshSnapshot = ConfigSnapshot(
            config: ConfigResponse(
                configurations: [],
                ab_tests: [],
                ab_test: nil,
                experiments: [],
                segment: nil,
                logging: nil,
                resilience: nil,
                debugging: nil,
                privacy: nil,
                network: nil
            ),
            source: .network,
            timestamp: Date(),
            checksum: "test"
        )
        mockCache.setSnapshot(freshSnapshot, age: 1000) // 1000 seconds old (fresh)
        
        let request = ConfigRequest(
            clientId: "test_client",
            appId: "test_app",
            xifa: "test_xifa",
            deviceFingerprint: "test_fingerprint",
            country: "US",
            platform: "ios",
            sdkVersion: "1.0.0",
            appVersion: "1.0",
            bundleId: "com.test.app",
            abTestOverride: nil
        )
        
        // When: Fetch config
        let result = await resilientClient.fetchConfigDetailed(request)
        
        // Then: Should fallback to cache fresh
        switch result {
        case .success(let config, let source):
            XCTAssertNotNil(config, "Should return config")
            XCTAssertEqual(source, .cacheFresh, "Should indicate cache fresh source")
        case .failure:
            XCTFail("Should not fail with fresh cache")
        }
        
        XCTAssertEqual(mockHTTPClient.callCount, 1, "Should attempt HTTP call first")
    }
    
    func testNetworkFailureCacheStaleFallback() async throws {
        // Given: Network fails, cache has stale data, stale allowed
        mockHTTPClient.shouldFail = true
        mockHTTPClient.failureError = NSError(domain: "NetworkError", code: -1, userInfo: nil)
        
        let staleSnapshot = ConfigSnapshot(
            config: ConfigResponse(
                configurations: [],
                ab_tests: [],
                ab_test: nil,
                experiments: [],
                segment: nil,
                logging: nil,
                resilience: nil,
                debugging: nil,
                privacy: nil,
                network: nil
            ),
            source: .network,
            timestamp: Date().addingTimeInterval(-200000), // 2 days ago (stale)
            checksum: "test"
        )
        mockCache.setSnapshot(staleSnapshot, age: 200000) // 2 days old (stale)
        
        let request = ConfigRequest(
            clientId: "test_client",
            appId: "test_app",
            xifa: "test_xifa",
            deviceFingerprint: "test_fingerprint",
            country: "US",
            platform: "ios",
            sdkVersion: "1.0.0",
            appVersion: "1.0",
            bundleId: "com.test.app",
            abTestOverride: nil
        )
        
        // When: Fetch config with stale cache allowed
        let stalePolicy = ConfigFetchPolicy(
            useCacheIfFailed: true,
            allowStaleCache: true,
            cacheMaxAge: 86400, // 24 hours
            staleMaxAge: 604800 // 7 days
        )
        
        let resilientClientWithStalePolicy = ResilientBackendClient(
            wrapping: mockHTTPClient,
            cache: mockCache,
            breaker: mockCircuitBreaker,
            policy: stalePolicy,
            emergencyLoader: mockEmergencyLoader
        )
        
        let result = await resilientClientWithStalePolicy.fetchConfigDetailed(request)
        
        // Then: Should fallback to cache stale
        switch result {
        case .success(let config, let source):
            XCTAssertNotNil(config, "Should return config")
            XCTAssertEqual(source, .cacheStale, "Should indicate cache stale source")
        case .failure:
            XCTFail("Should not fail with stale cache allowed")
        }
    }
    
    func testNetworkFailureCacheStaleNotAllowed() async throws {
        // Given: Network fails, cache has stale data, stale not allowed
        mockHTTPClient.shouldFail = true
        mockHTTPClient.failureError = NSError(domain: "NetworkError", code: -1, userInfo: nil)
        
        let staleSnapshot = ConfigSnapshot(
            config: ConfigResponse(
                configurations: [],
                ab_tests: [],
                ab_test: nil,
                experiments: [],
                segment: nil,
                logging: nil,
                resilience: nil,
                debugging: nil,
                privacy: nil,
                network: nil
            ),
            source: .network,
            timestamp: Date().addingTimeInterval(-200000), // 2 days ago (stale)
            checksum: "test"
        )
        mockCache.setSnapshot(staleSnapshot, age: 200000) // 2 days old (stale)
        
        let request = ConfigRequest(
            clientId: "test_client",
            appId: "test_app",
            xifa: "test_xifa",
            deviceFingerprint: "test_fingerprint",
            country: "US",
            platform: "ios",
            sdkVersion: "1.0.0",
            appVersion: "1.0",
            bundleId: "com.test.app",
            abTestOverride: nil
        )
        
        // When: Fetch config with stale cache not allowed
        let noStalePolicy = ConfigFetchPolicy(
            useCacheIfFailed: true,
            allowStaleCache: false,
            cacheMaxAge: 86400, // 24 hours
            staleMaxAge: 604800 // 7 days
        )
        
        let resilientClientWithNoStalePolicy = ResilientBackendClient(
            wrapping: mockHTTPClient,
            cache: mockCache,
            breaker: mockCircuitBreaker,
            policy: noStalePolicy,
            emergencyLoader: mockEmergencyLoader
        )
        
        let result = await resilientClientWithNoStalePolicy.fetchConfigDetailed(request)
        
        // Then: Should not use stale cache
        switch result {
        case .success:
            XCTFail("Should not succeed with stale cache not allowed")
        case .failure(let error, let fallbackAvailable):
            XCTAssertNotNil(error, "Should have error")
            XCTAssertFalse(fallbackAvailable, "Should indicate no fallback available")
        }
    }
    
    func testCompleteFallbackToEmergency() async throws {
        // Given: Network fails, cache fails, emergency config available
        mockHTTPClient.shouldFail = true
        mockHTTPClient.failureError = NSError(domain: "NetworkError", code: -1, userInfo: nil)
        mockCache.setShouldFailLoad(true)
        
        let emergencySnapshot = ConfigSnapshot(
            config: ConfigResponse(
                configurations: [
                    ProviderConfiguration(
                        provider_id: "emergency_provider",
                        is_active: true,
                        segment_priority: 1,
                        provider_priority: 1,
                        credentials: [:],
                        settings: [:]
                    )
                ],
                ab_tests: [],
                ab_test: nil,
                experiments: [],
                segment: nil,
                logging: nil,
                resilience: nil,
                debugging: nil,
                privacy: nil,
                network: nil
            ),
            source: .emergency,
            timestamp: Date(),
            checksum: "emergency_checksum"
        )
        mockEmergencyLoader.setMockSnapshot(emergencySnapshot)
        
        let request = ConfigRequest(
            clientId: "test_client",
            appId: "test_app",
            xifa: "test_xifa",
            deviceFingerprint: "test_fingerprint",
            country: "US",
            platform: "ios",
            sdkVersion: "1.0.0",
            appVersion: "1.0",
            bundleId: "com.test.app",
            abTestOverride: nil
        )
        
        // When: Fetch config
        let result = await resilientClient.fetchConfigDetailed(request)
        
        // Then: Should fallback to emergency config
        switch result {
        case .success(let config, let source):
            XCTAssertNotNil(config, "Should return config")
            XCTAssertEqual(source, .emergency, "Should indicate emergency source")
            XCTAssertEqual(config.configurations.count, 1, "Should have emergency provider")
            XCTAssertEqual(config.configurations.first?.provider_id, "emergency_provider", "Should have correct provider")
        case .failure:
            XCTFail("Should not fail with emergency config available")
        }
        
        XCTAssertEqual(mockEmergencyLoader.loadCallCount, 1, "Should attempt emergency config load")
    }
    
    func testCompleteFailureNoFallback() async throws {
        // Given: All fallback options fail
        mockHTTPClient.shouldFail = true
        mockHTTPClient.failureError = NSError(domain: "NetworkError", code: -1, userInfo: nil)
        mockCache.setShouldFailLoad(true)
        mockEmergencyLoader.setShouldFail(true)
        
        let request = ConfigRequest(
            clientId: "test_client",
            appId: "test_app",
            xifa: "test_xifa",
            deviceFingerprint: "test_fingerprint",
            country: "US",
            platform: "ios",
            sdkVersion: "1.0.0",
            appVersion: "1.0",
            bundleId: "com.test.app",
            abTestOverride: nil
        )
        
        // When: Fetch config
        let result = await resilientClient.fetchConfigDetailed(request)
        
        // Then: Should fail with no fallback available
        switch result {
        case .success:
            XCTFail("Should not succeed")
        case .failure(let error, let fallbackAvailable):
            XCTAssertNotNil(error, "Should have error")
            XCTAssertFalse(fallbackAvailable, "Should indicate no fallback available")
        }
        
        XCTAssertEqual(mockEmergencyLoader.loadCallCount, 1, "Should attempt emergency config load")
    }
    
    // MARK: - Circuit Breaker Tests
    
    func testCircuitBreakerOpenBlocksRequests() async throws {
        // Given: Circuit breaker is open
        mockCircuitBreaker.setOpen(true)
        
        let request = ConfigRequest(
            clientId: "test_client",
            appId: "test_app",
            xifa: "test_xifa",
            deviceFingerprint: "test_fingerprint",
            country: "US",
            platform: "ios",
            sdkVersion: "1.0.0",
            appVersion: "1.0",
            bundleId: "com.test.app",
            abTestOverride: nil
        )
        
        // When: Fetch config
        let result = await resilientClient.fetchConfigDetailed(request)
        
        // Then: Should fail due to circuit breaker
        switch result {
        case .success:
            XCTFail("Should not succeed with open circuit")
        case .failure(let error, let fallbackAvailable):
            XCTAssertTrue(error is CircuitOpenError, "Should be circuit open error")
            XCTAssertFalse(fallbackAvailable, "Should indicate no fallback available")
        }
        
        XCTAssertEqual(mockHTTPClient.callCount, 0, "Should not attempt HTTP call with open circuit")
    }
    
    // MARK: - Cache Integration Tests
    
    func testSuccessfulRequestSavesToCache() async throws {
        // Given: Network request succeeds
        mockHTTPClient.shouldFail = false
        
        let request = ConfigRequest(
            clientId: "test_client",
            appId: "test_app",
            xifa: "test_xifa",
            deviceFingerprint: "test_fingerprint",
            country: "US",
            platform: "ios",
            sdkVersion: "1.0.0",
            appVersion: "1.0",
            bundleId: "com.test.app",
            abTestOverride: nil
        )
        
        // When: Fetch config
        _ = await resilientClient.fetchConfigDetailed(request)
        
        // Then: Should save to cache
        XCTAssertNotNil(mockCache.load(), "Should save response to cache")
    }
    
    func testCacheSaveFailureDoesNotAffectResponse() async throws {
        // Given: Network request succeeds but cache save fails
        mockHTTPClient.shouldFail = false
        mockCache.setShouldFailSave(true)
        
        let request = ConfigRequest(
            clientId: "test_client",
            appId: "test_app",
            xifa: "test_xifa",
            deviceFingerprint: "test_fingerprint",
            country: "US",
            platform: "ios",
            sdkVersion: "1.0.0",
            appVersion: "1.0",
            bundleId: "com.test.app",
            abTestOverride: nil
        )
        
        // When: Fetch config
        let result = await resilientClient.fetchConfigDetailed(request)
        
        // Then: Should still succeed despite cache save failure
        switch result {
        case .success(_, let source):
            XCTAssertEqual(source, .network, "Should succeed from network")
        case .failure:
            XCTFail("Should not fail despite cache save failure")
        }
    }
    
    // MARK: - Performance Tests
    
    func testFallbackChainPerformance() {
        // Given: Complete fallback chain setup
        mockHTTPClient.shouldFail = true
        mockCache.setShouldFailLoad(true)
        mockEmergencyLoader.setShouldFail(false)
        
        let emergencySnapshot = ConfigSnapshot(
            config: ConfigResponse(
                configurations: [],
                ab_tests: [],
                ab_test: nil,
                experiments: [],
                segment: nil,
                logging: nil,
                resilience: nil,
                debugging: nil,
                privacy: nil,
                network: nil
            ),
            source: .emergency,
            timestamp: Date(),
            checksum: "test"
        )
        mockEmergencyLoader.setMockSnapshot(emergencySnapshot)
        
        let request = ConfigRequest(
            clientId: "test_client",
            appId: "test_app",
            xifa: "test_xifa",
            deviceFingerprint: "test_fingerprint",
            country: "US",
            platform: "ios",
            sdkVersion: "1.0.0",
            appVersion: "1.0",
            bundleId: "com.test.app",
            abTestOverride: nil
        )
        
        // When: Measure fallback chain performance
        measure {
            Task {
                _ = await resilientClient.fetchConfigDetailed(request)
            }
        }
    }
}
