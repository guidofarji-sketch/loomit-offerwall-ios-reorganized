//
//  MyChipsProvider.swift
//  LoomitOfferwallAdapterMyChips
//
//  Implementación de `OfferwallProvider` para MyChips/MAF.
//
//  Flujo de show (según docu oficial):
//  - El SDK MyChips no expone un `present` propio. Provee `MCWebViewController`
//    que el publisher empuja a un `UINavigationController`.
//  - El adapter:
//      1. Si el `presenter` (o su `navigationController`) es un nav controller,
//         hace `pushViewController(...)`.
//      2. Caso contrario, presenta modalmente envolviendo el VC en un nav nuevo.
//  - El `onClose` del MCWebViewController dispara `currentClose` del adapter,
//    que invoca al listener interno y desmonta la VC.
//

import Foundation
import UIKit
import LoomitOfferwallAdapterAPI

/// Listener opcional para reward checks (Self-Managed Currency mode).
///
/// **Independiente** del listener de UX (`OfferwallProviderListener`). Es un
/// canal específico para que el publisher reciba rewards del lado cliente
/// — el modo S2S (server-to-server) no necesita esto.
public protocol MyChipsRewardListener: AnyObject, Sendable {
    @MainActor func myChipsDidEarn(reward: MyChipsReward, adUnitId: String)
    @MainActor func myChipsRewardCheckFailed(error: Error, adUnitId: String)
}

@MainActor
public final class MyChipsProvider: OfferwallProvider {

    private enum State {
        case notInitialized
        case initialized
    }

    public nonisolated let providerKey: String = "mychips"
    public nonisolated let providerSdkVersion: String? = nil  // SDK no lo expone

    private let bridge: MyChipsSDKBridge
    private weak var rewardListener: MyChipsRewardListener?

    private var state: State = .notInitialized
    private var typedConfig: MyChipsConfig?
    private var providerConfig: ProviderConfig?
    private var presentedVC: UIViewController?
    private weak var presentingNav: UINavigationController?
    private var presentedModally: Bool = false

    /// Listener para resolver el callback async del show.
    private weak var providerListener: OfferwallProviderListener?

    /// Static reference to the last created instance (for testing)
    @MainActor
    public static var lastInstance: MyChipsProvider?

    public init(
        bridge: MyChipsSDKBridge,
        rewardListener: MyChipsRewardListener? = nil
    ) {
        self.bridge = bridge
        self.rewardListener = rewardListener
    }

    // MARK: - OfferwallProvider conformance

    public func initialize(
        config: ProviderConfig,
        listener: OfferwallProviderListener
    ) async -> Result<Void, OfferwallError> {

        self.providerListener = listener
        Self.lastInstance = self // Store reference for test access

        // Guardar ProviderConfig para acceso a adSpaceOverrides
        self.providerConfig = config

        // 1. Parsear config tipada del backend.
        let parsed = MyChipsConfig.parse(from: config)
        let mcConfig: MyChipsConfig
        switch parsed {
        case .success(let c):  mcConfig = c
        case .failure(let e):
            listener.provider(providerKey, didFailToInitializeWith: e)
            return .failure(e)
        }
        self.typedConfig = mcConfig

        // 2. Configurar SDK + setters según docu MyChips.
        bridge.configure(apiKey: mcConfig.apiKey)
        bridge.setUserId(config.userId)

        // IDFA si el publisher lo proveyó (vía credentials/settings o futuro
        // ATT pipeline). Hoy no lo recibimos del Core; el publisher puede
        // pasarlo en `credentials.idfa` o llamar al SDK directamente. Dejamos
        // hook por si lo manda el backend.
        if let idfa = config.credentials["idfa"]?.nonEmpty
            ?? config.settings["idfa"]?.nonEmpty {
            bridge.setIdfa(idfa)
        }

        if let age = mcConfig.age { bridge.setAge(age) }
        if let gender = mcConfig.gender { bridge.setGender(gender) }

        bridge.setAffSub1(mcConfig.affSub1)
        bridge.setAffSub2(mcConfig.affSub2)
        bridge.setAffSub3(mcConfig.affSub3)
        bridge.setAffSub4(mcConfig.affSub4)
        bridge.setAffSub5(mcConfig.affSub5)

        if let title = mcConfig.title?.nonEmpty {
            bridge.setToolbarTitle(title)
        }

        state = .initialized
        listener.providerDidInitialize(providerKey)
        // MyChips no expone "content available" como señal separada; una vez
        // configurado, asumimos disponibilidad.
        listener.provider(providerKey, didChangeAvailability: true)
        return .success(())
    }

