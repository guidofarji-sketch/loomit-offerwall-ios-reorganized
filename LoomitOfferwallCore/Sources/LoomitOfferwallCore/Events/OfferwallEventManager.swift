//
//  OfferwallEventManager.swift
//  LoomitOfferwallCore
//
//  Central event dispatch with batching and deduplication.
//  Parity with Android `OfferwallEventManager.kt`.
//
//  Features:
//  - Batched events (e.g., providers_availability_snapshot) are deduplicated by LC
//  - Immediate events are sent right away
//  - Prioritizes lifecycle_id from payload over metadata (critical for batched events)
//

import Foundation

/// Metadata for event enrichment. Provided by OfferwallSdk.
public struct OfferwallEventMetadata: Sendable {
    public let xifa: String?
    public let appId: String?
    public let platform: String
    public let country: String?
    public let appVersion: String?
    public let sdkVersion: String?
    public let deviceModel: String
    public let osVersion: String
    public let currentPlacement: String?
    public let currentUserId: String?
    public let isTestMode: Bool
    public let lifecycleId: Int?
    
    public init(
        xifa: String?,
        appId: String?,
        platform: String,
        country: String?,
        appVersion: String?,
        sdkVersion: String?,
        deviceModel: String,
        osVersion: String,
        currentPlacement: String?,
        currentUserId: String?,
        isTestMode: Bool,
        lifecycleId: Int?
    ) {
        self.xifa = xifa
        self.appId = appId
        self.platform = platform
        self.country = country
        self.appVersion = appVersion
        self.sdkVersion = sdkVersion
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.currentPlacement = currentPlacement
        self.currentUserId = currentUserId
        self.isTestMode = isTestMode
        self.lifecycleId = lifecycleId
    }
}

/// Descriptor for an event to be dispatched.
public struct OfferwallEventDescriptor: Sendable {
    public let type: String
    public let provider: String
    public let payload: [String: JSONValue]
    public let lifecycleId: Int?
    public let includeLifecycleInPayload: Bool
    public let timestampMs: Int64
    
    public init(
        type: String,
        provider: String,
        payload: [String: JSONValue] = [:],
        lifecycleId: Int? = nil,
        includeLifecycleInPayload: Bool = true,
        timestampMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.type = type
        self.provider = provider
        self.payload = payload
        self.lifecycleId = lifecycleId
        self.includeLifecycleInPayload = includeLifecycleInPayload
        self.timestampMs = timestampMs
    }
}

