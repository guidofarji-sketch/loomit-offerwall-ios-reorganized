//
//  LoomitUnityBridge.swift
//  LoomitUnityBridge
//
//  @objc wrapper class for Unity iOS bridge.
//  This is a DYNAMIC framework that wraps LoomitOfferwallCore for Unity distribution.
//  It re-exports the existing LoomitOfferwallBridgeWrapper via a clean @objc façade.
//
//  Architecture for Unity:
//  C# (DllImport) → C functions (.m) → @objc LoomitUnityBridge → LoomitOfferwallBridgeWrapper → OfferwallSdk
//

import Foundation
import LoomitOfferwallCore
import LoomitOfferwallAdapterAPI
import LoomitOfferwallAdapterTapjoy
import LoomitOfferwallAdapterMyChips
import LoomitOfferwallDebug
#if canImport(UIKit)
import UIKit
#endif

/// @objc wrapper that bridges Unity ↔ LoomitOfferwallCore.
/// Lives in a separate dynamic framework so it can be distributed as xcframework.
@objc public class LoomitUnityBridgeImpl: NSObject {

    @objc public static let shared = LoomitUnityBridgeImpl()

    private var wrapper: LoomitOfferwallBridgeWrapper {
        return LoomitOfferwallBridgeWrapper.shared
    }

    private var debugCollector: DebugDataCollector?

    // MARK: - Initialization

    @objc public func setupDebugPanel(debugEnabled: Bool) {
        Task { @MainActor in
            if self.debugCollector == nil {
                self.debugCollector = DebugDataCollector()
            }
            if let collector = self.debugCollector {
                DebugPanel.initialize(dataCollector: collector)
            }
            DebugPanel.setEnabled(debugEnabled)
        }
    }

    @objc public func initialize(gameObject: String, clientId: String, userId: String?, appId: String?) {
        wrapper.addAdapter(TapjoyAdapter())
        wrapper.addAdapter(MyChipsAdapter())
        setupDebugPanel(debugEnabled: wrapper.isDebuggingEnabled())
        wrapper.initialize(gameObject: gameObject, clientId: clientId, userId: userId, appId: appId)
    }

    // MARK: - User Management

    @objc public func setUserId(_ userId: String?) {
        wrapper.setUserId(userId)
    }

    @objc public func clearUserId() {
        wrapper.clearUserId()
    }

    @objc public func getUserId() -> String? {
        return wrapper.getUserId()
    }

    @objc public func getXifa() -> String {
        return wrapper.getXifa()
    }

    // MARK: - Show/Close

    @objc public func show() {
        wrapper.show()
    }

    @objc(showWithProviderAndAdSpace:adSpace:)
    public func showWithProviderAndAdSpace(providerOverride: String?, adSpace: String?) {
        wrapper.showWithProviderAndAdSpace(providerOverride: providerOverride, adSpace: adSpace)
    }

    @objc public func close() {
        wrapper.close()
    }

    @objc public func failoverToNext() {
        wrapper.failoverToNext()
    }

    // MARK: - Availability

    @objc public func hasAvailableOfferwall() -> Bool {
        return wrapper.hasAvailableOfferwall()
    }

    @objc public func getActiveProviderName() -> String? {
        return wrapper.getActiveProviderName()
    }

    @objc public func getAvailableProviders() -> String {
        return wrapper.getAvailableProviders()
    }

    // MARK: - Config

    @objc public func fetchConfig() {
        wrapper.fetchConfig()
    }

    @objc public func initializeProviders() {
        wrapper.initializeProviders()
    }

    @objc public func getLastSegmentName() -> String? {
        return wrapper.getLastSegmentName()
    }

    @objc public func hasActiveExperiments() -> Bool {
        return wrapper.hasActiveExperiments()
    }

    @objc public func getLastExperimentAssignments() -> String {
        return wrapper.getLastExperimentAssignments()
    }

    @objc public func getLastRawConfigResponse() -> String? {
        return wrapper.getLastRawConfigResponse()
    }

    @objc public func getProviderPlanJson() -> String {
        return wrapper.getProviderPlanJson()
    }

    @objc public func getLastConfigSource() -> String? {
        return wrapper.getLastConfigSource()
    }

    @objc public func getConfigRequestPreview(clientId: String, appId: String?) -> String {
        return wrapper.getConfigRequestPreview(clientId: clientId, appId: appId)
    }

    // MARK: - Custom Properties

    @objc public func setCustomProperty(key: String, value: String?) {
        wrapper.setCustomProperty(key: key, value: value)
    }

    @objc(removeCustomProperty:)
    public func removeCustomProperty(key: String) {
        wrapper.removeCustomProperty(key: key)
    }

    @objc public func clearCustomProperties() {
        wrapper.clearCustomProperties()
    }

    @objc(setCustomPropertiesFromJson:)
    public func setCustomPropertiesFromJson(json: String) {
        wrapper.setCustomPropertiesFromJson(json: json)
    }

    // MARK: - Privacy

    @objc public func setPrivacyOverrides(subjectToGdpr: Bool, gdprConsent: Bool, ccpaOptOut: Bool,
                                          tcfConsentString: String?, usPrivacyString: String?) {
        wrapper.setPrivacyOverrides(
            subjectToGdpr: subjectToGdpr,
            gdprConsent: gdprConsent,
            ccpaOptOut: ccpaOptOut,
            tcfConsentString: tcfConsentString,
            usPrivacyString: usPrivacyString
        )
    }

    // MARK: - Advertising

    @objc public func setAdvertisingId(_ advertisingId: String?) {
        wrapper.setAdvertisingId(advertisingId)
    }

    @objc public func setHasAdvertisingId(_ has: Bool) {
        wrapper.setHasAdvertisingId(has)
    }

    // MARK: - Debug

    @objc public func setDebuggingEnabled(_ enabled: Bool) {
        wrapper.setDebuggingEnabled(enabled)
        Task { @MainActor in DebugPanel.setEnabled(enabled) }
    }

    @objc public func isDebuggingEnabled() -> Bool {
        return wrapper.isDebuggingEnabled()
    }

    @objc public func handleShake() {
        Task { @MainActor in DebugPanel.handleShake() }
    }

    @objc public func showDebugPanel() {
        Task { @MainActor in
            DebugPanel.setEnabled(wrapper.isDebuggingEnabled())
            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
                  let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
                return
            }
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            DebugPanel.show(from: topVC)
        }
    }

    // MARK: - Environment

    @objc public func setEnvironment(_ envString: String) {
        wrapper.setEnvironment(envString)
    }

    // MARK: - Tracking

    @objc public func enableTracking() {
        wrapper.enableTracking()
    }

    @objc public func disableTracking() {
        wrapper.disableTracking()
    }
}
