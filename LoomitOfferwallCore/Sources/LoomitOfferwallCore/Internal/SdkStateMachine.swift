//
//  SdkStateMachine.swift
//  LoomitOfferwallCore
//
//  Thread-safe state machine with atomic transitions.
//  Parity with Android `SdkStateMachine` (SdkState.kt).
//
//  States:
//  - UNINITIALIZED: No API key set
//  - CONFIGURED: API key set, no config fetched
//  - CONFIG_READY: Config fetched, ready to init providers
//  - INITIALIZING: Providers being initialized
//  - READY: Providers initialized, ready to show
//  - SHOWING: Offerwall currently displayed
//

import Foundation

/// SDK lifecycle states. Parity with Android `SdkState` enum.
public enum SdkState: String, Sendable, Equatable, CaseIterable {
    case uninitialized = "UNINITIALIZED"
    case configured = "CONFIGURED"
    case configReady = "CONFIG_READY"
    case initializing = "INITIALIZING"
    case ready = "READY"
    case showing = "SHOWING"
    
    /// Human-readable label for logs/debug.
    public var label: String { rawValue }
}

/// Defines valid state transitions. Parity with Android `SdkStateTransitions`.
public enum SdkStateTransitions {
    
    /// Returns `true` if transitioning from `from` to `to` is valid.
    public static func isValid(from: SdkState, to: SdkState) -> Bool {
        switch (from, to) {
        // From UNINITIALIZED
        case (.uninitialized, .configured):
            return true
            
        // From CONFIGURED
        case (.configured, .configReady):
            return true
        case (.configured, .uninitialized):
            return true // shutdown
            
        // From CONFIG_READY
        case (.configReady, .initializing):
            return true
        case (.configReady, .configReady):
            return true // re-fetch config
        case (.configReady, .uninitialized):
            return true // shutdown
            
        // From INITIALIZING
        case (.initializing, .ready):
            return true // success
        case (.initializing, .configReady):
            return true // all providers failed
        case (.initializing, .uninitialized):
            return true // shutdown
            
        // From READY
        case (.ready, .showing):
            return true
        case (.ready, .configReady):
            return true // re-fetch config
        case (.ready, .uninitialized):
            return true // shutdown
            
        // From SHOWING
        case (.showing, .ready):
            return true // close/showFailed
        case (.showing, .uninitialized):
            return true // shutdown
            
        default:
            return false
        }
    }
    
    /// Returns all valid target states from a given state.
    public static func validTargets(from state: SdkState) -> [SdkState] {
        SdkState.allCases.filter { isValid(from: state, to: $0) }
    }
}

/// Thread-safe state machine for SDK lifecycle.
/// Uses actor isolation for thread safety (Swift Concurrency).
///
/// Parity with Android `SdkStateMachine` which uses `AtomicReference`.
@available(iOS 13.0, macOS 10.15, *)
public actor SdkStateMachine {
    
    /// Current state.
    public private(set) var state: SdkState
    
    /// History of transitions for debugging (last N).
    private var transitionHistory: [(from: SdkState, to: SdkState, timestamp: Date)] = []
    private let maxHistorySize = 20
    
    public init(initialState: SdkState = .uninitialized) {
        self.state = initialState
    }
    
    /// Attempts an atomic transition from `from` to `to`.
    ///
    /// - Returns: `true` if transition succeeded, `false` if current state doesn't match
    ///   `from` or transition is invalid.
    @discardableResult
    public func transition(from: SdkState, to: SdkState) -> Bool {
        guard state == from else {
            return false
        }
        
        guard SdkStateTransitions.isValid(from: from, to: to) else {
            return false
        }
        
        recordTransition(from: from, to: to)
        state = to
        return true
    }
    
    /// Forces state without validation. Use only for error recovery.
    public func forceState(_ newState: SdkState) {
        let oldState = state
        recordTransition(from: oldState, to: newState)
        state = newState
    }
    
    /// Checks if a transition would be valid without performing it.
    public func canTransition(from: SdkState, to: SdkState) -> Bool {
        state == from && SdkStateTransitions.isValid(from: from, to: to)
    }
    
    /// Returns recent transition history for debugging.
    public func recentTransitions() -> [(from: SdkState, to: SdkState, timestamp: Date)] {
        transitionHistory
    }
    
    /// Resets to initial state. Clears history.
    public func reset() {
        state = .uninitialized
        transitionHistory.removeAll()
    }
    
    // MARK: - Private
    
    private func recordTransition(from: SdkState, to: SdkState) {
        transitionHistory.append((from: from, to: to, timestamp: Date()))
        if transitionHistory.count > maxHistorySize {
            transitionHistory.removeFirst()
        }
    }
}

// MARK: - Convenience extensions

extension SdkStateMachine {
    
    /// Checks if SDK is in a state that allows showing offerwall.
    public var canShow: Bool {
        state == .ready
    }
    
    /// Checks if SDK is currently showing an offerwall.
    public var isShowing: Bool {
        state == .showing
    }
    
    /// Checks if SDK has been configured (API key set).
    public var isConfigured: Bool {
        state != .uninitialized
    }
    
    /// Checks if SDK is ready to initialize providers.
    public var canInitialize: Bool {
        state == .configReady
    }
}
