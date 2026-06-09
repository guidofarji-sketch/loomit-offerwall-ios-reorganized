//
//  EventPriority.swift
//  LoomitOfferwallCore
//
//  Prioridad de eventos para retención en la cola. Paridad con Android.
//

import Foundation

public enum EventPriority: Int, Sendable, Codable, Comparable {

    /// init/config/rewarded — nunca dropear.
    case critical = 3

    /// show/dismiss/failover — dropear de último.
    case high = 2

    /// availability/diagnostics — dropear primero.
    case normal = 1

    public static func < (lhs: EventPriority, rhs: EventPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Determina la prioridad a partir del tipo de evento.
    /// Mismas reglas que Android.
    public static func from(eventType: String) -> EventPriority {
        switch eventType {
        case "init_provider_start", "init_provider_success", "init_provider_failed",
             "config_success", "config_error", "rewarded":
            return .critical

        case "content_show", "content_dismiss", "show_failed",
             "provider_failover", "provider_available":
            return .high

        default:
            return .normal
        }
    }
}
