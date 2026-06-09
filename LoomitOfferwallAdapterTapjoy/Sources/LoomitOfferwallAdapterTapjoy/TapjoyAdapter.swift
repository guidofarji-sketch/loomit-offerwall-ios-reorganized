//
//  TapjoyAdapter.swift
//  LoomitOfferwallAdapterTapjoy
//
//  Factory descriptor que el publisher registra en `OfferwallSdk`.
//
//  Uso típico:
//
//  ```swift
//  Task {
//      await OfferwallSdk.shared.registerAdapter(TapjoyAdapter())
//  }
//  ```
//

import Foundation
import LoomitOfferwallAdapterAPI

public final class TapjoyAdapter: OfferwallAdapter, @unchecked Sendable {

    public let providerName: String = "Tapjoy"

    /// Backend usa `tapjoy`; mantenemos `unity` como alias (paridad con Android).
    public let supportedKeys: [String] = ["tapjoy", "unity"]

    /// Factory inyectable. Default produce `LiveTapjoySDKBridge`.
    private let bridgeFactory: @MainActor () -> TapjoySDKBridge

    /// Override global factory para testing (permite inyectar mock bridge sin crear adapter nuevo)
    @MainActor
    public static var overrideBridgeFactory: (@MainActor () -> TapjoySDKBridge)?

    public convenience init() {
        self.init(
            bridgeFactory: { LiveTapjoySDKBridge() }
        )
    }

    /// Init para tests. Permite inyectar un bridge mock.
    public init(
        bridgeFactory: @escaping @MainActor () -> TapjoySDKBridge
    ) {
        self.bridgeFactory = bridgeFactory
    }

    @MainActor
    public func createProvider() -> OfferwallProvider {
        // Usar override factory si existe (para testing), sino la local
        let factory = Self.overrideBridgeFactory ?? bridgeFactory
        return TapjoyProvider(bridge: factory())
    }
}
