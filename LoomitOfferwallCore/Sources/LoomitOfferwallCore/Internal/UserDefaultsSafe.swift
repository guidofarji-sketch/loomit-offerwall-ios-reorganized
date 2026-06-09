//
//  UserDefaultsSafe.swift
//  LoomitOfferwallCore
//
//  Thread-safe wrapper for UserDefaults.
//  UserDefaults internally uses CFPrefsSearchListSource which is not thread-safe.
//  Even with a serial queue, concurrent access from different threads can crash.
//  The ONLY reliable solution is to use the main thread for all UserDefaults access.
//
// IMPORTANT: Use the shared instance to ensure all UserDefaults operations across the SDK
// use the main thread. Multiple instances with separate queues can still cause crashes.
//

import Foundation

/// Thread-safe wrapper for UserDefaults.
/// All read/write operations are forced to run on the main thread.
public final class UserDefaultsSafe {

    private let defaults: UserDefaults

    /// Shared instance that forces all operations to the main thread.
    /// Use this to prevent crashes from concurrent access across multiple instances.
    public static let shared = UserDefaultsSafe()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - String

    public func string(forKey key: String) -> String? {
        if Thread.isMainThread {
            return defaults.string(forKey: key)
        }
        return DispatchQueue.main.sync { defaults.string(forKey: key) }
    }

    public func set(_ value: String?, forKey key: String) {
        if Thread.isMainThread {
            defaults.set(value, forKey: key)
        } else {
            DispatchQueue.main.async { self.defaults.set(value, forKey: key) }
        }
    }

    // MARK: - Data

    public func data(forKey key: String) -> Data? {
        if Thread.isMainThread {
            return defaults.data(forKey: key)
        }
        return DispatchQueue.main.sync { defaults.data(forKey: key) }
    }

    public func set(_ value: Data?, forKey key: String) {
        if Thread.isMainThread {
            defaults.set(value, forKey: key)
        } else {
            DispatchQueue.main.async { self.defaults.set(value, forKey: key) }
        }
    }

    // MARK: - Dictionary

    public func dictionary(forKey key: String) -> [String: Any]? {
        if Thread.isMainThread {
            return defaults.dictionary(forKey: key)
        }
        return DispatchQueue.main.sync { defaults.dictionary(forKey: key) }
    }

    // MARK: - Object

    public func object(forKey key: String) -> Any? {
        if Thread.isMainThread {
            return defaults.object(forKey: key)
        }
        return DispatchQueue.main.sync { defaults.object(forKey: key) }
    }

    // MARK: - Integer

    public func integer(forKey key: String) -> Int {
        if Thread.isMainThread {
            return defaults.integer(forKey: key)
        }
        return DispatchQueue.main.sync { defaults.integer(forKey: key) }
    }

    // MARK: - Remove

    public func removeObject(forKey key: String) {
        if Thread.isMainThread {
            defaults.removeObject(forKey: key)
        } else {
            DispatchQueue.main.async { self.defaults.removeObject(forKey: key) }
        }
    }

    // MARK: - Any (for dictionaries)

    public func set(_ value: Any?, forKey key: String) {
        if Thread.isMainThread {
            defaults.set(value, forKey: key)
        } else {
            DispatchQueue.main.async { self.defaults.set(value, forKey: key) }
        }
    }
}
