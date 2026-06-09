//
//  PrivacyResolver.swift
//  LoomitOfferwallCore
//
//  Privacy consent resolver for GDPR/CCPA compliance.
//  Paridad con Android `PrivacyResolver.kt`.
//

import Foundation

/// Privacy state information from IAB standard signals.
public struct PrivacyState: Sendable {
    public let tcfConsentString: String?
    public let usPrivacyString: String?
    public let subjectToGdpr: Bool?
    /// CCPA opt-out inferido de la US-Privacy string (posición 2 == 'Y' → true, 'N' → false).
    /// Paridad con Android PrivacyResolver.
    public let ccpaOptOut: Bool?
    
    public init(
        tcfConsentString: String? = nil,
        usPrivacyString: String? = nil,
        subjectToGdpr: Bool? = nil,
        ccpaOptOut: Bool? = nil
    ) {
        self.tcfConsentString = tcfConsentString
        self.usPrivacyString = usPrivacyString
        self.subjectToGdpr = subjectToGdpr
        self.ccpaOptOut = ccpaOptOut
    }
}

/// Privacy resolver that reads IAB standard signals from the device if a CMP is installed.
/// 
/// Supported standards:
/// - IAB TCF v2: "IABTCF_TCString" (String) and "IABTCF_gdprApplies" (Int 0/1)
/// - IAB CCPA: "IABUSPrivacy_String" (String)
public enum PrivacyResolver {
    
    private static let keyTcfString = "IABTCF_TCString"
    private static let keyTcfGdprApplies = "IABTCF_gdprApplies"
    private static let keyUsPrivacy = "IABUSPrivacy_String"
    
    /// Resolve privacy state from device storage.
    ///
    /// Many CMPs write to the app's root UserDefaults. We use the standard UserDefaults
    /// which is equivalent to Android's MODE_PRIVATE SharedPreferences.
    public static func resolve() -> PrivacyState {
        let defaults = UserDefaultsSafe.shared

        let tcf = defaults.string(forKey: keyTcfString)
        let us = defaults.string(forKey: keyUsPrivacy)

        let subjectToGdpr: Bool?
        if defaults.object(forKey: keyTcfGdprApplies) != nil {
            let gdprAppliesInt = defaults.integer(forKey: keyTcfGdprApplies)
            subjectToGdpr = switch gdprAppliesInt {
            case 0: false
            case 1: true
            default: nil
            }
        } else {
            subjectToGdpr = nil
        }

        // Inferir ccpaOptOut de IAB US-Privacy string (posición 2: 'Y'=optOut, 'N'=no optOut).
        // Spec: https://github.com/InteractiveAdvertisingBureau/USPrivacy/blob/master/CCPA/US%20Privacy%20String.md
        let ccpaOptOut: Bool?
        if let usStr = us?.nilIfEmpty, usStr.count >= 3 {
            let idx = usStr.index(usStr.startIndex, offsetBy: 2)
            switch usStr[idx] {
            case "Y": ccpaOptOut = true
            case "N": ccpaOptOut = false
            default:  ccpaOptOut = nil
            }
        } else {
            ccpaOptOut = nil
        }

        return PrivacyState(
            tcfConsentString: tcf?.nilIfEmpty,
            usPrivacyString: us?.nilIfEmpty,
            subjectToGdpr: subjectToGdpr,
            ccpaOptOut: ccpaOptOut
        )
    }
    
    /// Check if GDPR applies based on device locale and carrier info.
    /// 
    /// This is a fallback method when CMP signals are not available.
    /// Returns true for EU/EEA countries, false otherwise, nil if uncertain.
    public static func inferGdprApplicability() -> Bool? {
        let regionCode = Locale.current.regionCode?.uppercased()
        
        // EU/EEA countries
        let euCountries: Set<String> = [
            "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR",
            "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL",
            "PL", "PT", "RO", "SK", "SI", "ES", "SE"
        ]
        
        // UK (post-Brexit still has similar requirements)
        let ukCountries: Set<String> = ["GB", "UK"]
        
        guard let country = regionCode else {
            return nil // Cannot determine
        }
        
        if euCountries.contains(country) || ukCountries.contains(country) {
            return true
        }
        
        // Some non-EU European countries may have GDPR-like requirements
        let europeanCountries: Set<String> = ["CH", "NO", "IS", "LI", "AD", "MC", "SM", "VA"]
        if europeanCountries.contains(country) {
            return true
        }
        
        return false
    }
    
    /// Get ATT (App Tracking Transparency) status on iOS 14+.
    /// 
    /// This is iOS-specific and complements the IAB standards.
    public static func getAttStatus() -> AttStatus {
        guard #available(iOS 14, *) else {
            return .notSupported // iOS 13 and below don't have ATT
        }
        
        switch ATTrackingManager.trackingAuthorizationStatus {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .unknown
        }
    }
}

/// App Tracking Transparency status.
public enum AttStatus: String, Sendable {
    case notSupported = "not_supported"
    case notDetermined = "not_determined"
    case restricted = "restricted"
    case denied = "denied"
    case authorized = "authorized"
    case unknown = "unknown"
}

// MARK: - String Extension

private extension String {
    var nilIfEmpty: String? {
        return self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

// MARK: - ATTrackingManager Import

// Import AppTrackingTransparency framework for iOS 14+
#if canImport(AppTrackingTransparency)
import AppTrackingTransparency
#endif
