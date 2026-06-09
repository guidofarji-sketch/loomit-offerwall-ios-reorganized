//
//  SdkE2ETests.swift
//  LoomitOfferwallCoreTests
//
//  Test E2E del flujo completo del SDK iOS contra backend real (Staging).
//  Verifica:
//  1. fetchConfig → config_success (auto)
//  2. initAllFromPlan con stub adapter → init_success + providers_initialization_complete
//  3. Lifecycle start → providers_availability_snapshot
//
//  Los eventos se envían al backend real Y se capturan via tracking listener.
//

import XCTest
import UIKit
import LoomitOfferwallAdapterAPI
@testable import LoomitOfferwallCore

@MainActor
final class SdkE2ETests: XCTestCase {

    // Credenciales de staging
    private let apiKey = "lmt_b1debf8669027a925c0e60cf3e0377e206c47e8c8dba3897"
    private let clientId = "cl_417b8"
    private let appId = "ap_41d5f8d28c"

    private var trackingListener: TestTrackingListener!

    override func setUp() async throws {
        try await super.setUp()
        trackingListener = TestTrackingListener()
        // Reset singleton state between tests
        await OfferwallSdk.shared.__resetForTesting()
    }

    override func tearDown() async throws {
        trackingListener = nil
        try await super.tearDown()
    }

    // MARK: - Test E2E: Full SDK flow with stub adapter

    func test_fullFlow_withStubAdapter_lifecycle_and_snapshot() async throws {
        let sdk = OfferwallSdk.shared

        // 1. Configure SDK with staging credentials
        await sdk.setLoomitApiKey(apiKey)
        await sdk.setClientId(clientId)
        await sdk.setAppId(appId)
        await sdk.setEnvironment(.test)

        // 2. Register tracking listener
        await sdk.setTrackingListener(trackingListener)

        // 3. Register stub adapter that matches "maf" (backend waterfall key)
        let stubAdapter = StubMafAdapter()
        await sdk.registerAdapter(stubAdapter)

        // 4. fetchConfig() against staging backend
        let configResponse = try await sdk.fetchConfig()

        // 5. Verify valid config
        XCTAssertNotNil(configResponse.offerwall, "Config debe tener offerwall")
        let waterfall = configResponse.offerwall?.defaultWaterfall ?? []
        XCTAssertFalse(waterfall.isEmpty, "Config debe tener providers en defaultWaterfall")
        print("📋 Waterfall: \(waterfall.map { $0.providerId })")

        // 6. Wait for async event dispatch
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // 7. Verify config_success auto-emitted
        let eventsAfterConfig = trackingListener.getEvents()
        let configSuccessEvents = eventsAfterConfig.filter { $0.name == "config_success" }
        XCTAssertEqual(configSuccessEvents.count, 1, "Debe haber 1 config_success")
        if let cs = configSuccessEvents.first {
            print("✅ config_success: \(cs.payload)")
        }

        // 8. Verify plan was built
        let plan = await sdk.getProviderPlan()
        XCTAssertFalse(plan.isEmpty, "Provider plan debe tener entries")
        print("📋 Plan: \(plan.map { "\($0.providerId) (p=\($0.priority))" })")

        // 9. initAllFromPlan() — stub adapter handles "maf", should succeed
        trackingListener.clear()
        await sdk.initAllFromPlan()

        // 10. providers_initialization_complete fires synchronously
        //     Per Kotlin reference, per-provider events (init_provider_success/init_provider_failed)
        //     are debug-only (sendDebugEvent) and NOT pushed to backend via emitEvent.
        //     Only providers_initialization_complete goes to the backend.
        let immediateEvents = trackingListener.getEvents()
        let immediateNames = immediateEvents.map { $0.name }
        print("📊 Events immediately after initAllFromPlan: \(immediateNames)")

        let initComplete = immediateEvents.filter { $0.name == "providers_initialization_complete" }
        XCTAssertEqual(initComplete.count, 1, "Debe haber 1 providers_initialization_complete")
        if let ic = initComplete.first {
            XCTAssertEqual(ic.payload["successful_providers"], .int(1))
            XCTAssertEqual(ic.payload["all_providers_failed"], .bool(false))
            XCTAssertEqual(ic.payload["sdk_status"], .string("fully_operational"))
            print("✅ providers_initialization_complete: \(ic.payload)")
        }

        // No init_success or init_error events should exist (they are debug-only in Kotlin)
        XCTAssertTrue(immediateEvents.filter { $0.name == "init_success" }.isEmpty,
                       "init_success should NOT be emitted to backend")
        XCTAssertTrue(immediateEvents.filter { $0.name == "init_error" }.isEmpty,
                       "init_error should NOT be emitted to backend")

        // 11. Wait for 2s grace period + margin for providers_availability_snapshot
        //     (Kotlin: delay(2000) grace period for content validation before lifecycle start)
        try await Task.sleep(nanoseconds: 9_000_000_000) // 8s barrier + 1s margin

        let allInitEvents = trackingListener.getEvents()
        let allInitNames = allInitEvents.map { $0.name }
        print("📊 Events after grace period: \(allInitNames)")

        // providers_availability_snapshot (lifecycle started AFTER grace period)
        let snapshot = allInitEvents.filter { $0.name == "providers_availability_snapshot" }
        XCTAssertEqual(snapshot.count, 1, "Debe haber 1 providers_availability_snapshot (after grace period)")
        if let snap = snapshot.first {
            XCTAssertEqual(snap.payload["available_providers"], .int(1))
            XCTAssertEqual(snap.payload["sdk_ready"], .bool(true))
            if case .int(let lcId) = snap.payload["lifecycle_id"] {
                XCTAssertGreaterThan(lcId, 0, "lifecycle_id debe ser > 0")
                print("✅ providers_availability_snapshot: lifecycle_id=\(lcId)")
            } else {
                XCTFail("lifecycle_id debe ser un int")
            }
            print("✅ providers_availability_snapshot: \(snap.payload)")
        }

        // 12. Verify correct temporal ordering: init_complete BEFORE snapshot
        let initCompleteIdx = allInitEvents.firstIndex { $0.name == "providers_initialization_complete" }
        let snapshotIdx = allInitEvents.firstIndex { $0.name == "providers_availability_snapshot" }
        if let ic = initCompleteIdx, let sn = snapshotIdx {
            XCTAssertLessThan(ic, sn,
                "providers_initialization_complete must come BEFORE providers_availability_snapshot")
        }

        // 13. Verify providersInitialized flag
        let isInit = await sdk.hasProvidersInitialized()
        XCTAssertTrue(isInit, "SDK debe reportar providers inicializados")

        // 14. Debug bridge
        let debugBridge = SdkDebugBridge(sdk: sdk)
        let xifa = await debugBridge.xifa()

        // 15. Summary
        let allEvents = eventsAfterConfig + allInitEvents
        let allTypes = Set(allEvents.map { $0.name }).sorted()
        print("\n✅ Test E2E completo — flujo con adapter")
        print("   - Total eventos backend: \(allEvents.count)")
        print("   - Tipos: \(allTypes)")
        print("   - XIFA: \(xifa)")

        // Assert all 4 event types were emitted (no init_success/init_error)
        XCTAssertTrue(allTypes.contains("config_success"))
        XCTAssertTrue(allTypes.contains("providers_initialization_complete"))
        XCTAssertTrue(allTypes.contains("providers_availability_snapshot"))
        XCTAssertFalse(allTypes.contains("init_success"), "init_success is debug-only, not backend")
        XCTAssertFalse(allTypes.contains("init_error"), "init_error is debug-only, not backend")
    }

