//
//  EventTrackingLogger.swift
//  LoomitOfferwallCore
//
//  Logger for event tracking pipeline health.
//  Parity with Android `EventTrackingLogger.kt`.
//
//  Logs to category: `event_tracking_health`
//
//  Events logged:
//  - event_emitted: SDK generated an event
//  - push_success: Event successfully sent to backend
//  - push_failure: Event failed to send
//  - event_dropped: Event was dropped (queue full, etc.)
//  - pusher_not_configured: Event buffered because pusher not ready
//

import Foundation

/// Logger for event tracking pipeline health metrics.
@available(iOS 13.0, macOS 10.15, *)
public actor EventTrackingLogger {
    
    private let logger: () async -> CategoryLogger
    
    // Counters for diagnostics
    private var eventsEmitted: Int = 0
    private var pushSuccesses: Int = 0
    private var pushFailures: Int = 0
    private var eventsDropped: Int = 0
    private var eventsBuffered: Int = 0
    
    public init(loggerProvider: @escaping () async -> CategoryLogger) {
        self.logger = loggerProvider
    }
    
    // MARK: - Event Lifecycle
    
    /// Called when an event is emitted by the SDK.
    public func onEventEmitted(
        type: String,
        provider: String,
        hasUserId: Bool,
        hasXifa: Bool,
        lifecycleId: Int?
    ) async {
        eventsEmitted += 1
        await logger().debug([
            "stage": .string("event_emitted"),
            "event_type": .string(type),
            "provider": .string(provider),
            "has_user_id": .bool(hasUserId),
            "has_xifa": .bool(hasXifa),
            "lifecycle_id": lifecycleId.map { .int(Int64($0)) } ?? .null,
            "total_emitted": .int(Int64(eventsEmitted))
        ])
    }
    
    /// Called when an event is successfully pushed to backend.
    public func onPushSuccess(
        type: String,
        provider: String,
        latencyMs: Int64
    ) async {
        pushSuccesses += 1
        await logger().debug([
            "stage": .string("push_success"),
            "event_type": .string(type),
            "provider": .string(provider),
            "latency_ms": .int(latencyMs),
            "total_successes": .int(Int64(pushSuccesses))
        ])
    }
    
    /// Called when an event fails to push.
    public func onPushFailure(
        type: String,
        provider: String,
        error: String,
        willRetry: Bool
    ) async {
        pushFailures += 1
        await logger().warning([
            "stage": .string("push_failure"),
            "event_type": .string(type),
            "provider": .string(provider),
            "error": .string(error),
            "will_retry": .bool(willRetry),
            "total_failures": .int(Int64(pushFailures))
        ])
        print("[EventTrackingLogger] Push failed: \(type) (\(error)), willRetry=\(willRetry)")
    }
    
    /// Called when an event is dropped (not retried).
    public func onEventDropped(
        type: String,
        provider: String,
        reason: String
    ) async {
        eventsDropped += 1
        await logger().warning([
            "stage": .string("event_dropped"),
            "event_type": .string(type),
            "provider": .string(provider),
            "reason": .string(reason),
            "total_dropped": .int(Int64(eventsDropped))
        ])
        print("[EventTrackingLogger] Event dropped: \(type) (\(reason))")
    }
    
    /// Called when an event is buffered because pusher is not configured.
    public func onPusherNotConfigured(
        type: String,
        provider: String,
        buffered: Bool,
        bufferSize: Int
    ) async {
        if buffered {
            eventsBuffered += 1
        }
        await logger().info([
            "stage": .string("pusher_not_configured"),
            "event_type": .string(type),
            "provider": .string(provider),
            "buffered": .bool(buffered),
            "buffer_size": .int(Int64(bufferSize)),
            "total_buffered": .int(Int64(eventsBuffered))
        ])
    }
    
    /// Called when buffered events are flushed after pusher becomes available.
    public func onBufferFlushed(count: Int, successCount: Int) async {
        await logger().info([
            "stage": .string("buffer_flushed"),
            "total_count": .int(Int64(count)),
            "success_count": .int(Int64(successCount))
        ])
        print("[EventTrackingLogger] Buffer flushed: \(successCount)/\(count) events sent")
    }
    
    /// Periodic heartbeat with pipeline health metrics.
    public func onHealthHeartbeat(queueSize: Int) async {
        await logger().debug([
            "stage": .string("pipeline_heartbeat"),
            "events_emitted": .int(Int64(eventsEmitted)),
            "push_successes": .int(Int64(pushSuccesses)),
            "push_failures": .int(Int64(pushFailures)),
            "events_dropped": .int(Int64(eventsDropped)),
            "events_buffered": .int(Int64(eventsBuffered)),
            "current_queue_size": .int(Int64(queueSize))
        ])
    }
    
    // MARK: - Diagnostics
    
    /// Returns current diagnostic counters.
    public func diagnostics() -> (
        emitted: Int,
        successes: Int,
        failures: Int,
        dropped: Int,
        buffered: Int
    ) {
        (eventsEmitted, pushSuccesses, pushFailures, eventsDropped, eventsBuffered)
    }
    
    /// Resets counters (for testing).
    public func resetCounters() {
        eventsEmitted = 0
        pushSuccesses = 0
        pushFailures = 0
        eventsDropped = 0
        eventsBuffered = 0
    }
}
