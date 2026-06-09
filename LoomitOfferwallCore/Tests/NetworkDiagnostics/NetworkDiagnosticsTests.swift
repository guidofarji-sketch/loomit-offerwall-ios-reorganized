//
//  NetworkDiagnosticsTests.swift
//  LoomitOfferwallCoreTests
//
//  Unit tests for NetworkDiagnostics component.
//

import XCTest
import Network
@testable import LoomitOfferwallCore

final class NetworkDiagnosticsTests: XCTestCase {
    
    // MARK: - Mock Classes
    
    class MockNWPathMonitor {
        var mockPath: MockNWPath?
        var startCalled = false
        var cancelCalled = false
        
        func start(queue: DispatchQueue) {
            startCalled = true
            // Simulate async callback
            queue.asyncAfter(deadline: .now() + 0.1) {
                if let path = self.mockPath {
                    path.handler?(path)
                }
            }
        }
        
        func cancel() {
            cancelCalled = true
        }
    }
    
    class MockNWPath {
        let status: NWPath.Status
        let usesInterfaceTypes: Set<NWInterface.InterfaceType>
        let isExpensive: Bool
        var handler: ((NWPath) -> Void)?
        
        init(status: NWPath.Status, 
             usesInterfaceTypes: Set<NWInterface.InterfaceType>,
             isExpensive: Bool = false) {
            self.status = status
            self.usesInterfaceTypes = usesInterfaceTypes
            self.isExpensive = isExpensive
        }
        
        func usesInterfaceType(_ type: NWInterface.InterfaceType) -> Bool {
            return usesInterfaceTypes.contains(type)
        }
    }
    
    class MockSocketStream {
        var shouldConnect = true
        var shouldTimeout = false
        var connectDelay: TimeInterval = 0
        
        func connect(toHost host: String, port: Int) throws {
            if shouldTimeout {
                throw NSError(domain: "SocketError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection timeout"])
            }
            if !shouldConnect {
                throw NSError(domain: "SocketError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Connection failed"])
            }
            
