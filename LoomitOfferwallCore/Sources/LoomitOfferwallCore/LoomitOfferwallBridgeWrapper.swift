//
//  LoomitOfferwallBridgeWrapper.swift
//  LoomitOfferwallCore
//
//  @objc wrapper class for Unity iOS bridge.
//
//  This class lives INSIDE the SDK pod and exposes synchronous @objc methods
//  that wrap the async OfferwallSdk actor. It also implements OfferwallListener
//  to forward callbacks to Unity via UnitySendMessage.
//
//  Architecture: C# → C functions (.m) → @objc methods (this class) → OfferwallSdk (actor)
//

import Foundation
import LoomitOfferwallAdapterAPI
#if canImport(UIKit)
import UIKit
#endif

/// @objc wrapper that bridges Unity ↔ OfferwallSdk actor.
/// Lives INSIDE the SDK pod so it links against the SDK at build time.
@objc public class LoomitOfferwallBridgeWrapper: NSObject {

    @objc public static let shared = LoomitOfferwallBridgeWrapper()

    private var sdk: OfferwallSdk {
        return OfferwallSdk.shared
    }
    private var unityGameObject: String = "LoomitOfferwallManager"
    private var isSdkInitialized: Bool = false
    private var cachedUserId: String?
    private var cachedXifa: String = ""
    private var preRegisteredAdapters: [any OfferwallAdapter] = []

    /// Pre-register adapters before initialize() is called.
    /// When any adapters are pre-registered, NSClassFromString discovery is skipped.
    public func addAdapter(_ adapter: any OfferwallAdapter) {
        preRegisteredAdapters.append(adapter)
    }

    // MARK: - Unity Callbacks (NSNotificationCenter decoupling)
    // The wrapper lives inside the LoomitOfferwall pod and cannot link against
    // UnityFramework symbols (UnitySendMessage / UnityGetGLViewController).
    // Callbacks are broadcast as notifications; the ObjC bridge in UnityFramework
    // observes them and forwards to Unity via UnitySendMessage.

    private static let unityCallbackNotification = Notification.Name("LoomitUnityCallback")

    private func sendToUnity(_ method: String, _ message: String) {
        NotificationCenter.default.post(
            name: Self.unityCallbackNotification,
            object: nil,
            userInfo: [
                "gameObject": unityGameObject,
                "method": method,
                "message": message
            ]
        )
    }

    // MARK: - View Controller Helpers

