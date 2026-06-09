//
//  MyChipsConfig.swift
//  LoomitOfferwallAdapterMyChips
//
//  Parsing tipado de la configuración que el backend manda en
//  `credentials` + `settings` para MyChips/MAF. Paridad con Android `MyChipsBlock`.
//

import Foundation
import LoomitOfferwallAdapterAPI

/// Género del usuario (paridad con `MCGenderEnum` del SDK MyChips).
public enum MyChipsGender: String, Sendable, Equatable {
    case male
    case female
    case other
}

/// Configuración tipada del provider MyChips (alias: MAF).
///
/// Mapea el subconjunto de `MCOfferwallSDK` que el adapter aplica durante
/// `initialize`. Source: <https://docs.mychips.io/ios/install-sdk>.
public struct MyChipsConfig: Sendable, Equatable {

    /// API key de MyChips. **Required.** Obtenida en
    /// <https://dashboard.maf.ad>.
    public let apiKey: String

    /// Ad unit ID. **Required** para `MCWebViewController(adunitId:)` y `getReward`.
    public let adUnitId: String

    /// Título opcional del toolbar del offerwall.
    public let title: String?

    /// Edad del usuario (0–100). Mejora targeting/analytics.
    public let age: Int?

    /// Género del usuario.
    public let gender: MyChipsGender?

    /// Sub-affiliate IDs para tracking custom (1..5).
    public let affSub1: String?
    public let affSub2: String?
    public let affSub3: String?
    public let affSub4: String?
    public let affSub5: String?

    public init(
        apiKey: String,
        adUnitId: String,
        title: String? = nil,
        age: Int? = nil,
        gender: MyChipsGender? = nil,
        affSub1: String? = nil,
        affSub2: String? = nil,
        affSub3: String? = nil,
        affSub4: String? = nil,
        affSub5: String? = nil
    ) {
        self.apiKey = apiKey
        self.adUnitId = adUnitId
        self.title = title
        self.age = age
        self.gender = gender
        self.affSub1 = affSub1
        self.affSub2 = affSub2
        self.affSub3 = affSub3
        self.affSub4 = affSub4
        self.affSub5 = affSub5
    }

    // MARK: - Parsing

    /// Construye el config desde un `ProviderConfig`. Acepta los aliases que
    /// el backend puede usar (`api_key` vs `apiKey`, `ad_unit_id` vs `adUnitId`).
    /// Retorna `.failure` si faltan campos obligatorios.
    public static func parse(from providerConfig: ProviderConfig) -> Result<MyChipsConfig, OfferwallError> {
        // Mergeamos credentials y settings — backend a veces los pone en uno u otro.
        let merged = providerConfig.credentials.merging(providerConfig.settings) { lhs, _ in lhs }

        let apiKey = lookup(["api_key", "apiKey"], in: merged) ?? ""
        guard !apiKey.isEmpty else {
            return .failure(.invalidConfiguration(reason: "MyChips api_key is required"))
        }

        let adUnitId = lookup(["ad_unit_id", "adUnitId"], in: merged)
            ?? providerConfig.settings["placement_id"]
            ?? ""
        guard !adUnitId.isEmpty else {
            return .failure(.invalidConfiguration(reason: "MyChips ad_unit_id is required"))
        }

        // Age (0..100) — opcional, ignorado si no parsea o sale de rango.
        let age: Int? = {
            guard let raw = lookup(["age"], in: merged), let n = Int(raw),
                  (0...100).contains(n) else { return nil }
            return n
        }()

        // Gender — opcional, normalizado.
        let gender: MyChipsGender? = {
            guard let raw = lookup(["gender"], in: merged)?.lowercased() else { return nil }
            return MyChipsGender(rawValue: raw)
        }()

        return .success(MyChipsConfig(
            apiKey: apiKey,
            adUnitId: adUnitId,
            title: lookup(["title"], in: merged),
            age: age,
            gender: gender,
            affSub1: lookup(["aff_sub1", "affSub1"], in: merged),
            affSub2: lookup(["aff_sub2", "affSub2"], in: merged),
            affSub3: lookup(["aff_sub3", "affSub3"], in: merged),
            affSub4: lookup(["aff_sub4", "affSub4"], in: merged),
            affSub5: lookup(["aff_sub5", "affSub5"], in: merged)
        ))
    }

    private static func lookup(_ keys: [String], in dict: [String: String]) -> String? {
        for key in keys {
            if let value = dict[key], !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