            if connectDelay > 0 {
                Thread.sleep(forTimeInterval: connectDelay)
            }
        }
    }
    
    // MARK: - Test Cases
    
    func testNetworkConnectivityDetection() async {
        // Given: Mock network path with WiFi
        let mockMonitor = MockNWPathMonitor()
        let mockPath = MockNWPath(
            status: .satisfied,
            usesInterfaceTypes: [.wifi]
        )
        mockMonitor.mockPath = mockPath
        
        // When: Collect network diagnostics
        let result = await NetworkDiagnostics.collect(hosts: ["example.com"])
        
        // Then: Network should be detected as active with WiFi
        XCTAssertTrue(result.hasActiveNetwork, "Should detect active network")
        XCTAssertTrue(result.hasInternetCapability, "Should detect internet capability")
        XCTAssertTrue(result.transports.contains("WIFI"), "Should detect WiFi transport")
        XCTAssertFalse(result.transports.contains("CELLULAR"), "Should not detect cellular transport")
    }
    
    func testCellularConnectivityDetection() async {
        // Given: Mock network path with cellular
        let mockMonitor = MockNWPathMonitor()
        let mockPath = MockNWPath(
            status: .satisfied,
            usesInterfaceTypes: [.cellular],
            isExpensive: true
        )
        mockMonitor.mockPath = mockPath
        
        // When: Collect network diagnostics
        let result = await NetworkDiagnostics.collect(hosts: ["example.com"])
        
        // Then: Network should be detected as cellular and metered
        XCTAssertTrue(result.hasActiveNetwork, "Should detect active network")
        XCTAssertTrue(result.transports.contains("CELLULAR"), "Should detect cellular transport")
        XCTAssertEqual(result.isMetered, true, "Should detect metered connection")
    }
    
    func testNoNetworkConnectivity() async {
        // Given: Mock network path with no connection
        let mockMonitor = MockNWPathMonitor()
        let mockPath = MockNWPath(
            status: .unsatisfied,
            usesInterfaceTypes: []
        )
        mockMonitor.mockPath = mockPath
        
        // When: Collect network diagnostics
        let result = await NetworkDiagnostics.collect(hosts: ["example.com"])
        
        // Then: Network should be detected as inactive
        XCTAssertFalse(result.hasActiveNetwork, "Should detect inactive network")
        XCTAssertFalse(result.hasInternetCapability, "Should not detect internet capability")
        XCTAssertTrue(result.transports.isEmpty, "Should have no transports")
    }
    
    func testHostConnectivityCheckSuccess() async {
        // Given: Valid host with successful DNS and socket connection
        let result = await NetworkDiagnostics.collect(hosts: ["google.com"])
        
        // When: Check host connectivity
        let googleCheck = result.hostChecks.first { $0.host == "google.com" }
        
        // Then: Host should be resolved and reachable
        XCTAssertNotNil(googleCheck, "Should have check for google.com")
        XCTAssertTrue(googleCheck?.resolved == true, "Should resolve google.com")
        XCTAssertTrue(googleCheck?.reachable == true, "Should reach google.com")
        XCTAssertNil(googleCheck?.errorMessage, "Should have no error message")
    }
    
    func testHostConnectivityCheckFailure() async {
        // Given: Invalid host that should fail DNS resolution
        let result = await NetworkDiagnostics.collect(hosts: ["invalid.nonexistent.host"])
        
        // When: Check host connectivity
        let hostCheck = result.hostChecks.first { $0.host == "invalid.nonexistent.host" }
        
        // Then: Host should fail to resolve
        XCTAssertNotNil(hostCheck, "Should have check for invalid host")
        XCTAssertFalse(hostCheck?.resolved == true, "Should not resolve invalid host")
        XCTAssertFalse(hostCheck?.reachable == true, "Should not reach invalid host")
        XCTAssertNotNil(hostCheck?.errorMessage, "Should have error message")
    }
    
    func testMultipleHostConnectivity() async {
        // Given: Multiple hosts with different connectivity states
        let hosts = ["google.com", "github.com", "invalid.host"]
        
        // When: Collect network diagnostics
        let result = await NetworkDiagnostics.collect(hosts: hosts)
        
        // Then: Should have checks for all hosts
        XCTAssertEqual(result.hostChecks.count, hosts.count, "Should have check for each host")
        
        // Valid hosts should resolve
        let googleCheck = result.hostChecks.first { $0.host == "google.com" }
        XCTAssertTrue(googleCheck?.resolved == true, "Should resolve google.com")
        
        let githubCheck = result.hostChecks.first { $0.host == "github.com" }
        XCTAssertTrue(githubCheck?.resolved == true, "Should resolve github.com")
        
        // Invalid host should not resolve
        let invalidCheck = result.hostChecks.first { $0.host == "invalid.host" }
        XCTAssertFalse(invalidCheck?.resolved == true, "Should not resolve invalid host")
    }
    
    func testHostExtractionFromURL() async {
        // Given: Various URL formats
        let urls = [
            "https://www.example.com/path",
            "http://example.com",
            "example.com",
            "subdomain.example.com:8080"
        ]
        
        // When: Collect network diagnostics
        let result = await NetworkDiagnostics.collect(hosts: urls)
        
        // Then: Should extract hosts correctly
        let expectedHosts = ["www.example.com", "example.com", "subdomain.example.com"]
        XCTAssertEqual(result.hostChecks.count, expectedHosts.count, "Should extract correct number of hosts")
        
        for host in expectedHosts {
            let check = result.hostChecks.first { $0.host.contains(host) }
            XCTAssertNotNil(check, "Should have check for \(host)")
        }
    }
    
    func testDuplicateHostHandling() async {
        // Given: Duplicate hosts in different formats
        let hosts = [
            "example.com",
            "https://example.com",
            "http://example.com/path",
            "EXAMPLE.COM" // uppercase
        ]
        
        // When: Collect network diagnostics
        let result = await NetworkDiagnostics.collect(hosts: hosts)
        
        // Then: Should deduplicate hosts
        XCTAssertEqual(result.hostChecks.count, 1, "Should deduplicate to single host")
        XCTAssertEqual(result.hostChecks.first?.host, "example.com", "Should use lowercase host")
    }
    
    func testEmptyHostsList() async {
        // Given: Empty hosts list
        let hosts: [String] = []
        
        // When: Collect network diagnostics
        let result = await NetworkDiagnostics.collect(hosts: hosts)
        
        // Then: Should return empty host checks
        XCTAssertTrue(result.hostChecks.isEmpty, "Should have no host checks")
    }
    
    func testNetworkDiagnosticsSummary() async {
        // Given: Mixed network state
        let mockMonitor = MockNWPathMonitor()
        let mockPath = MockNWPath(
            status: .satisfied,
            usesInterfaceTypes: [.wifi, .cellular],
            isExpensive: false
        )
        mockMonitor.mockPath = mockPath
        
        // When: Collect network diagnostics
        let result = await NetworkDiagnostics.collect(hosts: ["google.com", "invalid.host"])
        
        // Then: Should provide comprehensive summary
        XCTAssertTrue(result.hasActiveNetwork, "Should detect active network")
        XCTAssertTrue(result.hasInternetCapability, "Should detect internet capability")
        XCTAssertTrue(result.hasValidatedInternet, "Should detect validated internet")
        XCTAssertTrue(result.transports.contains("WIFI"), "Should detect WiFi")
        XCTAssertTrue(result.transports.contains("CELLULAR"), "Should detect cellular")
        XCTAssertEqual(result.isMetered, false, "Should not be metered")
        XCTAssertEqual(result.hostChecks.count, 2, "Should have 2 host checks")
        XCTAssertNil(result.error, "Should have no error")
    }
    
    // MARK: - Performance Tests
    
    func testNetworkDiagnosticsPerformance() {
        // Given: Multiple hosts
        let hosts = ["google.com", "github.com", "stackoverflow.com", "apple.com"]
        
        // When: Measure performance
        measure {
            Task {
                _ = await NetworkDiagnostics.collect(hosts: hosts)
            }
        }
    }
    
    func testHostCheckTimeoutPerformance() {
        // Given: Host that might timeout
        let hosts = ["slow-responding-host.com"]
        
        // When: Measure timeout handling performance
        measure {
            Task {
                _ = await NetworkDiagnostics.collect(hosts: hosts)
            }
        }
    }
}
