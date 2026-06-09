//
//  TapjoySDKBridge.swift
//  LoomitOfferwallAdapterTapjoy
//
//  Capa fina sobre el SDK Tapjoy iOS.
//

import Foundation
import UIKit
import Tapjoy

/// Abstracción del SDK Tapjoy iOS.
@MainActor
public protocol TapjoySDKBridge: AnyObject {
    func setDebugEnabled(_ enabled: Bool)
    func connect(sdkKey: String, options: [String: Any]?)
}

/// Default impl que delega al SDK Tapjoy real.
@MainActor
public final class LiveTapjoySDKBridge: TapjoySDKBridge {
    public init() {}

    public func setDebugEnabled(_ enabled: Bool) {
        Tapjoy.loggingLevel = enabled ? .debug : .error
    }

    public func connect(sdkKey: String, options: [String: Any]?) {
        Tapjoy.connect(sdkKey, options: options)
    }
}
