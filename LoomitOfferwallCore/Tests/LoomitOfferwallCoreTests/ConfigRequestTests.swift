//
//  ConfigRequestTests.swift
//  LoomitOfferwallCoreTests
//

import XCTest
@testable import LoomitOfferwallCore

final class ConfigRequestTests: XCTestCase {

    func test_encode_usesSnakeCaseKeys() throws {
        let request = ConfigRequest(
            clientId: "CLIENT-1",
            appId: "APP-1",
            packageName: "com.publisher.app",
            publisherUserId: "user-42",
            xifa: "xifa-uuid",
            tcfConsentString: "CO-tcf",
            country: "AR",
            platform: "ios",
            sdkVersion: "0.1.0",
            appVersion: "1.2.3",
            hasAdvertisingId: true,
            aaid: "idfa-uuid",
            customProperties: ["tier": "gold"]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        let json = String(data: data, encoding: .utf8) ?? ""

        // Sample of expected snake_case keys
        XCTAssertTrue(json.contains("\"client_id\":\"CLIENT-1\""), json)
        XCTAssertTrue(json.contains("\"app_id\":\"APP-1\""), json)
        XCTAssertTrue(json.contains("\"package_name\":\"com.publisher.app\""), json)
        XCTAssertTrue(json.contains("\"publisher_user_id\":\"user-42\""), json)
        XCTAssertTrue(json.contains("\"xifa\":\"xifa-uuid\""), json)
        XCTAssertTrue(json.contains("\"tcf_consent_string\":\"CO-tcf\""), json)
        XCTAssertTrue(json.contains("\"sdk_version\":\"0.1.0\""), json)
        XCTAssertTrue(json.contains("\"app_version\":\"1.2.3\""), json)
        XCTAssertTrue(json.contains("\"has_advertising_id\":true"), json)
        XCTAssertTrue(json.contains("\"aaid\":\"idfa-uuid\""), json)
        XCTAssertTrue(json.contains("\"custom_properties\":{\"tier\":\"gold\"}"), json)

        // Optional fields not set should be omitted
        XCTAssertFalse(json.contains("us_privacy_string"), json)
        XCTAssertFalse(json.contains("subject_to_gdpr"), json)
        XCTAssertFalse(json.contains("ab_test_override"), json)
    }

    func test_roundTrip() throws {
        let original = ConfigRequest(
            clientId: "X",
            xifa: "Y",
            platform: "ios",
            sdkVersion: "1.0",
            hasAdvertisingId: false,
            abTestOverride: AbTestOverridePayload(experimentId: "exp1", variantId: "B")
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ConfigRequest.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func test_abTestOverride_usesSnakeCase() throws {
        let payload = AbTestOverridePayload(experimentId: "exp1", variantId: "B")
        let data = try JSONEncoder().encode(payload)
        let json = String(data: data, encoding: .utf8) ?? ""

        XCTAssertTrue(json.contains("\"experiment_id\":\"exp1\""), json)
        XCTAssertTrue(json.contains("\"variant_id\":\"B\""), json)
    }
}
