//
//  MyChipsAdapter.swift
//  LoomitOfferwallAdapterMyChips
//
//  Factory descriptor que el publisher registra en `OfferwallSdk`.
//
//  Uso típico:
//
//  ```swift
//  Task {
//      await OfferwallSdk.shared.registerAdapter(MyChipsAdapter())
//  }
//  ```
//
//  Para reward S2S no se necesita nada más. Para Self-Managed Currency, el
//  publisher debe pasar un `MyChipsRewardListener`:
//
//  ```swift
//  let adapter = MyChipsAdapter(rewardListener: self)
//  ```
//

import Foundation
import LoomitOfferwallAdapterAPI

public final class MyChipsAdapter: OfferwallAdapter, @unchecked Sendable {

    public let providerName: String = "MyChips"

    /// Backend usa `mychips`; mantenemos `maf` como alias (paridad con Android).
    public let supportedKeys: [String] = ["mychips", "maf"]

    /// Factory inyectable. Default produce `LiveMyChipsSDKBridge`.
    private let bridgeFactory: @MainActor () -> MyChipsSDKBridge

    /// Reward listener opcional (Self-Managed Currency mode).
    private weak var rewardListener: MyChipsRewardListener?

    /// Override global factory para testing (permite inyectar mock bridge sin crear adapter nuevo)
    @MainActor
    public static var overrideBridgeFactory: (@MainActor () -> MyChipsSDKBridge)?

    public convenience init(rewardListener: MyChipsRewardListener? = nil) {
        self.init(
            bridgeFactory: { LiveMyChipsSDKBridge() },
            rewardListener: rewardListener
        )
    }

    /// Init para tests. Permite inyectar un bridge mock.
    public init(
        bridgeFactory: @escaping @MainActor () -> MyChipsSDKBridge,
        rewardListener: MyChipsRewardListener? = nil
    ) {
        self.bridgeFactory = bridgeFactory
        self.rewardListener = rewardListener
    }

    @MainActor
    public func createProvider() -> OfferwallProvider {
        // Usar override factory si existe (para testing), sino la local
        let factory = Self.overrideBridgeFactory ?? bridgeFactory
        return MyChipsProvider(
            bridge: factory(),
            rewardListener: rewardListener
        )
    }
}
