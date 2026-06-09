//
//  MyChipsAdapterE2ETest.swift
//  LoomitOfferwallCoreTests
//
//  Test E2E del SDK iOS con MyChipsAdapter real (usando MockMyChipsSDKBridge).
//  Verifica el flujo completo: fetchConfig → initAllFromPlan → show → close
//

import XCTest
import UIKit
import LoomitOfferwallAdapterAPI
import LoomitOfferwallAdapterMyChips
@testable import LoomitOfferwallCore

@MainActor
final class MyChipsAdapterE2ETest: XCTestCase {

    // Credenciales de staging
    private let apiKey = "lmt_b1debf8669027a925c0e60cf3e0377e206c47e8c8dba3897"
    private let clientId = "cl_417b8"
    private let appId = "ap_41d5f8d28c"

    private var trackingListener: TestTrackingListener!

    override func setUp() async throws {
        try await super.setUp()
        trackingListener = TestTrackingListener()
        await OfferwallSdk.shared.__resetForTesting()
    }

    override func tearDown() async throws {
        trackingListener = nil
        MyChipsAdapter.overrideBridgeFactory = nil
        MyChipsProvider.lastInstance = nil
        try await super.tearDown()
    }

    // MARK: - Test E2E: MyChipsAdapter real con MockMyChipsSDKBridge

