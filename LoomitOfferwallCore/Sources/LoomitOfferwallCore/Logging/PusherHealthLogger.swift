//
//  PusherHealthLogger.swift
//  LoomitOfferwallCore
//
//  Logger for event pusher infrastructure health.
//  Parity with Android `PusherHealthLogger.kt`.
//
//  Logs to category: `pusher_infrastructure`
//
//  Events logged:
//  - pusher_init_attempt: Attempting to initialize pusher
//  - pusher_init_success: Pusher initialized successfully
//  - pusher_init_failure: Pusher failed to initialize
//  - retry_scheduled: Retry scheduled after failure
//  - race_condition_detected: Concurrent access detected
//

import Foundation

/// Logger for event pusher infrastructure health.
@available(iOS 13.0, macOS 10.15, *)
public actor PusherHealthLogger {
    
    private let logger: () async -> CategoryLogger
    
    // Counters for diagnostics
    private var initAttempts: Int = 0
    private var initSuccesses: Int = 0
    private var initFailures: Int = 0
    private var retriesScheduled: Int = 0
    private var raceConditionsDetected: Int = 0
    
    public init(loggerProvider: @escaping () async -> CategoryLogger) {
        self.logger = loggerProvider
    }
    
    // MARK: - Initialization Events
    
    /// Called when pusher initialization is attempted.
    public func onPusherInitAttempt(hasApiKey: Bool) async {
        initAttempts += 1
        await logger().debug([
            "stage": .string("pusher_init_attempt"),
            "has_api_key": .bool(hasApiKey),
            "attempt_number": .int(Int64(initAttempts))
        ])
    }
    
    /// Called when pusher initializes successfully.
    public func onPusherInitSuccess(queueSize: Int) async {
        initSuccesses += 1
        await logger().info([
            "stage": .string("pusher_init_success"),
            "queue_size": .int(Int64(queueSize)),
            "total_successes": .int(Int64(initSuccesses))
        ])
        print("[PusherHealthLogger] Pusher initialized successfully (queue=\(queueSize))")
    }
    
    /// Called when pusher fails to initialize.
    public func onPusherInitFailure(reason: String) async {
        initFailures += 1
        await logger().warning([
            "stage": .string("pusher_init_failure"),
            "reason": .string(reason),
            "total_failures": .int(Int64(initFailures))
        ])
        print("[PusherHealthLogger] Pusher init failed: \(reason)")
    }
    
    // MARK: - Retry Events
    
    /// Called when a retry is scheduled.
    public func onRetryScheduled(attempt: Int, delayMs: Int64) async {
        retriesScheduled += 1
        await logger().debug([
            "stage": .string("retry_scheduled"),
            "attempt": .int(Int64(attempt)),
            "delay_ms": .int(delayMs),
            "total_retries": .int(Int64(retriesScheduled))
        ])
    }
    
    /// Called when retry succeeds after previous failures.
    public func onRetrySuccess(attempt: Int, totalLatencyMs: Int64) async {
        await logger().info([
            "stage": .string("retry_success"),
            "attempt": .int(Int64(attempt)),
            "total_latency_ms": .int(totalLatencyMs)
        ])
    }
    
    /// Called when all retries are exhausted.
    public func onRetriesExhausted(totalAttempts: Int, lastError: String) async {
        await logger().error([
            "stage": .string("retries_exhausted"),
            "total_attempts": .int(Int64(totalAttempts)),
            "last_error": .string(lastError)
        ])
        print("[PusherHealthLogger] All retries exhausted after \(totalAttempts) attempts: \(lastError)")
    }
    
    // MARK: - Race Condition Detection
    
    /// Called when a race condition is detected.
    public func onRaceConditionDetected(context: String) async {
        raceConditionsDetected += 1
        await logger().warning([
            "stage": .string("race_condition_detected"),
            "context": .string(context),
            "total_detected": .int(Int64(raceConditionsDetected))
        ])
        print("[PusherHealthLogger] Race condition detected: \(context)")
    }
    
    // MARK: - Queue Events
    
    /// Called when queue reaches high watermark.
    public func onQueueHighWatermark(size: Int, maxSize: Int) async {
        await logger().warning([
            "stage": .string("queue_high_watermark"),
            "current_size": .int(Int64(size)),
            "max_size": .int(Int64(maxSize)),
            "utilization_pct": .int(Int64(size * 100 / max(maxSize, 1)))
        ])
    }
    
    /// Called when queue is drained successfully.
    public func onQueueDrained(eventCount: Int, durationMs: Int64) async {
        await logger().debug([
            "stage": .string("queue_drained"),
            "event_count": .int(Int64(eventCount)),
            "duration_ms": .int(durationMs)
        ])
    }
    
    // MARK: - Diagnostics
    
    /// Returns current diagnostic counters.
    public func diagnostics() -> (
        initAttempts: Int,
        initSuccesses: Int,
        initFailures: Int,
        retriesScheduled: Int,
        raceConditions: Int
    ) {
        (initAttempts, initSuccesses, initFailures, retriesScheduled, raceConditionsDetected)
    }
    
    /// Resets counters (for testing).
    public func resetCounters() {
        initAttempts = 0
        initSuccesses = 0
        initFailures = 0
        retriesScheduled = 0
        raceConditionsDetected = 0
    }
}