    // MARK: - Test E2E: Show flow

    func test_show_flow_emits_content_show_and_dismiss() async throws {
        let sdk = OfferwallSdk.shared

        // 1. Configure SDK
        await sdk.setLoomitApiKey(apiKey)
        await sdk.setClientId(clientId)
        await sdk.setAppId(appId)
        await sdk.setEnvironment(.test)

        // 2. Register tracking listener
        await sdk.setTrackingListener(trackingListener)

        // 3. Register stub adapter
        let stubAdapter = StubMafAdapter()
        await sdk.registerAdapter(stubAdapter)

        // 3. Fetch config
        _ = try await sdk.fetchConfig()

        // 4. Init providers
        await sdk.initAllFromPlan()
        try await Task.sleep(nanoseconds: 3_000_000_000) // Wait for 2s grace + snapshot

        // 5. Verify ready state
        let isInit = await sdk.hasProvidersInitialized()
        let hasAvail = await sdk.hasAvailableOfferwall()
        XCTAssertTrue(isInit)
        XCTAssertTrue(hasAvail)

        // 6. Show offerwall (use a dummy presenter)
        let dummyVC = UIViewController()
        // Don't clear trackingListener - we need to see both snapshots (init + post-close)
        // trackingListener.clear()

        await sdk.show(from: dummyVC, adSpace: "test_ad_space")

        // 7. Verify show_request and content_show events
        let showEvents = trackingListener.getEvents()
        let showEventNames = showEvents.map { $0.name }
        print("📊 Events after show: \(showEventNames)")

        let showRequest = showEvents.filter { $0.name == "show_request" }
        XCTAssertEqual(showRequest.count, 1, "Debe haber 1 show_request")
        if let sr = showRequest.first {
            XCTAssertEqual(sr.payload["provider"], .string("maf"))
            XCTAssertEqual(sr.payload["ad_space"], .string("test_ad_space"))
            print("✅ show_request: \(sr.payload)")
        }

        let contentShow = showEvents.filter { $0.name == "content_show" }
        XCTAssertEqual(contentShow.count, 1, "Debe haber 1 content_show")
        if let cs = contentShow.first {
            XCTAssertEqual(cs.payload["provider"], .string("maf"))
            print("✅ content_show: \(cs.payload)")
        }

        // 8. Simulate close (call close on the actual provider instance used by SDK)
        let provider = StubMafProvider.lastInstance
        XCTAssertNotNil(provider, "Debe haber una instancia del provider creada por initAllFromPlan")

        // Close the offerwall
        provider?.close()

        // 9. Wait for close event
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let allEvents = trackingListener.getEvents()
        let allEventNames = allEvents.map { $0.name }
        print("📊 Events after close: \(allEventNames)")

        let contentDismiss = allEvents.filter { $0.name == "content_dismiss" }
        XCTAssertEqual(contentDismiss.count, 1, "Debe haber 1 content_dismiss")
        if let cd = contentDismiss.first {
            XCTAssertEqual(cd.payload["provider"], .string("maf"))
            print("✅ content_dismiss: \(cd.payload)")
        }

        // 10. Verify lifecycle restarted (new snapshot after close)
        let snapshots = allEvents.filter { $0.name == "providers_availability_snapshot" }
        // First snapshot after init, second after close
        XCTAssertEqual(snapshots.count, 2, "Debe haber 2 snapshots (init + post-close)")
        if snapshots.count >= 2 {
            let firstLcId = snapshots[0].payload["lifecycle_id"]
            let secondLcId = snapshots[1].payload["lifecycle_id"]
            XCTAssertNotEqual(firstLcId, secondLcId, "Lifecycle IDs deben ser diferentes (restart)")
            print("✅ Lifecycle restarted: \(firstLcId) → \(secondLcId)")
        }

        print("\n✅ Show flow test completo — eventos emitidos correctamente")
    }
}

