//
//  DeviceInfo.swift
//  LoomitOfferwallCore
//
//  Helpers para obtener metadata del dispositivo (modelo, OS) en iOS.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum DeviceInfo {

    /// Modelo del device (ej: "iPhone16,1"). En simulator retorna "Simulator/<model>".
    static var model: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { id, element in
            guard let value = element.value as? Int8, value != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(value)))
        }
        return identifier.isEmpty ? "unknown" : identifier
    }

    /// Versión del OS (ej: "17.4.1").
    static var osVersion: String {
        #if canImport(UIKit)
        return UIDevice.current.systemVersion
        #else
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #endif
    }
}
