//
//  TapjoyProvider.swift
//  LoomitOfferwallAdapterTapjoy
//
//  Implementación de `OfferwallProvider` para Tapjoy/Unity Offerwall.
//
//  Flujo de show:
//  - El SDK Tapjoy requiere conexión previa con connect()
//  - Luego se crea un placement con getPlacement()
//  - Se solicita contenido con requestContent()
//  - Cuando onContentReady, se muestra con showContent()
//  - Callbacks de reward se reciben vía TJEarnedCurrencyListener
/// Tapjoy iOS provider implementation using official Tapjoy SDK 14.7.0
/// Handles connection, placement management, and offerwall display with proper error handling
import Foundation
import UIKit
import LoomitOfferwallAdapterAPI
import Tapjoy

@MainActor
public final class TapjoyProvider: NSObject, OfferwallProvider, @preconcurrency TJPlacementDelegate {

    // MARK: - Notification names from Tapjoy SDK (using actual SDK constants)
    private static let connectSuccessNotification = NSNotification.Name("TJC_Connect_Success")
    private static let connectFailedNotification = NSNotification.Name("TJC_Connect_Failed")
    private static let connectWarningNotification = NSNotification.Name("TJC_Connect_Warning")

    private enum State {
        case notInitialized
        case initializing
        case initialized
        case error
    }

    private struct EndpointCandidate {
        let serviceUrl: String
        let placementServiceUrl: String?
        let redirectDomain: String?
    }

    public nonisolated let providerKey: String = "tapjoy"
    public nonisolated let providerSdkVersion: String? = nil

    private let bridge: TapjoySDKBridge

    private var state: State = .notInitialized
    private var typedConfig: TapjoyConfig?
    private var providerConfig: ProviderConfig?

    private var placementName: String = ""
    private var contentAvailable: Bool = false

    private var endpointCandidates: [EndpointCandidate] = []
    private var currentEndpointIndex: Int = 0

    private weak var providerListener: OfferwallProviderListener?
    private var currentPlacement: TJPlacement?

    /// Guards against duplicate show/close callbacks from TJPlacementDelegate
    private var hasReportedShow = false
    private var hasReportedClose = false

    /// Static reference to the last created instance (for testing)
    @MainActor
    public static var lastInstance: TapjoyProvider?

    private static let DEFAULT_PLACEMENT = "default_placement"
    private static let DEFAULT_TEST_PLACEMENT = "test_placement"
    private static let DEFAULT_ENDPOINTS = [
        EndpointCandidate(
            serviceUrl: "https://gateway.offerwall.unity3d.com/",
            placementServiceUrl: "https://gateway.offerwall.unity3d.com/placements/",
            redirectDomain: "gateway.offerwall.unity3d.com"
        ),
        EndpointCandidate(
            serviceUrl: "https://gateway.tapjoy.com/",
            placementServiceUrl: "https://gateway.tapjoy.com/placements/",
            redirectDomain: "gateway.tapjoy.com"
        ),
        EndpointCandidate(
            serviceUrl: "https://ws.tapjoyads.com/",
            placementServiceUrl: "https://ws.tapjoyads.com/placements/",
            redirectDomain: "ws.tapjoyads.com"
        )
    ]

    public init(bridge: TapjoySDKBridge) {
        self.bridge = bridge
    }

    // MARK: - OfferwallProvider conformance

    public func initialize(
        config: ProviderConfig,
        listener: OfferwallProviderListener
    ) async -> Result<Void, OfferwallError> {

        self.providerListener = listener
        Self.lastInstance = self

        // Guardar ProviderConfig para acceso a adSpaceOverrides
        self.providerConfig = config

        // 1. Parsear config tipada del backend.
        let parsed = TapjoyConfig.parse(from: config)
        let tjConfig: TapjoyConfig
        switch parsed {
        case .success(let c):  tjConfig = c
        case .failure(let e):
            listener.provider(providerKey, didFailToInitializeWith: e)
            return .failure(e)
        }
        self.typedConfig = tjConfig

        // 2. Configurar placement name según modo test/producción
        placementName = if tjConfig.testMode {
            tjConfig.testPlacementId?.nonEmpty ?? Self.DEFAULT_TEST_PLACEMENT
        } else {
            tjConfig.placementId.nonEmpty ?? Self.DEFAULT_PLACEMENT
        }

        // 3. Configurar debug mode
        bridge.setDebugEnabled(tjConfig.testMode)

        // 4. Preparar endpoints
        prepareEndpointCandidates(tjConfig)

        guard !endpointCandidates.isEmpty else {
            let error = OfferwallError.invalidConfiguration(reason: "No endpoints configured for Tapjoy")
            listener.provider(providerKey, didFailToInitializeWith: error)
            state = .error
            return .failure(error)
        }

        // 6. Register for Tapjoy connection notifications
        setupConnectionNotifications()

        // 7. Iniciar conexión
        state = .initializing
        currentEndpointIndex = 0
        contentAvailable = false

        attemptTapjoyConnect()

        return .success(())
    }