// MARK: - Test Provider Listener

@MainActor
class TestProviderListener: OfferwallProviderListener {
    func providerDidInitialize(_ providerKey: String) {}
    func provider(_ providerKey: String, didFailToInitializeWith error: OfferwallError) {}
    func provider(_ providerKey: String, didChangeAvailability isAvailable: Bool) {}
    func provider(_ providerKey: String, didEarnRewardAmount amount: Int, currency: String) {}
    func providerDidClose(_ providerKey: String) {}
    func providerDidShow(_ providerKey: String) {}
}

// MARK: - Test Tracking Listener

/// Listener de test para capturar eventos de tracking
@MainActor
class TestTrackingListener: OfferwallTrackingListener {

    struct TrackedEvent: Equatable {
        let name: String
        let payload: [String: JSONValue]
        let timestamp: Date
    }

    private var events: [TrackedEvent] = []

    init() {}

    func offerwallTracking(didDispatchEvent name: String, payload: [String: JSONValue]) {
        let event = TrackedEvent(
            name: name,
            payload: payload,
            timestamp: Date()
        )
        events.append(event)
        print("📊 Event tracked: \(name) payload: \(payload)")
    }

    func getEvents() -> [TrackedEvent] {
        events
    }

    func clear() {
        events.removeAll()
    }
}

// MARK: - Stub MAF Adapter (lightweight, no real SDK dependency)

/// Stub adapter that matches "maf"/"mychips" keys. Lives in test target
/// so core never imports a concrete adapter (§10 anti-pattern).
final class StubMafAdapter: OfferwallAdapter, @unchecked Sendable {
    let providerName: String = "MAF-Stub"
    let supportedKeys: [String] = ["maf", "mychips"]

    @MainActor
    func createProvider() -> OfferwallProvider {
        StubMafProvider()
    }
}

/// Stub provider that always initializes successfully and reports available.
@MainActor
final class StubMafProvider: OfferwallProvider {
    nonisolated let providerKey: String = "maf"
    nonisolated let providerSdkVersion: String? = "stub-1.0"

    private var initialized = false
    private var listener: OfferwallProviderListener?

    /// Static reference to the last created instance (for testing close flow)
    @MainActor
    static var lastInstance: StubMafProvider?

    func initialize(
        config: ProviderConfig,
        listener: OfferwallProviderListener
    ) async -> Result<Void, OfferwallError> {
        self.listener = listener
        initialized = true
        Self.lastInstance = self // Store reference for test access
        listener.providerDidInitialize(providerKey)
        listener.provider(providerKey, didChangeAvailability: true)
        return .success(())
    }

    func isAvailable() -> Bool {
        initialized
    }

    func show(from presenter: UIViewController, adSpace: String?) async -> Result<Void, OfferwallError> {
        guard initialized else {
            return .failure(.providerUnavailable(provider: providerKey, reason: "not initialized"))
        }
        return .success(())
    }

    func close() {
        // Signal close to core via listener
        listener?.providerDidClose(providerKey)
    }
}
