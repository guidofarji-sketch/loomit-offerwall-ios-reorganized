//
//  CustomPropertiesStore.swift
//  LoomitOfferwallSampleApp
//
//  Persists publisher-set custom properties to UserDefaults (JSON array).
//  Paridad con Android CustomPropertiesStore.kt.
//

import Foundation
import LoomitOfferwallCore

enum CustomPropertiesStore {
    private static let udKey = "offerwall_custom_properties_entries"

    struct Entry: Codable, Equatable {
        var key: String
        var value: String
    }

    static func load() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: udKey),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return entries.filter { !$0.key.isEmpty && !$0.value.isEmpty }
    }

    /// Persists `entries` and syncs the SDK: removes deleted keys, sets new/updated ones.
    static func save(_ entries: [Entry]) async {
        let previous = load()
        let sanitized = entries.filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty &&
                                         !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        if let data = try? JSONEncoder().encode(sanitized) {
            UserDefaults.standard.set(data, forKey: udKey)
        }
        let previousKeys = Set(previous.map { $0.key })
        let newKeys = Set(sanitized.map { $0.key })
        let removedKeys = previousKeys.subtracting(newKeys)
        for key in removedKeys {
            await OfferwallSdk.shared.removeCustomProperty(key)
        }
        for entry in sanitized {
            await OfferwallSdk.shared.setCustomProperty(entry.key, value: entry.value)
        }
    }

    /// Reapplies stored properties to the SDK (call on app start and on view appear).
    /// Paridad con Android `applySavedProperties(context)`.
    static func applySavedProperties() async {
        let entries = load()
        for entry in entries {
            await OfferwallSdk.shared.setCustomProperty(entry.key, value: entry.value)
        }
    }
}
