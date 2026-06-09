//
//  LifecycleDiagnosticLogger.swift
//  LoomitOfferwallCore
//
//  Diagnostic logger for lifecycle events and anomalies.
//  Parity with Android `LifecycleDiagnosticLogger.kt`.
//
//  Logs to category: `lifecycle_diagnostic`
//
//  Events logged:
//  - lifecycle_started: New lifecycle began
//  - double_start_prevented: Attempted to start lifecycle when one was active
//  - double_show_prevented: Attempted to show when already showing
//  - invalid_transition_prevented: State machine rejected transition
//  - state_transition: Valid state transition occurred
//  - lifecycle_ended: Lifecycle completed
//

import Foundation

/// Logger for lifecycle diagnostic events.
/// Uses `ProductionLogger` internally with category `lifecycle_diagnostic`.
@available(iOS 13.0, macOS 10.15, *)
public actor LifecycleDiagnosticLogger {
    
    private let logger: () async -> CategoryLogger
    
    // Counters for diagnostics
    private var totalLifecycleStarts: Int = 0
    private var preventedDoubleStarts: Int = 0
    private var preventedDoubleShows: Int = 0
    private var invalidTransitions: Int = 0
    
    public init(loggerProvider: @escaping () async -> CategoryLogger) {
        self.logger = loggerProvider
    }
    
    // MARK: - Lifecycle Events
    
    /// Called when a new lifecycle starts.
    /// - Parameters:
    ///   - lifecycleId: The new lifecycle ID
    ///   - totalCount: Total lifecycle starts since SDK init
    ///   - callerStack: Stack trace sample of who initiated the lifecycle
    public func onLifecycleStarted(
        lifecycleId: Int,
        totalCount: Int,
        callerStack: [String]
    ) async {
        totalLifecycleStarts += 1
        await logger().info([
            "stage": .string("lifecycle_started"),
            "lifecycle_id": .int(Int64(lifecycleId)),
            "total_count": .int(Int64(totalCount)),
            "caller_stack": .string(callerStack.joined(separator: " <- "))
        ])
        print("[LifecycleDiagnosticLogger] Lifecycle started: LC=\(lifecycleId) (total=\(totalCount))")
    }
    
    /// Called when a double-start was prevented.
    /// - Parameters:
    ///   - currentLifecycleId: The currently active lifecycle ID
    ///   - attemptedBy: Description of what tried to start a new lifecycle
    public func onDoubleStartPrevented(
        currentLifecycleId: Int,
        attemptedBy: String
    ) async {
        preventedDoubleStarts += 1
        await logger().warning([
            "stage": .string("double_start_prevented"),
            "current_lifecycle_id": .int(Int64(currentLifecycleId)),
            "attempted_by": .string(attemptedBy)
        ])
        print("[LifecycleDiagnosticLogger] Lifecycle double-start prevented: LC=\(currentLifecycleId) was already active (attempted by \(attemptedBy))")
    }
    
    /// Called when a double-show was prevented.
    /// - Parameter currentLifecycleId: The currently active lifecycle ID
    public func onDoubleShowPrevented(currentLifecycleId: Int) async {
        preventedDoubleShows += 1
        await logger().warning([
            "stage": .string("double_show_prevented"),
            "current_lifecycle_id": .int(Int64(currentLifecycleId))
        ])
        print("[LifecycleDiagnosticLogger] Double-show prevented: LC=\(currentLifecycleId) already has an offerwall showing")
    }
    
    /// Called when a double-show was prevented (with state info).
    /// - Parameters:
    ///   - currentState: Current state description
    ///   - attemptedProvider: Provider that was attempted
    public func logDoubleShowPrevented(
        currentState: String,
        attemptedProvider: String
    ) async {
        preventedDoubleShows += 1
        await logger().warning([
            "stage": .string("double_show_prevented"),
            "current_state": .string(currentState),
            "attempted_provider": .string(attemptedProvider)
        ])
        print("[LifecycleDiagnosticLogger] Double-show prevented: state=\(currentState), attempted_provider=\(attemptedProvider)")
    }
    
    /// Called when an invalid state transition was attempted.
    /// - Parameters:
    ///   - from: Current state
    ///   - to: Attempted target state
    ///   - reason: Why the transition was invalid
    public func onInvalidTransitionAttempted(
        from: SdkState,
        to: SdkState,
        reason: String
    ) async {
        invalidTransitions += 1
        await logger().warning([
            "stage": .string("invalid_transition_prevented"),
            "from_state": .string(from.label),
            "to_state": .string(to.label),
            "reason": .string(reason)
        ])
        print("[LifecycleDiagnosticLogger] Invalid transition prevented: \(from.label) -> \(to.label) (\(reason))")
    }
    
    /// Called when a valid state transition occurs.
    /// - Parameters:
    ///   - from: Previous state
    ///   - to: New state
    ///   - trigger: What triggered the transition
    public func onStateTransition(
        from: SdkState,
        to: SdkState,
        trigger: String
    ) async {
        await logger().debug([
            "stage": .string("state_transition"),
            "from_state": .string(from.label),
            "to_state": .string(to.label),
            "trigger": .string(trigger)
        ])
        print("[LifecycleDiagnosticLogger] State transition: \(from.label) -> \(to.label) (trigger=\(trigger))")
    }
    
    /// Called when a lifecycle ends.
    /// - Parameters:
    ///   - lifecycleId: The ending lifecycle ID
    ///   - reason: Why the lifecycle ended
    public func onLifecycleEnded(lifecycleId: Int, reason: String) async {
        await logger().info([
            "stage": .string("lifecycle_ended"),
            "lifecycle_id": .int(Int64(lifecycleId)),
            "reason": .string(reason)
        ])
        print("[LifecycleDiagnosticLogger] Lifecycle ended: LC=\(lifecycleId) (reason=\(reason))")
    }
    
    /// Periodic heartbeat with current lifecycle status.
    public func onStatusHeartbeat(
        currentLifecycleId: Int,
        lifecycleIdFromAvailability: Bool
    ) async {
        await logger().debug([
            "stage": .string("lifecycle_heartbeat"),
            "current_lifecycle_id": .int(Int64(currentLifecycleId)),
            "lifecycle_id_from_availability": .bool(lifecycleIdFromAvailability),
            "total_starts": .int(Int64(totalLifecycleStarts)),
            "prevented_double_starts": .int(Int64(preventedDoubleStarts))
        ])
    }
    
    // MARK: - Diagnostics
    
    /// Returns current diagnostic counters.
    public func diagnostics() -> (
        totalStarts: Int,
        preventedDoubleStarts: Int,
        preventedDoubleShows: Int,
        invalidTransitions: Int
    ) {
        (totalLifecycleStarts, preventedDoubleStarts, preventedDoubleShows, invalidTransitions)
    }
    
    /// Resets counters (for testing).
    public func resetCounters() {
        totalLifecycleStarts = 0
        preventedDoubleStarts = 0
        preventedDoubleShows = 0
        invalidTransitions = 0
    }
}

// MARK: - Stack Trace Capture

extension LifecycleDiagnosticLogger {
    
    /// Captures a sample of the current call stack for diagnostics.
    /// - Parameters:
    ///   - skipFrames: Number of frames to skip from the top
    ///   - maxFrames: Maximum frames to capture
    /// - Returns: Array of frame descriptions
    public static func captureCallerStack(skipFrames: Int = 2, maxFrames: Int = 5) -> [String] {
        let symbols = Thread.callStackSymbols
        let startIndex = min(skipFrames, symbols.count)
        let endIndex = min(startIndex + maxFrames, symbols.count)
        
        guard startIndex < endIndex else { return [] }
        
        return Array(symbols[startIndex..<endIndex]).map { symbol in
            // Simplify symbol: extract just the function name
            // Format: "0   Module    0x... functionName + offset"
            let parts = symbol.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 4 {
                // Try to get the function name (usually 4th element)
                return String(parts[3])
            }
            return symbol
        }
    }
}
