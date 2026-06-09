//
//  ConfigResponseTests.swift
//  LoomitOfferwallCoreTests
//
//  Tests de decoding del wire schema. Usamos un payload realista basado en
//  lo que el backend devuelve hoy (paridad con Android).
//

import XCTest
@testable import LoomitOfferwallCore

final class ConfigResponseTests: XCTestCase {

    func test_decode_realisticPayload() throws {
        let json = """
        {
            "segment": "default",
            "configurations": [],
            "offerwall": {
                "default_waterfall": [
                    {
                        "provider_id": "TAPJOY",
                        "is_active": true,
                        "provider_priority": 1,
                        "credentials": {
                            "sdk_key": "abc123",
                            "placement_id": "main_offerwall",
                            "test_mode": false,
                            "fallback_service_urls": ["https://a.com", "https://b.com"]
                        }
                    },
                    {
                        "provider_id": "mychips",
                        "is_active": true,
                        "provider_priority": 2,
                        "credentials": {
                            "app_id": "MAF-12345"
                        },
                        "placement": "rewards_tab"
                    }
                ],
                "ad_space_overrides": {
                    "checkout": {
                        "enabled": true,
                        "waterfall": [
                            {
                                "provider_id": "mychips",
                                "is_active": true,
                                "provider_priority": 1,
                                "credentials": {"app_id": "MAF-CHECKOUT"}
                            }
                        ]
                    },
                    "disabled_space": {
                        "enabled": false,
                        "waterfall": []
                    }
                }
            },
            "debugging": false,
            "logging_config": {
                "enabled": true,
                "endpoint": "https://logs.loomit.io/upload-logs",
                "batch_size": 50,
                "flush_interval_ms": 30000,
                "categories": {
                    "events": {
                        "enabled": true,
                        "sampling_rate": 1.0,
                        "max_per_hour": 1000,
                        "min_level": "info"
                    },
                    "network": {
                        "enabled": true,
                        "sampling_rate": 0.1,
                        "max_per_hour": 500
                    }
                }
            }
        }
        """

        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(ConfigResponse.self, from: data)

        // Top level
        XCTAssertEqual(response.segment, "default")
        XCTAssertTrue(response.configurations.isEmpty)
        XCTAssertEqual(response.debuggingStatus, false)

        // Offerwall block
        let offerwall = try XCTUnwrap(response.offerwall)
        XCTAssertEqual(offerwall.defaultWaterfall.count, 2)

        let tapjoy = offerwall.defaultWaterfall[0]
        XCTAssertEqual(tapjoy.providerId, "TAPJOY")
        XCTAssertEqual(tapjoy.normalizedProviderId, "tapjoy")
        XCTAssertEqual(tapjoy.priority, 1)
        XCTAssertEqual(tapjoy.credentialString("sdk_key"), "abc123")
        XCTAssertEqual(tapjoy.credentialString("placement_id"), "main_offerwall")
        XCTAssertEqual(tapjoy.credentialBool("test_mode"), false)
        XCTAssertNil(tapjoy.placement)

        let mychips = offerwall.defaultWaterfall[1]
        XCTAssertEqual(mychips.normalizedProviderId, "mychips")
        XCTAssertEqual(mychips.placement, "rewards_tab")
        XCTAssertEqual(mychips.credentialString("app_id"), "MAF-12345")

        // Overrides
        XCTAssertEqual(offerwall.adSpaceOverrides.count, 2)
        let checkout = try XCTUnwrap(offerwall.adSpaceOverrides["checkout"])
        XCTAssertTrue(checkout.enabled)
        XCTAssertEqual(checkout.waterfall.count, 1)
        XCTAssertEqual(checkout.waterfall[0].credentialString("app_id"), "MAF-CHECKOUT")

        let disabled = try XCTUnwrap(offerwall.adSpaceOverrides["disabled_space"])
        XCTAssertFalse(disabled.enabled)

        // Logging config
        let logging = try XCTUnwrap(response.loggingConfig)
        XCTAssertTrue(logging.enabled)
        XCTAssertEqual(logging.endpoint, "https://logs.loomit.io/upload-logs")
        XCTAssertEqual(logging.batchSize, 50)
        XCTAssertEqual(logging.flushIntervalMs, 30_000)
        XCTAssertEqual(logging.categories.count, 2)

        let eventsCat = try XCTUnwrap(logging.categories["events"])
        XCTAssertTrue(eventsCat.enabled)
        XCTAssertEqual(eventsCat.samplingRate, 1.0)
        XCTAssertEqual(eventsCat.maxPerHour, 1000)
        XCTAssertEqual(eventsCat.minLevel, "info")

        let networkCat = try XCTUnwrap(logging.categories["network"])
        XCTAssertEqual(networkCat.samplingRate, 0.1)
        XCTAssertNil(networkCat.minLevel)
    }

    func test_decode_minimalPayload_appliesDefaults() throws {
        let json = "{}"
        let response = try JSONDecoder().decode(ConfigResponse.self, from: Data(json.utf8))

        XCTAssertNil(response.segment)
        XCTAssertTrue(response.configurations.isEmpty)
        XCTAssertNil(response.offerwall)
        XCTAssertTrue(response.experiments.isEmpty)
        XCTAssertTrue(response.abTests.isEmpty)
        XCTAssertNil(response.debuggingStatus)
        XCTAssertNil(response.loggingConfig)
    }

    // MARK: - Waterfall resolution

    func test_resolvedWaterfall_default_filtersInactive_sortsbyPriority() {
        let block = OfferwallBlock(
            defaultWaterfall: [
                ProviderPlanEntry(providerId: "a", isActive: true,  priority: 3),
                ProviderPlanEntry(providerId: "b", isActive: false, priority: 1),  // skipped
                ProviderPlanEntry(providerId: "c", isActive: true,  priority: 2),
                ProviderPlanEntry(providerId: "d", isActive: true,  priority: 1)
            ]
        )

        let resolved = block.resolvedWaterfall(for: nil) ?? []
        XCTAssertEqual(resolved.map(\.providerId), ["d", "c", "a"])
    }

    func test_resolvedWaterfall_overrideEnabled_returnsOverrideWaterfall() {
        let block = OfferwallBlock(
            defaultWaterfall: [ProviderPlanEntry(providerId: "default", priority: 1)],
            adSpaceOverrides: [
                "checkout": AdSpaceOverride(
                    enabled: true,
                    waterfall: [ProviderPlanEntry(providerId: "override", priority: 1)]
                )
            ]
        )

        let resolved = block.resolvedWaterfall(for: "checkout") ?? []
        XCTAssertEqual(resolved.map(\.providerId), ["override"])
    }

    func test_resolvedWaterfall_overrideDisabled_returnsNil() {
        let block = OfferwallBlock(
            defaultWaterfall: [ProviderPlanEntry(providerId: "default", priority: 1)],
            adSpaceOverrides: [
                "promo": AdSpaceOverride(enabled: false, waterfall: [])
            ]
        )

        XCTAssertNil(block.resolvedWaterfall(for: "promo"))
    }

    func test_resolvedWaterfall_unknownAdSpace_fallsBackToDefault() {
        let block = OfferwallBlock(
            defaultWaterfall: [ProviderPlanEntry(providerId: "default", priority: 1)]
        )

        let resolved = block.resolvedWaterfall(for: "unknown") ?? []
        XCTAssertEqual(resolved.map(\.providerId), ["default"])
    }
}
