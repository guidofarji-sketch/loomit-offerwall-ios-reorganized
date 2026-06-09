//
//  JSONValueTests.swift
//  LoomitOfferwallCoreTests
//

import XCTest
@testable import LoomitOfferwallCore

final class JSONValueTests: XCTestCase {

    // MARK: - Decoding

    func test_decode_primitives() throws {
        XCTAssertEqual(try decode("null"),   .null)
        XCTAssertEqual(try decode("true"),   .bool(true))
        XCTAssertEqual(try decode("false"),  .bool(false))
        XCTAssertEqual(try decode("42"),     .int(42))
        XCTAssertEqual(try decode("-7"),     .int(-7))
        XCTAssertEqual(try decode("3.14"),   .double(3.14))
        XCTAssertEqual(try decode("\"hi\""), .string("hi"))
    }

    func test_decode_int_preservesPrecision() throws {
        // Timestamp en ms = 1_704_067_200_000. Si decoder eligiera Double primero,
        // perderíamos precisión a partir de 2^53. Verificamos int-first.
        let value = try decode("1704067200000")
        XCTAssertEqual(value, .int(1_704_067_200_000))
    }

    func test_decode_array_mixedTypes() throws {
        let value = try decode(#"[1, "two", true, null, 3.14]"#)
        XCTAssertEqual(value, .array([
            .int(1),
            .string("two"),
            .bool(true),
            .null,
            .double(3.14)
        ]))
    }

    func test_decode_nestedObject() throws {
        let json = """
        {
            "credentials": {
                "sdk_key": "abc123",
                "test_mode": true,
                "fallback_urls": ["https://a", "https://b"]
            }
        }
        """
        let value = try decode(json)
        guard case .object(let outer) = value else {
            XCTFail("Expected object"); return
        }
        guard case .object(let creds) = outer["credentials"] else {
            XCTFail("Expected credentials object"); return
        }
        XCTAssertEqual(creds["sdk_key"], .string("abc123"))
        XCTAssertEqual(creds["test_mode"], .bool(true))
        XCTAssertEqual(creds["fallback_urls"], .array([.string("https://a"), .string("https://b")]))
    }

    // MARK: - Encoding round-trip

    func test_encode_roundTrip() throws {
        let original: JSONValue = [
            "id": 42,
            "name": "tapjoy",
            "active": true,
            "rate": 0.5,
            "tags": ["a", "b"],
            "meta": ["nested": nil]
        ]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Accessors (no coercion)

    func test_stringValue_onlyExactMatch() {
        XCTAssertEqual(JSONValue.string("hi").stringValue, "hi")
        XCTAssertNil(JSONValue.int(42).stringValue)
        XCTAssertNil(JSONValue.bool(true).stringValue)
    }

    func test_intValue_acceptsWholeDoubles() {
        XCTAssertEqual(JSONValue.int(42).intValue, 42)
        XCTAssertEqual(JSONValue.double(42.0).intValue, 42)
        XCTAssertNil(JSONValue.double(42.5).intValue)
        XCTAssertNil(JSONValue.string("42").intValue)
    }

    func test_doubleValue_acceptsBothNumbers() {
        XCTAssertEqual(JSONValue.int(42).doubleValue, 42.0)
        XCTAssertEqual(JSONValue.double(3.14).doubleValue, 3.14)
        XCTAssertNil(JSONValue.string("3.14").doubleValue)
    }

    func test_isNull() {
        XCTAssertTrue(JSONValue.null.isNull)
        XCTAssertFalse(JSONValue.string("").isNull)
        XCTAssertFalse(JSONValue.int(0).isNull)
        XCTAssertFalse(JSONValue.bool(false).isNull)
    }

    // MARK: - Coercion (explicit)

    func test_coerceToString() {
        XCTAssertEqual(JSONValue.string("hi").coerceToString(), "hi")
        XCTAssertEqual(JSONValue.int(42).coerceToString(), "42")
        XCTAssertEqual(JSONValue.bool(true).coerceToString(), "true")
        XCTAssertEqual(JSONValue.bool(false).coerceToString(), "false")
        XCTAssertNil(JSONValue.null.coerceToString())
        XCTAssertNil(JSONValue.array([]).coerceToString())
    }

    func test_coerceToBool_acceptsCommonStrings() {
        XCTAssertEqual(JSONValue.bool(true).coerceToBool(), true)
        XCTAssertEqual(JSONValue.int(1).coerceToBool(), true)
        XCTAssertEqual(JSONValue.int(0).coerceToBool(), false)
        XCTAssertEqual(JSONValue.string("true").coerceToBool(), true)
        XCTAssertEqual(JSONValue.string("FALSE").coerceToBool(), false)
        XCTAssertEqual(JSONValue.string("1").coerceToBool(), true)
        XCTAssertEqual(JSONValue.string("yes").coerceToBool(), true)
        XCTAssertEqual(JSONValue.string("No").coerceToBool(), false)
        XCTAssertNil(JSONValue.string("maybe").coerceToBool())
        XCTAssertNil(JSONValue.null.coerceToBool())
    }

    // MARK: - Literals (ergonomics)

    func test_literals() {
        let value: JSONValue = [
            "n": nil,
            "b": true,
            "i": 42,
            "d": 3.14,
            "s": "hi",
            "a": [1, 2, 3]
        ]
        guard case .object(let dict) = value else { XCTFail(); return }
        XCTAssertEqual(dict["n"], .null)
        XCTAssertEqual(dict["b"], .bool(true))
        XCTAssertEqual(dict["i"], .int(42))
        XCTAssertEqual(dict["d"], .double(3.14))
        XCTAssertEqual(dict["s"], .string("hi"))
        XCTAssertEqual(dict["a"], .array([.int(1), .int(2), .int(3)]))
    }

    // MARK: - Hashable

    func test_hashable_canBeUsedInSet() {
        let set: Set<JSONValue> = [.int(1), .int(1), .string("x")]
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - Helpers

    private func decode(_ json: String) throws -> JSONValue {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}