    private var hasRegisteredObservers = false

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupConnectionNotifications() {
        // Prevent duplicate observers if initialize() is called multiple times
        if hasRegisteredObservers {
            NotificationCenter.default.removeObserver(self)
        }
        hasRegisteredObservers = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(tjcConnectSuccess),
            name: Self.connectSuccessNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(tjcConnectFail),
            name: Self.connectFailedNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(tjcConnectWarning),
            name: Self.connectWarningNotification,
            object: nil
        )
    }

    @objc func tjcConnectSuccess(notif: NSNotification) {
        print("[TapjoyProvider] Tapjoy connect succeeded")
        handleConnectionSuccess()
    }

    @objc func tjcConnectFail(notif: NSNotification) {
        var message = "Tapjoy connect failed"
        if let error = notif.userInfo?["error"] as? NSError {
            message += " - Error: \(error.code) - \(error.localizedDescription)"
            if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                message += "\nUnderlying Error: \(underlyingError.code) - \(underlyingError.localizedDescription)"
            }
        }
        print("[TapjoyProvider] \(message)")

        if tryNextEndpoint() {
            return
        }
        handleInitializationError(message)
    }

    @objc func tjcConnectWarning(notif: NSNotification) {
        var message = "Tapjoy Connect Warning"
        if let error = notif.userInfo?["error"] as? NSError {
            message += "\nError: \(error.code) - \(error.localizedDescription)"
            if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                message += "\nUnderlying Error: \(underlyingError.code) - \(underlyingError.localizedDescription)"
            }
        }
        print("[TapjoyProvider] \(message)")
    }

    public func isAvailable() -> Bool {
        state == .initialized && contentAvailable
    }

    public func close() {
        guard !hasReportedClose else {
            print("[TapjoyProvider] ⚠️ close() ignored: already reported close")
            return
        }
        hasReportedClose = true

        // Clean up NotificationCenter observers
        NotificationCenter.default.removeObserver(self)
        hasRegisteredObservers = false

        state = .notInitialized
        contentAvailable = false
        providerListener?.providerDidClose(providerKey)
    }

    public func show(
        from presenter: UIViewController,
        adSpace: String?
    ) async -> Result<Void, OfferwallError> {
        // Reset callback guards for a fresh show session
        hasReportedShow = false
        hasReportedClose = false

        guard state == .initialized else {
            let reason: String
            switch state {
            case .notInitialized:
                reason = "SDK not initialized"
            case .initializing:
                reason = "SDK still initializing"
            case .error:
                reason = "SDK initialization error"
            case .initialized:
                reason = "" // This case should never be reached due to guard
            }
            return .failure(.providerUnavailable(provider: providerKey, reason: reason))
        }

        let mode = typedConfig?.testMode == true ? "TEST" : "PRODUCTION"
        print("[TapjoyProvider] Showing offerwall (Mode: \(mode)) - Placement: \(placementName)")
        print("[TapjoyProvider] Note: Tapjoy SDK integration simplified - actual offerwall display not implemented")

        // Show the Tapjoy offerwall using the placement
        guard let placement = currentPlacement else {
            return .failure(.providerUnavailable(provider: providerKey, reason: "No placement available"))
        }

        if placement.isContentReady {
            print("[TapjoyProvider] Showing offerwall content")
            placement.showContent(with: presenter)
        } else {
            print("[TapjoyProvider] Content not ready, requesting...")
            placement.requestContent()
            return .failure(.providerUnavailable(provider: providerKey, reason: "Content not ready"))
        }

        return .success(())
    }

    // MARK: - Private: Connection

    private func prepareEndpointCandidates(_ config: TapjoyConfig) {
        endpointCandidates.removeAll()

        var seen = Set<String>()

        func addCandidate(serviceUrl: String, placementUrl: String?, redirectDomain: String?) {
            let normalized = normalizeUrl(serviceUrl)
            guard !normalized.isEmpty, !seen.contains(normalized) else { return }
            seen.insert(normalized)

            let normalizedPlacement = placementUrl?.nonEmpty.flatMap { normalizeUrl($0) }
            let domain = redirectDomain?.nonEmpty ?? extractHost(normalized)

            endpointCandidates.append(EndpointCandidate(
                serviceUrl: normalized,
                placementServiceUrl: normalizedPlacement,
                redirectDomain: domain
            ))
        }

        // Add configured service URL
        if let serviceUrl = config.serviceUrl?.nonEmpty {
            addCandidate(serviceUrl: serviceUrl, placementUrl: config.placementServiceUrl, redirectDomain: config.redirectDomain)
        }

        // Add fallback URLs
        for fallback in config.fallbackServiceUrls {
            if !fallback.isEmpty {
                addCandidate(serviceUrl: fallback, placementUrl: nil, redirectDomain: nil)
            }
        }

        // Add default endpoints if none configured
        if endpointCandidates.isEmpty {
            Self.DEFAULT_ENDPOINTS.forEach { defaultEndpoint in
                addCandidate(serviceUrl: defaultEndpoint.serviceUrl, placementUrl: defaultEndpoint.placementServiceUrl, redirectDomain: defaultEndpoint.redirectDomain)
            }
        } else {
            // Add default endpoints not already seen
            Self.DEFAULT_ENDPOINTS.forEach { defaultEndpoint in
                if !seen.contains(defaultEndpoint.serviceUrl) {
                    addCandidate(serviceUrl: defaultEndpoint.serviceUrl, placementUrl: defaultEndpoint.placementServiceUrl, redirectDomain: defaultEndpoint.redirectDomain)
                }
            }
        }
    }

    private func attemptTapjoyConnect() {
        guard state == .initializing else { return }
        guard currentEndpointIndex < endpointCandidates.count else {
            handleInitializationError("No more endpoints to try")
            return
        }

        let endpoint = endpointCandidates[currentEndpointIndex]
        let options = buildConnectOptions(endpoint)

        print("[TapjoyProvider] Connecting to Tapjoy using \(endpoint.serviceUrl) (attempt \(currentEndpointIndex + 1)/\(endpointCandidates.count))")

        bridge.connect(
            sdkKey: typedConfig?.sdkKey ?? "",
            options: options
        )
    }

    @discardableResult
    private func tryNextEndpoint() -> Bool {
        if currentEndpointIndex + 1 >= endpointCandidates.count {
            return false
        }

        currentEndpointIndex += 1
        print("[TapjoyProvider] Retrying with alternative endpoint (attempt \(currentEndpointIndex + 1)/\(endpointCandidates.count))")
        attemptTapjoyConnect()
        return true
    }

    private func handleConnectionSuccess() {
        guard state == .initializing else { return }

        state = .initialized
        providerListener?.providerDidInitialize(providerKey)

        print("[TapjoyProvider] Creating placement: \(placementName)")
        // Create placement with self as delegate
        currentPlacement = TJPlacement(name: placementName, delegate: self)
        guard let placement = currentPlacement else {
            print("[TapjoyProvider] Failed to create placement")
            handleInitializationError("Failed to create placement")
            return
        }

        print("[TapjoyProvider] Placement created successfully, delegate set: \(placement.delegate != nil)")
        print("[TapjoyProvider] Initial content ready state: \(placement.isContentReady)")
        placement.requestContent()

        // Check if content is already ready immediately
        if placement.isContentReady {
            print("[TapjoyProvider] Content is ready immediately, setting availability")
            setContentAvailable(true)
        }
    }

    private func handleInitializationError(_ message: String) {
        state = .error
        print("[TapjoyProvider] Initialization error: \(message)")
        let error = OfferwallError.providerUnavailable(provider: providerKey, reason: message)
        providerListener?.provider(providerKey, didFailToInitializeWith: error)
        contentAvailable = false
    }

    private func buildConnectOptions(_ endpoint: EndpointCandidate) -> [String: Any] {
        var options: [String: Any] = [
            "TJC_OPTION_ENABLE_LOGGING": true,
            "TJC_OPTION_DISABLE_ADVERTISING_ID_CHECK": true,
            "TJC_OPTION_SERVICE_URL": endpoint.serviceUrl,
            "TJC_OPTION_HOST_URL": endpoint.serviceUrl,
            "TJC_OPTION_PLACEMENT_SERVICE_URL": endpoint.placementServiceUrl ?? buildPlacementUrl(endpoint.serviceUrl)
        ]

        if let redirectDomain = endpoint.redirectDomain {
            options["TJC_OPTION_REDIRECT_DOMAIN"] = redirectDomain
        }

        if let disableOfferwallGateway = typedConfig?.disableOfferwallGateway {
            options["TJC_OPTION_DISABLE_OFFERWALL_GATEWAY"] = disableOfferwallGateway
        }

        // User ID
        if let userId = providerConfig?.userId.nonEmpty {
            options["TJC_OPTION_USER_ID"] = userId
        }

        // Privacy settings
        if let tcfConsent = providerConfig?.credentials["tcf_consent_string"]?.nonEmpty {
            options["user_consent"] = tcfConsent
        }
        if let usPrivacy = providerConfig?.credentials["us_privacy_string"]?.nonEmpty {
            options["us_privacy"] = usPrivacy
        }
        if let subjectToGdpr = providerConfig?.credentials["subject_to_gdpr"] as? Bool {
            options["gdpr_subject"] = subjectToGdpr
        }

        return options
    }

    private func buildPlacementUrl(_ serviceUrl: String) -> String {
        let normalized = normalizeUrl(serviceUrl)
        return normalized.hasSuffix("/") ? "\(normalized)placements/" : "\(normalized)/placements/"
    }

    private func normalizeUrl(_ url: String) -> String {
        var value = url.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return value }
        if !value.hasPrefix("http://") && !value.hasPrefix("https://") {
            value = "https://\(value)"
        }
        return value.hasSuffix("/") ? value : "\(value)/"
    }

    private func extractHost(_ url: String) -> String? {
        guard let urlObj = URL(string: url) else { return nil }
        return urlObj.host
    }

    // MARK: - TJPlacementListener (Tapjoy SDK callbacks)

    public func requestDidSucceed(_ placement: TJPlacement) {
        print("[TapjoyProvider] 🔥 requestDidSucceed called for placement: \(placement.placementName), contentReady: \(placement.isContentReady)")
        if placement.isContentReady {
            print("[TapjoyProvider] 🔥 Setting content available = true from requestDidSucceed")
            setContentAvailable(true)
        }
    }

    public func requestDidFail(_ placement: TJPlacement, error: Error?) {
        print("[TapjoyProvider] 🔥 requestDidFail called for placement: \(placement.placementName), error: \(error?.localizedDescription ?? "unknown")")
        setContentAvailable(false)
    }

    public func contentIsReady(_ placement: TJPlacement) {
        print("[TapjoyProvider] 🔥 contentIsReady called for placement: \(placement.placementName)")
        print("[TapjoyProvider] 🔥 Setting content available = true from contentIsReady")
        setContentAvailable(true)
    }

    public func contentDidAppear(_ placement: TJPlacement) {
        print("[TapjoyProvider] 🔥 contentDidAppear called for placement: \(placement.placementName)")
        guard !hasReportedShow else {
            print("[TapjoyProvider] ⚠️ contentDidAppear duplicate ignored")
            return
        }
        hasReportedShow = true
        providerListener?.providerDidShow(providerKey)
    }

    public func contentDidDisappear(_ placement: TJPlacement) {
        print("[TapjoyProvider] 🔥 contentDidDisappear called for placement: \(placement.placementName)")
        guard !hasReportedClose else {
            print("[TapjoyProvider] ⚠️ contentDidDisappear duplicate ignored")
            return
        }
        hasReportedClose = true

        // Add delay to prevent firstResponder crash when Unity retakes control
        // Tapjoy needs time to clean up its window before Unity's window becomes key again
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            guard let self = self else { return }
            self.providerListener?.providerDidClose(self.providerKey)
        }

        // Request new content after dismiss
        placement.requestContent()
        setContentAvailable(false)
    }

    // Additional TJPlacementDelegate methods
    public func didClick(_ placement: TJPlacement) {
        print("[TapjoyProvider] 🔥 didClick called for placement: \(placement.placementName)")
    }

    @available(*, deprecated, message: "TJActionRequest is deprecated, will be updated when new API is available")
    public func placement(_ placement: TJPlacement, didRequestPurchase request: TJActionRequest?, productId: String?) {
        print("[TapjoyProvider] 🔥 placement:didRequestPurchase:productId: called: \(productId ?? "nil")")
        request?.completed()
    }

    @available(*, deprecated, message: "TJActionRequest is deprecated, will be updated when new API is available")
    public func placement(_ placement: TJPlacement, didRequestReward request: TJActionRequest?, itemId: String?, quantity: Int32) {
        print("[TapjoyProvider] 🔥 placement:didRequestReward:itemId:quantity: called: \(itemId ?? "nil") x\(quantity)")
        if let itemId = itemId {
            providerListener?.provider(providerKey, didEarnRewardAmount: Int(quantity), currency: itemId)
        }
        request?.completed()
    }

    private func setContentAvailable(_ available: Bool) {
        guard contentAvailable != available else { return }
        contentAvailable = available
        print("[TapjoyProvider] Content availability changed: \(available)")
        providerListener?.provider(providerKey, didChangeAvailability: available)
    }

}

// MARK: - Extensions

extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