    public func isAvailable() -> Bool {
        state == .initialized
    }

    public func show(
        from presenter: UIViewController,
        adSpace: String?
    ) async -> Result<Void, OfferwallError> {
        guard state == .initialized, let mcConfig = typedConfig else {
            return .failure(.providerUnavailable(provider: providerKey, reason: "not initialized"))
        }

        // Resolver ad_unit_id según adSpace usando adSpaceOverrides
        let adUnit: String
        if let adSpace = adSpace?.nonEmpty,
           let overrideCredentials = providerConfig?.adSpaceOverrides[adSpace],
           let overrideAdUnitId = overrideCredentials["ad_unit_id"] ?? overrideCredentials["adUnitId"] {
            adUnit = overrideAdUnitId
        } else {
            adUnit = mcConfig.adUnitId
        }

        // Construir VC.
        let webVC = bridge.makeWebViewController(adUnitId: adUnit) { [weak self] in
            self?.dismissCurrent()
        }

        // Always present modally fullscreen. This ensures the offerwall
        // appears on top of whatever is currently on screen — including when
        // called from inside the debug suite modal. Pushing onto a nav stack
        // would place the VC behind any modal that is already presented on top.
        let nav = UINavigationController(rootViewController: webVC)
        nav.modalPresentationStyle = .fullScreen
        presenter.present(nav, animated: true)
        self.presentingNav = nav
        self.presentedVC = webVC
        self.presentedModally = true

        // Notify Core that the offerwall is now visible.
        // MAF has no native delegate for this; we report it directly since
        // the VC is already on screen after present() returns.
        providerListener?.providerDidShow(providerKey)

        return .success(())
    }

    public func close() {
        dismissCurrent()
    }

    // MARK: - Reward checking (Self-Managed Currency)

    /// Invocable por el publisher cuando la app vuelve a foreground
    /// (`scenePhase == .active` o `sceneDidBecomeActive`). Si configuró
    /// Self-Managed Currency en el dashboard, puede haber reward pendiente.
    /// En modo S2S, llamar a esto no causa daño (simplemente retorna sin reward).
    public func checkPendingReward() {
        guard let mcConfig = typedConfig else { return }
        bridge.getReward(
            adUnitId: mcConfig.adUnitId,
            onReward: { [weak self] reward in
                guard let self = self, let listener = self.rewardListener else { return }
                listener.myChipsDidEarn(reward: reward, adUnitId: mcConfig.adUnitId)
            },
            onError: { [weak self] error in
                self?.rewardListener?.myChipsRewardCheckFailed(
                    error: error,
                    adUnitId: mcConfig.adUnitId
                )
            }
        )
    }

    // MARK: - Internal

    private func dismissCurrent() {
        guard presentedVC != nil else { return }
        if presentedModally {
            // Nuestro nav wrapper es vc.parent? no, lo presentamos directamente.
            presentingNav?.dismiss(animated: true)
        } else if let nav = presentingNav {
            nav.popViewController(animated: true)
        }
        presentedVC = nil
        presentingNav = nil
        presentedModally = false

        // Notificar al SDK que el offerwall se cerró
        providerListener?.providerDidClose(providerKey)
    }
}

// MARK: - Helpers

private extension String {
    /// Devuelve `self` si no está vacío después de trim, sino `nil`.
    var nonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
