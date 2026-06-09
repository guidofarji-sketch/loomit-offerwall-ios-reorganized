//
//  MockIdentifierStore.swift
//  LoomitOfferwallCoreTests
//

import Foundation
@testable import LoomitOfferwallCore

final class MockIdentifierStore: IdentifierStoring, @unchecked Sendable {

    var stubbedXifa: String = "test-xifa-0000-1111-2222"
    var stubbedIDFV: String? = "test-idfv-aaaa-bbbb"
    var stubbedBundleId: String? = "com.test.bundle"
    var stubbedFingerprint: String = String(repeating: "0", count: 64)

    func xifa() -> String { stubbedXifa }
    func idfv() -> String? { stubbedIDFV }
    func bundleIdentifier() -> String? { stubbedBundleId }
    func deviceFingerprint() -> String { stubbedFingerprint }
}