/// Central event manager with batching support.
/// Parity with Android `OfferwallEventManager`.
@available(iOS 13.0, macOS 10.15, *)
public actor OfferwallEventManager {
    
    /// Event types that are batched (deduplicated by lifecycle ID).
    private let batchedEventTypes: Set<String> = ["providers_availability_snapshot"]
    
    /// Pending batched events, keyed by "type:provider:lifecycleId".
    private var pendingEvents: [String: OfferwallEventDescriptor] = [:]
    
    /// Batch flush interval.
    private let batchIntervalMs: Int64 = 15_000
    
    /// Batch flush task.
    private var batchTask: Task<Void, Never>?
    
    /// In-memory buffer for events when pusher is not configured.
    private var pendingBuffer: [OfferwallEvent] = []
    private let pendingBufferCapacity: Int = 100
    
    // Dependencies (injected)
    private let metadataProvider: @Sendable () async -> OfferwallEventMetadata
    private let trackingCallback: @Sendable (String, String, [String: JSONValue]) async -> Void
    private let eventPusherProvider: @Sendable () async -> OfferwallEventPusher?
    private let eventQueueProvider: @Sendable () async -> EventQueue?
    private let eventTrackingLogger: EventTrackingLogger?
    
    public init(
        metadataProvider: @escaping @Sendable () async -> OfferwallEventMetadata,
        trackingCallback: @escaping @Sendable (String, String, [String: JSONValue]) async -> Void,
        eventPusherProvider: @escaping @Sendable () async -> OfferwallEventPusher?,
        eventQueueProvider: @escaping @Sendable () async -> EventQueue?,
        eventTrackingLogger: EventTrackingLogger? = nil
    ) {
        self.metadataProvider = metadataProvider
        self.trackingCallback = trackingCallback
        self.eventPusherProvider = eventPusherProvider
        self.eventQueueProvider = eventQueueProvider
        self.eventTrackingLogger = eventTrackingLogger
    }
    
    // MARK: - Public API
    
    /// Dispatches an event. Batched events are deduplicated; others are sent immediately.
    public func dispatch(_ descriptor: OfferwallEventDescriptor) async {
        // Notify tracking callback with raw payload
        await trackingCallback(descriptor.type, descriptor.provider, descriptor.payload)
        
        if batchedEventTypes.contains(descriptor.type) {
            enqueueBatched(descriptor)
        } else {
            await sendNow(descriptor)
        }
    }
    
    /// Forces flush of all pending batched events.
    public func flushBatch() async {
        let toFlush: [OfferwallEventDescriptor]
        toFlush = Array(pendingEvents.values)
        pendingEvents.removeAll()
        
        for descriptor in toFlush {
            await sendNow(descriptor)
        }
    }
    
    /// Flushes pending buffer when pusher becomes available.
    public func flushPendingBuffer() async {
        guard !pendingBuffer.isEmpty else { return }
        
        let pusher = await eventPusherProvider()
        guard pusher != nil else { return }
        
        let events = pendingBuffer
        pendingBuffer.removeAll()
        
        var successCount = 0
        for event in events {
            do {
                try await pusher?.push(event)
                successCount += 1
            } catch {
                print("[OfferwallEventManager] Failed to flush buffered event: \(error)")
            }
        }
        
        await eventTrackingLogger?.onBufferFlushed(count: events.count, successCount: successCount)
    }
    
    /// Returns current pending buffer size.
    public func pendingBufferSize() -> Int {
        pendingBuffer.count
    }
    
    // MARK: - Private: Batching
    
    private func enqueueBatched(_ descriptor: OfferwallEventDescriptor) {
        // Extract lifecycle_id from payload for dedup key
        let lifecycleIdFromPayload = extractLifecycleId(from: descriptor.payload)
        let lifecycleIdForKey = descriptor.lifecycleId ?? lifecycleIdFromPayload
        
        // Build dedup key
        let key: String
        if descriptor.type == "providers_availability_snapshot",
           let lcId = lifecycleIdForKey, lcId != 0 {
            key = "\(descriptor.type):\(descriptor.provider):\(lcId)"
        } else {
            key = "\(descriptor.type):\(descriptor.provider)"
        }
        
        pendingEvents[key] = descriptor
        
        // Schedule batch flush if not already scheduled
        if batchTask == nil {
            batchTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(batchIntervalMs) * 1_000_000)
                await self.flushBatch()
                self.batchTask = nil
            }
        }
    }
    
    // MARK: - Private: Send
    
    private func sendNow(_ descriptor: OfferwallEventDescriptor) async {
        let metadata = await metadataProvider()
        
        // CRITICAL: Prioritize lifecycle_id from payload (captured at event creation time)
        // over metadata (which reflects current state at flush time).
        // This is critical for batched events. Parity with Android fix.
        let lifecycleIdFromPayload = extractLifecycleId(from: descriptor.payload)
        let lifecycleId = descriptor.lifecycleId ?? lifecycleIdFromPayload ?? metadata.lifecycleId
        
        let timestamp = descriptor.timestampMs
        
        // Enrich payload
        var enrichedPayload = descriptor.payload
        if descriptor.includeLifecycleInPayload, let lcId = lifecycleId, lcId != 0 {
            if enrichedPayload["lifecycle_id"] == nil {
                enrichedPayload["lifecycle_id"] = .int(Int64(lcId))
            }
        }
        if let placement = metadata.currentPlacement, !placement.isEmpty {
            if enrichedPayload["placement"] == nil {
                enrichedPayload["placement"] = .string(placement)
            }
        }
        if let userId = metadata.currentUserId, !userId.isEmpty {
            if enrichedPayload["user_id"] == nil {
                enrichedPayload["user_id"] = .string(userId)
            }
        }
        if enrichedPayload["is_test_mode"] == nil {
            enrichedPayload["is_test_mode"] = .bool(metadata.isTestMode)
        }
        if enrichedPayload["timestamp_ms"] == nil {
            enrichedPayload["timestamp_ms"] = .int(timestamp)
        }
        
        // Build event
        let event = OfferwallEvent(
            type: descriptor.type,
            provider: descriptor.provider,
            xifa: metadata.xifa,
            appId: metadata.appId,
            platform: metadata.platform,
            country: metadata.country,
            appVersion: metadata.appVersion,
            sdkVersion: metadata.sdkVersion,
            deviceModel: metadata.deviceModel,
            osVersion: metadata.osVersion,
            lifecycleId: lifecycleId,
            timestampMs: timestamp,
            data: enrichedPayload
        )
        
        // Log event emission
        await eventTrackingLogger?.onEventEmitted(
            type: event.type,
            provider: event.provider,
            hasUserId: enrichedPayload["user_id"] != nil,
            hasXifa: event.xifa != nil && !event.xifa!.isEmpty,
            lifecycleId: lifecycleId
        )
        
        // Push event
        let pusher = await eventPusherProvider()
        if let pusher = pusher {
            print("[OfferwallEventManager] Pushing event '\(descriptor.type)' for provider '\(descriptor.provider)'" +
                  (lifecycleId.map { " (lifecycle=\($0))" } ?? ""))
            do {
                try await pusher.push(event)
            } catch {
                print("[OfferwallEventManager] Push failed: \(error)")
            }
        } else {
            // No pusher: try disk queue, then memory buffer
            if let queue = await eventQueueProvider() {
                let priority = EventPriority.from(eventType: event.type)
                let enqueued = await queue.enqueue(event, priority: priority)
                if enqueued {
                    let queueSize = await queue.getSize()
                    print("[OfferwallEventManager] Event '\(descriptor.type)' persisted to disk (queue=\(queueSize))")
                    await eventTrackingLogger?.onPusherNotConfigured(
                        type: descriptor.type,
                        provider: descriptor.provider,
                        buffered: true,
                        bufferSize: queueSize
                    )
                } else {
                    bufferInMemory(event, descriptor: descriptor)
                }
            } else {
                bufferInMemory(event, descriptor: descriptor)
            }
        }
    }
    
    private func bufferInMemory(_ event: OfferwallEvent, descriptor: OfferwallEventDescriptor) {
        if pendingBuffer.count >= pendingBufferCapacity {
            pendingBuffer.removeFirst() // drop oldest
        }
        pendingBuffer.append(event)
        
        print("[OfferwallEventManager] Event '\(descriptor.type)' buffered in memory (buffer=\(pendingBuffer.count)/\(pendingBufferCapacity))")
        
        Task {
            await eventTrackingLogger?.onPusherNotConfigured(
                type: descriptor.type,
                provider: descriptor.provider,
                buffered: true,
                bufferSize: pendingBuffer.count
            )
        }
    }
    
    // MARK: - Helpers
    
    private func extractLifecycleId(from payload: [String: JSONValue]) -> Int? {
        switch payload["lifecycle_id"] {
        case .int(let value):
            return Int(value)
        case .string(let str):
            return Int(str)
        default:
            return nil
        }
    }
}
