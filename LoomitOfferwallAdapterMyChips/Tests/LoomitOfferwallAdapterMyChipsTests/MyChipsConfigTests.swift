//
//  MyChipsConfigTests.swift
//  LoomitOfferwallAdapterMyChipsTests
//

import XCTest
import LoomitOfferwallAdapterAPI
@testable import LoomitOfferwallAdapterMyChips

final class MyChipsConfigTests: XCTestCase {

    private func providerConfig(
        credentials: [String: String] = [:],
        settings: [String: String] = [:]
    ) -> ProviderConfig {
        ProviderConfig(
            providerKey: "mychips",
            priority: 1,
            credentials: credentials,
            settings: settings,
            privacy: .empty,
            userId: "u-1",
            xifa: "xifa-1",
            appId: "app",
            country: "AR",
            sdkVersion: "0.1",
            appVersion: "1.0"
        )
    }

    func test_parse_minimumValid_succeeds() throws {
        let pc = providerConfig(credentials: [
            "api_key": "key-123",
            "ad_unit_id": "adunit-xyz"
        ])
        let result = MyChipsConfig.parse(from: pc)
        guard case .success(let cfg) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(cfg.apiKey, "key-123")
        XCTAssertEqual(cfg.adUnitId, "adunit-xyz")
        XCTAssertNil(cfg.title)
        XCTAssertNil(cfg.age)
        XCTAssertNil(cfg.gender)
    }

    func test_parse_acceptsCamelCaseAliases() throws {
        let pc = providerConfig(credentials: [
            "apiKey": "k",
            "adUnitId": "a"
        ])
        guard case .success(let cfg) = MyChipsConfig.parse(from: pc) else {
            return XCTFail()
        }
        XCTAssertEqual(cfg.apiKey, "k")
        XCTAssertEqual(cfg.adUnitId, "a")
    }

    func test_parse_missingApiKey_fails() {
        let pc = providerConfig(credentials: ["ad_unit_id": "a"])
        guard case .failure(let err) = MyChipsConfig.parse(from: pc) else {
            return XCTFail()
        }
        if case .invalidConfiguration(let reason) = err {
            XCTAssertTrue(reason.contains("api_key"))
        } else {
            XCTFail("expected invalidConfiguration, got \(err)")
        }
    }

    func test_parse_missingAdUnitId_fallsBackToPlacementId() throws {
        let pc = providerConfig(
            credentials: ["api_key": "k"],
            settings: ["placement_id": "p-1"]
        )
        guard case .success(let cfg) = MyChipsConfig.parse(from: pc) else {
            return XCTFail()
        }
        XCTAssertEqual(cfg.adUnitId, "p-1")
    }

    func test_parse_missingAdUnitId_andPlacementId_fails() {
        let pc = providerConfig(credentials: ["api_key": "k"])
        guard case .failure = MyChipsConfig.parse(from: pc) else {
            return XCTFail()
        }
    }

    func test_parse_age_outOfRange_isIgnored() throws {
        let pc = providerConfig(credentials: [
            "api_key": "k", "ad_unit_id": "a", "age": "200"
        ])
        guard case .success(let cfg) = MyChipsConfig.parse(from: pc) else {
            return XCTFail()
        }
        XCTAssertNil(cfg.age, "age > 100 must be ignored")
    }

    func test_parse_age_validRange_isAccepted() throws {
        let pc = providerConfig(credentials: [
            "api_key": "k", "ad_unit_id": "a", "age": "30"
        ])
        guard case .success(let cfg) = MyChipsConfig.parse(from: pc) else {
            return XCTFail()
        }
        XCTAssertEqual(cfg.age, 30)
    }

    func test_parse_gender_normalizesCase() throws {
        let pc = providerConfig(credentials: [
            "api_key": "k", "ad_unit_id": "a", "gender": "FEMALE"
        ])
        guard case .success(let cfg) = MyChipsConfig.parse(from: pc) else {
            return XCTFail()
        }
        XCTAssertEqual(cfg.gender, .female)
    }

    func test_parse_affSubs_allFields() throws {
        let pc = providerConfig(credentials: [
            "api_key": "k", "ad_unit_id": "a",
            "aff_sub1": "1", "aff_sub2": "2", "aff_sub3": "3",
            "aff_sub4": "4", "aff_sub5": "5"
        ])
        guard case .success(let cfg) = MyChipsConfig.parse(from: pc) else {
            return XCTFail()
        }
        XCTAssertEqual(cfg.affSub1, "1")
        XCTAssertEqual(cfg.affSub2, "2")
        XCTAssertEqual(cfg.affSub3, "3")
        XCTAssertEqual(cfg.affSub4, "4")
        XCTAssertEqual(cfg.affSub5, "5")
    }
}
