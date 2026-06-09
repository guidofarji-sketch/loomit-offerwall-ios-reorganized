//
//  SdkDebugBridge.swift
//  LoomitOfferwallCore
//
//  Implementación del `DebugBridge` que delega a un `OfferwallSdk` (actor).
//  Es la única ruta autorizada para que la Debug Suite externa observe estado
//  del SDK sin tocar internals.
//

import Foundation

/// Wrapper read-only que conforma `DebugBridge`. Construido por
/// `OfferwallSdk.debugBridge()`.
public struct SdkDebugBridge: DebugBridge {

    private let sdk: OfferwallSdk

    init(sdk: OfferwallSdk) {
        self.sdk = sdk
    }

    public func xifa() async -> String {
        await sdk.xifa()
    }

    public func deviceFingerprint() async -> String {
        await sdk.deviceFingerprint()
    }

    public func bundleIdentifier() async -> String? {
        await sdk.bundleIdentifierForDebug()
    }

    public func hasAdvertisingId() async -> Bool {
        await sdk.hasAdvertisingIdForDebug()
    }

    public func advertisingId() async -> String? {
        await sdk.advertisingIdForDebug()
    }

    public func publisherUserId() async -> String? {
        await sdk.publisherUserIdForDebug()
    }

    public func lastConfig() async -> ConfigResponse? {
        await sdk.lastConfig
    }

    public func lastConfigSource() async -> ConfigSource? {
        await sdk.lastConfigSource
    }

    public func cachedConfigInfo() async -> CachedConfigInfo? {
        await sdk.cachedConfigInfoForDebug()
    }

    public func resilienceState() async -> ResilienceState {
        await sdk.resilienceState()
    }

    public func pendingEvents() async -> [PendingEventInfo] {
        await sdk.pendingEventsForDebug()
    }

    public func pendingEventQueueSize() async -> Int {
        await sdk.pendingEventQueueSize()
    }

    public func registeredAdapterKeys() async -> [String] {
        await sdk.registeredAdapterKeysForDebug()
    }

    public func customPropertyDebugState() async -> [String: DebugCustomProperty] {
        await sdk.customPropertiesForDebug()
    }

    public func currentEnvironment() async -> BackendEnvironment {
        await sdk.environmentForDebug()
    }

    public func setEnvironmentForDebug(_ environment: BackendEnvironment) async {
        await sdk.forceSetEnvironment(environment)
        await sdk.persistDebugEnvironment(environment)
    }

    public func applyPersistedEnvironmentIfNeeded() async {
        await sdk.loadAndApplyDebugEnvironmentIfNeeded()
    }
}