    func test_mychips_adapter_full_flow_with_mock_bridge() async throws {
        let sdk = OfferwallSdk.shared

        // 1. Configure SDK
        await sdk.setLoomitApiKey(apiKey)
        await sdk.setClientId(clientId)
        await sdk.setAppId(appId)
        await sdk.setEnvironment(.test)

        // 2. Register tracking listener
        await sdk.setTrackingListener(trackingListener)

        // 3. Create mock bridge for testing and set as override
        let mockBridge = MockMyChipsSDKBridge()
        MyChipsAdapter.overrideBridgeFactory = { mockBridge }

        // 4. Register MyChipsAdapter (SDK will use the override factory)
        let myChipsAdapter = MyChipsAdapter()
        await sdk.registerAdapter(myChipsAdapter)

        // 5. Fetch config
        let configResponse = try await sdk.fetchConfig()

        // 6. Verify config includes mychips/maf
        XCTAssertNotNil(configResponse.offerwall, "Config debe tener offerwall")
        let waterfall = configResponse.offerwall?.defaultWaterfall ?? []
        XCTAssertFalse(waterfall.isEmpty, "Config debe tener providers en defaultWaterfall")
        print("📋 Waterfall: \(waterfall.map { $0.providerId })")

        let hasMyChips = waterfall.contains { $0.providerId.lowercased() == "mychips" || $0.providerId.lowercased() == "maf" }
        XCTAssertTrue(hasMyChips, "Waterfall debe incluir mychips/maf")

        // 6. Wait for config_success event
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let eventsAfterConfig = trackingListener.getEvents()
        let configSuccess = eventsAfterConfig.filter { $0.name == "config_success" }
        XCTAssertEqual(configSuccess.count, 1, "Debe haber 1 config_success")

        // 7. Init providers
        trackingListener.clear()
        await sdk.initAllFromPlan()

        // 8. Verify init events
        let initEvents = trackingListener.getEvents()
        let initComplete = initEvents.filter { $0.name == "providers_initialization_complete" }
        XCTAssertEqual(initComplete.count, 1, "Debe haber 1 providers_initialization_complete")
        if let ic = initComplete.first {
            XCTAssertEqual(ic.payload["successful_providers"], .int(1))
            print("✅ providers_initialization_complete: \(ic.payload)")
        }

        // 9. Verify MyChipsAdapter was initialized correctly
        let configureCalls = mockBridge.calls.filter {
            if case .configure = $0 { return true }
            return false
        }
        XCTAssertEqual(configureCalls.count, 1, "MyChipsSDK.configure debe haber sido llamado")
        print("📋 MyChipsSDK calls: \(mockBridge.calls)")

        // 10. Wait for 2s grace + snapshot
        try await Task.sleep(nanoseconds: 3_000_000_000)

        let allInitEvents = trackingListener.getEvents()
        let snapshots = allInitEvents.filter { $0.name == "providers_availability_snapshot" }
        XCTAssertEqual(snapshots.count, 1, "Debe haber 1 providers_availability_snapshot")

        // 11. Verify ready state
        let isInit = await sdk.hasProvidersInitialized()
        let hasAvail = await sdk.hasAvailableOfferwall()
        XCTAssertTrue(isInit)
        XCTAssertTrue(hasAvail)

        // 12. Debug snapshot (via debugBridge)
        let xifa = await sdk.debugBridge().xifa()
        let fp = await sdk.debugBridge().deviceFingerprint()
        print("📊 Debug info:")
        print("   - XIFA: \(xifa)")
        print("   - Device fingerprint: \(fp)")

        // 13. Show offerwall
        let dummyVC = UIViewController()
        // Don't clear tracking listener - we need to capture init snapshot + show events + post-close snapshot
        // trackingListener.clear()

        await sdk.show(from: dummyVC, adSpace: "test_ad_space")

        // 14. Verify show events
        let showEvents = trackingListener.getEvents()
        let showRequest = showEvents.filter { $0.name == "show_request" }
        XCTAssertEqual(showRequest.count, 1, "Debe haber 1 show_request")
        if let sr = showRequest.first {
            XCTAssertEqual(sr.payload["provider"], .string("maf"))
            print("✅ show_request: \(sr.payload)")
        }

        let contentShow = showEvents.filter { $0.name == "content_show" }
        XCTAssertEqual(contentShow.count, 1, "Debe haber 1 content_show")
        if let cs = contentShow.first {
            XCTAssertEqual(cs.payload["provider"], .string("maf"))
            print("✅ content_show: \(cs.payload)")
        }

        // 15. Verify MyChips makeWebViewController was called
        let makeWebCalls = mockBridge.calls.filter {
            if case .makeWebViewController = $0 { return true }
            return false
        }
        XCTAssertEqual(makeWebCalls.count, 1, "makeWebViewController debe haber sido llamado")
        XCTAssertNotNil(mockBridge.lastOnClose, "onClose callback debe haber sido capturado")

        // 16. Simulate close via the actual provider instance created by SDK
        let provider = MyChipsProvider.lastInstance
        XCTAssertNotNil(provider, "Debe haber una instancia del provider creada por initAllFromPlan")
        provider?.close()

        // 17. Wait for close event
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let allEvents = trackingListener.getEvents()
        let contentDismiss = allEvents.filter { $0.name == "content_dismiss" }
        XCTAssertEqual(contentDismiss.count, 1, "Debe haber 1 content_dismiss")
        if let cd = contentDismiss.first {
            // MyChipsAdapter supports both "mychips" and "maf" keys
            let providerVal = cd.payload["provider"]
            XCTAssertTrue(
                providerVal == .string("mychips") || providerVal == .string("maf"),
                "Provider debe ser mychips o maf"
            )
            print("✅ content_dismiss: \(cd.payload)")
        }

        // 18. Verify lifecycle restarted
        let allSnapshots = allEvents.filter { $0.name == "providers_availability_snapshot" }
        print("📊 Total snapshots found: \(allSnapshots.count)")
        for (i, snap) in allSnapshots.enumerated() {
            print("📊 Snapshot \(i): \(snap.payload)")
        }
        XCTAssertEqual(allSnapshots.count, 2, "Debe haber 2 snapshots (init + post-close)")
        if allSnapshots.count >= 2 {
            let firstLcId = allSnapshots[0].payload["lifecycle_id"]
            let secondLcId = allSnapshots[1].payload["lifecycle_id"]
            XCTAssertNotEqual(firstLcId, secondLcId, "Lifecycle IDs deben ser diferentes")
            print("✅ Lifecycle restarted: \(firstLcId) → \(secondLcId)")
        }

        print("\n✅ MyChipsAdapter E2E test completo — flujo real verificado")
    }
}