    private func getTopmostViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return nil
        }
        guard let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first else {
            return nil
        }

        var topVC = window.rootViewController
        while let presentedVC = topVC?.presentedViewController {
            if presentedVC.view == nil || presentedVC.isBeingDismissed {
                break
            }
            topVC = presentedVC
        }

        return topVC
    }

    // MARK: - API Key Resolution

    private func resolveApiKey() -> String? {
        return Bundle.main.object(forInfoDictionaryKey: "LoomitApiKey") as? String
    }

    // MARK: - Public API: Initialization

    @objc public func initialize(gameObject: String, clientId: String, userId: String?, appId: String?) {
        unityGameObject = gameObject.isEmpty ? "LoomitOfferwallManager" : gameObject

        print("[LoomitBridgeWrapper] initialize(gameObject=\(gameObject), clientId=\(clientId))")

        Task {
            // Guard: Skip duplicate initialization
            if self.isSdkInitialized {
                print("[LoomitBridgeWrapper] SDK already initialized (guard preventing duplicate init)")
                await self.sdk.setListener(self)
                return
            }

            if let apiKey = self.resolveApiKey(), !apiKey.isEmpty {
                await self.sdk.setLoomitApiKey(apiKey)
            } else {
                print("[LoomitBridgeWrapper] WARNING: No LoomitApiKey found in Info.plist")
            }

            if !clientId.isEmpty { await self.sdk.setClientId(clientId) }
            if let appId = appId, !appId.isEmpty { await self.sdk.setAppId(appId) }
            if let userId = userId, !userId.isEmpty { await self.sdk.setPublisherUserId(userId) }

            await self.sdk.setListener(self)

            // Register adapters dynamically (pods may or may not be present)
            await self.registerAvailableAdapters()

            // Cache synchronous values so getters don't block Unity's main thread

            self.cachedUserId = await self.sdk.getPublisherUserId()
            self.cachedXifa = await self.sdk.xifa()

            self.isSdkInitialized = true
        }
    }


    /// Registers adapters. Uses pre-registered adapters (injected from LoomitUnityBridge
    /// which has compile-time access) when available. Falls back to NSClassFromString
    /// for CocoaPods integrations where adapters are linked dynamically.
    private func registerAvailableAdapters() async {
        if !preRegisteredAdapters.isEmpty {
            for adapter in preRegisteredAdapters {
                await self.sdk.registerAdapter(adapter)
                print("[LoomitBridgeWrapper] Registered adapter: \(adapter.providerName)")
            }
            return
        }
        let adapterClasses = [
            "LoomitOfferwallAdapterTapjoy.TapjoyAdapter",
            "LoomitOfferwallAdapterMyChips.MyChipsAdapter"
        ]
        for className in adapterClasses {
            if let adapterClass = NSClassFromString(className) as? NSObject.Type {
                let instance = adapterClass.init()
                if let adapter = instance as? OfferwallAdapter {
                    await self.sdk.registerAdapter(adapter)
                    print("[LoomitBridgeWrapper] Registered adapter: \(className)")
                } else {
                    print("[LoomitBridgeWrapper] WARNING: \(className) does not conform to OfferwallAdapter")
                }
            } else {
                print("[LoomitBridgeWrapper] Adapter not linked: \(className)")
            }
        }
    }

    // MARK: - Public API: User Management

    @objc public func setUserId(_ userId: String?) {
        Task {
            await self.sdk.setPublisherUserId(userId)
            self.cachedUserId = userId
        }
    }

    @objc public func clearUserId() {
        Task {
            await self.sdk.clearPublisherUserId()
            self.cachedUserId = nil
        }
    }

    @objc public func getUserId() -> String? {
        // Return cached value — synchronous, no blocking.
        return self.cachedUserId
    }

    @objc public func getXifa() -> String {
        // Return cached value — synchronous, no blocking.
        return self.cachedXifa
    }

    // MARK: - Public API: Show/Close

    @objc public func show() {
        Task {
            guard let vc = self.getTopmostViewController() else {
                print("[LoomitBridgeWrapper] ERROR: No ViewController available for show()")
                self.sendToUnity("OnOfferwallShowFailed", "No ViewController")
                return
            }
            await self.sdk.show(from: vc)
        }
    }

    @objc(showWithProviderAndAdSpace:adSpace:)
    public func showWithProviderAndAdSpace(providerOverride: String?, adSpace: String?) {
        let provider = providerOverride?.isEmpty == true ? nil : providerOverride
        let space = adSpace?.isEmpty == true ? nil : adSpace

        print("[LoomitBridgeWrapper] showWithProviderAndAdSpace: USER REQUEST")

        Task {
            guard let vc = self.getTopmostViewController() else {
                self.sendToUnity("OnOfferwallShowFailed", "No ViewController")
                return
            }
            await self.sdk.show(from: vc, providerOverride: provider, adSpace: space)
        }
    }

    @objc public func close() {
        Task { await self.sdk.close() }
    }

    @objc public func failoverToNext() {
        Task {
            guard let vc = self.getTopmostViewController() else {
                self.sendToUnity("OnOfferwallShowFailed", "Failover failed: No ViewController")
                return
            }
            _ = await self.sdk.failoverToNext(from: vc, adSpace: nil)
        }
    }

    // MARK: - Public API: Availability

    @objc public func hasAvailableOfferwall() -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var result = false
        Task.detached {
            result = await self.sdk.hasAvailableOfferwall()
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    @objc public func getActiveProviderName() -> String? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: String?
        Task.detached {
            result = await self.sdk.getActiveProviderName()
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    @objc public func getAvailableProviders() -> String {
        let semaphore = DispatchSemaphore(value: 0)
        var result: [String] = []
        Task.detached {
            result = await self.sdk.getAvailableProviders()
            semaphore.signal()
        }
        semaphore.wait()
        let jsonArray = try? JSONEncoder().encode(result)
        return String(data: jsonArray ?? Data(), encoding: .utf8) ?? "[]"
    }

    // MARK: - Public API: Config

    @objc public func fetchConfig() {
        print("[LoomitBridgeWrapper] fetchConfig: USER REQUEST")
        Task {
            do {
                _ = try await self.sdk.fetchConfig()
                print("[LoomitBridgeWrapper] fetchConfig: SUCCESS")
            } catch {
                print("[LoomitBridgeWrapper] fetchConfig: FAILED - \(error.localizedDescription)")
                self.sendToUnity("OnConfigFetchFailed", "fetchConfig failed: \(error.localizedDescription)")
            }
        }
    }

    @objc public func initializeProviders() {
        print("[LoomitBridgeWrapper] initializeProviders: USER REQUEST")
        Task {
            await self.sdk.initAllFromPlan()
            print("[LoomitBridgeWrapper] initializeProviders: COMPLETED")
        }
    }

    @objc public func getLastSegmentName() -> String? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: String?
        Task.detached {
            result = await self.sdk.getLastSegmentName()
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    @objc public func hasActiveExperiments() -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var result = false
        Task.detached {
            result = await self.sdk.hasActiveExperiments()
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    @objc public func getLastExperimentAssignments() -> String {
        let semaphore = DispatchSemaphore(value: 0)
        var result: [OfferwallSdk.ExperimentAssignment] = []
        Task.detached {
            result = await self.sdk.getLastExperimentAssignments()
            semaphore.signal()
        }
        semaphore.wait()
        let assignmentsArray = result.map { exp -> [String: Any] in
            var dict: [String: Any] = [
                "name": exp.name,
                "group": exp.group ?? "",
                "isActive": exp.isActive
            ]
            if !exp.rawPayload.isEmpty {
                dict["rawPayload"] = exp.rawPayload
            }
            return dict
        }
        if let data = try? JSONSerialization.data(withJSONObject: assignmentsArray),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        return "[]"
    }

    @objc public func getLastRawConfigResponse() -> String? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: String?
        Task.detached {
            result = await self.sdk.getLastRawConfigResponse()
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    @objc public func getProviderPlanJson() -> String {
        let semaphore = DispatchSemaphore(value: 0)
        var result: [ProviderPlanEntry] = []
        Task.detached {
            result = await self.sdk.getProviderPlan()
            semaphore.signal()
        }
        semaphore.wait()
        let planArray = result.map { entry -> [String: Any] in
            [
                "provider": entry.providerId,
                "placement": entry.placement ?? "",
                "credentials": entry.credentials.isEmpty ? "{}" : "[present]",
                "priority": entry.priority,
                "isActive": entry.isActive
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: planArray),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        return "[]"
    }

    @objc public func getLastConfigSource() -> String? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: String?
        Task.detached {
            result = await self.sdk.getLastConfigSource()
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    @objc public func getConfigRequestPreview(clientId: String, appId: String?) -> String {
        let semaphore = DispatchSemaphore(value: 0)
        var result: String = ""
        Task.detached {
            result = await self.sdk.getConfigRequestPreview(clientId: clientId, appId: appId?.isEmpty == true ? nil : appId)
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    // MARK: - Public API: Custom Properties

    @objc public func setCustomProperty(key: String, value: String?) {
        let sanitizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedKey.isEmpty else { return }
        let sanitizedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalValue = sanitizedValue?.isEmpty == true ? nil : sanitizedValue
        Task { await self.sdk.setCustomProperty(sanitizedKey, value: finalValue) }
    }

    @objc(removeCustomProperty:)
    public func removeCustomProperty(key: String) {
        Task { await self.sdk.removeCustomProperty(key) }
    }

    @objc public func clearCustomProperties() {
        Task { await self.sdk.clearCustomProperties() }
    }

    @objc(setCustomPropertiesFromJson:)
    public func setCustomPropertiesFromJson(json: String) {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return }
        Task { await self.sdk.setCustomProperties(dict) }
    }

    // MARK: - Public API: Privacy

    @objc public func setPrivacyOverrides(subjectToGdpr: Bool, gdprConsent: Bool, ccpaOptOut: Bool,
                                          tcfConsentString: String?, usPrivacyString: String?) {
        let tcf = tcfConsentString?.isEmpty == true ? nil : tcfConsentString
        let usPrivacy = usPrivacyString?.isEmpty == true ? nil : usPrivacyString
        Task {
            await self.sdk.setPrivacy(
                tcfConsentString: tcf,
                usPrivacyString: usPrivacy,
                subjectToGdpr: subjectToGdpr,
                gdprConsent: gdprConsent,
                ccpaOptOut: ccpaOptOut
            )
        }
    }

    // MARK: - Public API: Advertising

    @objc public func setAdvertisingId(_ advertisingId: String?) {
        let adId = advertisingId?.isEmpty == true ? nil : advertisingId
        Task { await self.sdk.setAdvertisingId(adId) }
    }

    @objc public func setHasAdvertisingId(_ has: Bool) {
        Task { await self.sdk.setHasAdvertisingId(has) }
    }

    // MARK: - Public API: Debug

    @objc public func setDebuggingEnabled(_ enabled: Bool) {
        Task { await self.sdk.setDebuggingEnabled(enabled) }
    }

    @objc public func isDebuggingEnabled() -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var result = false
        Task.detached {
            result = await self.sdk.isDebuggingEnabled()
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    @objc public func showDebugPanel() {
        // NO-OP: DebugPanel not available in SDK core
        print("[LoomitBridgeWrapper] showDebugPanel: not implemented in SDK core")
    }

    // MARK: - Public API: Environment

    @objc public func setEnvironment(_ envString: String) {
        print("[LoomitBridgeWrapper] setEnvironment(\(envString))")
        Task {
            let environment: BackendEnvironment
            switch envString.lowercased() {
            case "live", "production":
                environment = .live
            case "test", "staging":
                environment = .test
            default:
                if let url = URL(string: envString) {
                    environment = .custom(baseURL: url)
                } else {
                    print("[LoomitBridgeWrapper] WARNING: Invalid environment '\(envString)', defaulting to live")
                    environment = .live
                }
            }
            await self.sdk.setEnvironment(environment)
        }
    }

    // MARK: - Public API: Tracking

    @objc public func enableTracking() {
        // Tracking is enabled by default; no separate API needed on iOS
    }

    @objc public func disableTracking() {
        // Tracking opt-out handled via setPrivacy on iOS
    }
}

// MARK: - OfferwallListener

extension LoomitOfferwallBridgeWrapper: OfferwallListener {

    public func offerwallDidInitialize() {
        print("[LoomitBridgeWrapper] offerwallDidInitialize: Providers ready - sending to Unity")
        sendToUnity("OnOfferwallInitialized", "")
    }

    public func offerwall(didFailToInitialize reason: String) {
        print("[LoomitBridgeWrapper] offerwall(didFailToInitialize): \(reason)")
        sendToUnity("OnOfferwallInitializationFailed", reason)
    }

    public func offerwall(didReceiveConfig result: Result<ConfigResponse, OfferwallError>) {
        switch result {
        case .success(let config):
            if let json = try? String(data: JSONEncoder().encode(config), encoding: .utf8) {
                print("[LoomitBridgeWrapper] offerwall(didReceiveConfig): Config received")
                sendToUnity("OnConfigFetched", json)
            }
        case .failure(let error):
            print("[LoomitBridgeWrapper] offerwall(didReceiveConfig): Failed - \(error.localizedDescription)")
            sendToUnity("OnConfigFetchFailed", error.localizedDescription)
        }
    }

    public func offerwall(didChangeAvailability available: Bool) {
        sendToUnity("OnOfferwallAvailabilityChanged", available ? "true" : "false")
    }

    public func offerwall(didShow providerKey: String, adSpace: String?) {
        sendToUnity("OnOfferwallShow", providerKey)
    }

    public func offerwall(didFailToShow error: OfferwallError, adSpace: String?) {
        sendToUnity("OnOfferwallShowFailed", error.localizedDescription)
    }

    public func offerwall(didClose providerKey: String) {
        sendToUnity("OnOfferwallClose", providerKey)
    }

    public func offerwall(didEarnRewardAmount amount: Int, currency: String, providerKey: String) {
        let json = "{\"provider\":\"\(providerKey)\",\"currency\":\"\(currency)\",\"amount\":\(amount)}"
        sendToUnity("OnOfferwallRewardReceived", json)
    }
}
