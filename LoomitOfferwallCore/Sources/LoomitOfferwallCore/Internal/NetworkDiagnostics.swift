//
//  NetworkDiagnostics.swift
//  LoomitOfferwallCore
//
//  Network diagnostics and connectivity validation.
//  Paridad con Android `NetworkDiagnostics.kt`.
//

import Foundation
import Network

/// Result of host connectivity check.
public struct HostConnectivityCheck: Sendable, Equatable {
    public let host: String
    public let resolved: Bool
    public let reachable: Bool
    public let errorMessage: String?
    
    public init(host: String, resolved: Bool, reachable: Bool, errorMessage: String? = nil) {
        self.host = host
        self.resolved = resolved
        self.reachable = reachable
        self.errorMessage = errorMessage
    }
}

/// Summary of network diagnostics.
public struct NetworkDiagnosticsSummary: Sendable, Equatable {
    public let hasActiveNetwork: Bool
    public let hasInternetCapability: Bool
    public let hasValidatedInternet: Bool
    public let transports: [String]
    public let isMetered: Bool
    public let hostChecks: [HostConnectivityCheck]
    public let error: String?
    
    public init(
        hasActiveNetwork: Bool,
        hasInternetCapability: Bool,
        hasValidatedInternet: Bool,
        transports: [String],
        isMetered: Bool,
        hostChecks: [HostConnectivityCheck],
        error: String? = nil
    ) {
        self.hasActiveNetwork = hasActiveNetwork
        self.hasInternetCapability = hasInternetCapability
        self.hasValidatedInternet = hasValidatedInternet
        self.transports = transports
        self.isMetered = isMetered
        self.hostChecks = hostChecks
        self.error = error
    }
}

/// Network diagnostics collector.
public enum NetworkDiagnostics {
    
    /// Collect comprehensive network diagnostics.
    public static func collect(hosts: [String]) async -> NetworkDiagnosticsSummary {
        // Get network path info first
        let pathInfo = await getNetworkPathInfo()
        
        // Test host connectivity
        let normalizedHosts = hosts.compactMap { extractHost(from: $0) }.uniqued()
        let hostChecks: [HostConnectivityCheck] = await withTaskGroup(of: HostConnectivityCheck.self) { group in
            for host in normalizedHosts {
                group.addTask { await testHost(host) }
            }
            var results: [HostConnectivityCheck] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        
        print("[NetworkDiagnostics] Network capabilities -> active=\(pathInfo.hasActiveNetwork) internetCap=\(pathInfo.hasInternetCapability) validated=\(pathInfo.hasValidatedInternet) transports=\(pathInfo.transports.isEmpty ? "none" : pathInfo.transports.joined(separator: ",")) metered=\(pathInfo.isMetered)")
        
        return NetworkDiagnosticsSummary(
            hasActiveNetwork: pathInfo.hasActiveNetwork,
            hasInternetCapability: pathInfo.hasInternetCapability,
            hasValidatedInternet: pathInfo.hasValidatedInternet,
            transports: pathInfo.transports,
            isMetered: pathInfo.isMetered,
            hostChecks: hostChecks,
            error: nil
        )
    }
    
    /// Get network path information.
    private static func getNetworkPathInfo() async -> (hasActiveNetwork: Bool, hasInternetCapability: Bool, hasValidatedInternet: Bool, transports: [String], isMetered: Bool) {
        let monitor = NWPathMonitor()
        
        return await withCheckedContinuation { continuation in
            monitor.pathUpdateHandler = { path in
                let hasActiveNetwork = path.status == .satisfied
                
                var transports: [String] = []
                if path.usesInterfaceType(.wifi) { transports.append("WIFI") }
                if path.usesInterfaceType(.cellular) { transports.append("CELLULAR") }
                if path.usesInterfaceType(.wiredEthernet) { transports.append("ETHERNET") }
                if path.usesInterfaceType(.other) { transports.append("OTHER") }
                
                let hasInternetCapability = path.usesInterfaceType(.wifi) || 
                                           path.usesInterfaceType(.cellular) || 
                                           path.usesInterfaceType(.wiredEthernet)
                
                let hasValidatedInternet = hasInternetCapability
                let isMetered = path.isExpensive
                
                monitor.cancel()
                continuation.resume(returning: (hasActiveNetwork, hasInternetCapability, hasValidatedInternet, transports, isMetered))
            }
            
            monitor.start(queue: .global(qos: .utility))
            
            // Timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
                monitor.cancel()
                continuation.resume(returning: (false, false, false, [], false))
            }
        }
    }
    
    /// Extract host from URL or string.
    private static func extractHost(from input: String?) -> String? {
        guard let input = input, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed) {
            return url.host?.lowercased()
        }
        if !trimmed.hasPrefix("http://") && !trimmed.hasPrefix("https://") {
            if let url = URL(string: "https://" + trimmed) {
                return url.host?.lowercased()
            }
        }
        return trimmed.lowercased()
    }
    
    /// Test host connectivity.
    private static func testHost(_ host: String) async -> HostConnectivityCheck {
        let resolved = await checkDNSResolution(host: host)
        return HostConnectivityCheck(host: host, resolved: resolved, reachable: false, errorMessage: nil)
    }
    
    /// Check DNS resolution for host.
    private static func checkDNSResolution(host: String) async -> Bool {
        let hostRef = CFHostCreateWithName(nil, host as CFString).takeRetainedValue()
        CFHostStartInfoResolution(hostRef, .names, nil)
        var hasBeenResolved: DarwinBoolean = false
        if let addresses = CFHostGetAddressing(hostRef, &hasBeenResolved)?.takeUnretainedValue() {
            return CFArrayGetCount(addresses) > 0
        }
        return false
    }
}

// MARK: - Array Extension

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
