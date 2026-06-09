//
//  MockUIKit.swift
//  LoomitOfferwallCoreTests
//
//  Mock UIKit for macOS testing environment.
//

import Foundation

#if !canImport(UIKit)

// Mock UIKit types for macOS testing
public typealias UIViewController = NSObject
public typealias UIView = NSObject
public typealias UIWindow = NSObject

#endif
