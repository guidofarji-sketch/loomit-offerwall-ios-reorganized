//
//  DebugPanel.swift
//  LoomitOfferwallDebug
//
//  Entry point para la Debugging Suite del SDK.
//  Paridad con Android DebugPanel.kt
//

import UIKit
import LoomitOfferwallCore

/// Coordinador principal de la Debugging Suite.
/// Se activa automáticamente cuando debugging está habilitado.
@MainActor
public final class DebugPanel {

    public static let shared = DebugPanel()

    private var coordinator: DebugPanelCoordinator?
    private var isEnabled = false
    private var collector: DebugDataCollectorBridge?

    private init() {}
    
    /// Verifica si el debug panel está habilitado
    public static func isEnabled() -> Bool {
        return shared.isEnabled
    }
    
    /// Activa/desactiva el debug panel manualmente
    public static func setEnabled(_ enabled: Bool) {
        shared.isEnabled = enabled
        if enabled {
            shared.startMonitoring()
        } else {
            shared.stopMonitoring()
        }
    }

    /// Inicializa el DebugPanel e inyecta el DebugDataCollector en el SDK
    /// Debe llamarse después de setDebuggingEnabled en el SDK
    public static func initialize(dataCollector: DebugDataCollectorBridge) {
        shared.collector = dataCollector
        Task {
            await OfferwallSdk.shared.setDebugDataCollector(dataCollector)
            // Aplica el environment persistido (paridad con Android loadSavedEnvironmentPreference)
            await OfferwallSdk.shared.loadAndApplyDebugEnvironmentIfNeeded()
        }
    }

    /// Obtiene el collector inyectado (usado por DebugPanelViewController)
    internal static func getCollector() -> DebugDataCollectorBridge? {
        return shared.collector
    }
    
    /// Llamar desde motionEnded del ViewController para mostrar la pill flotante.
    /// No abre el panel directamente — el usuario debe tappear la pill.
    public static func handleShake() {
        guard shared.isEnabled else { return }
        shared.coordinator?.showFloatingPill()
    }

    /// Muestra el debug panel inmediatamente (para botón manual)
    public static func show(from viewController: UIViewController) {
        guard shared.isEnabled else { return }
        // Prevent multiple instances from being presented simultaneously
        guard !shared.isPresenting else {
            print("[DebugPanel] Already presenting, ignoring duplicate show request")
            return
        }
        shared.isPresenting = true
        shared.coordinator?.showDebugPanel(from: viewController) {
            shared.isPresenting = false
        }
    }
    
    private var isPresenting = false
    
    /// Inicia el monitoreo (shake detector)
    private func startMonitoring() {
        guard coordinator == nil else { return }
        coordinator = DebugPanelCoordinator()
        coordinator?.startMonitoring()
    }
    
    /// Detiene el monitoreo
    private func stopMonitoring() {
        coordinator?.stopMonitoring()
        coordinator = nil
    }
    
    /// Llamar desde OfferwallSdk cuando el debugging status cambia
    internal static func updateDebuggingStatus(_ status: Bool) {
        setEnabled(status)
    }
}

/// Coordinador interno que maneja el shake detector y la pill flotante
@MainActor
final class DebugPanelCoordinator {
    
    private var shakeDetector: ShakeDetector?
    private var floatingPill: FloatingDebugPill?
    private var isMonitoring = false
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        shakeDetector = ShakeDetector()
        shakeDetector?.onShake = { [weak self] in
            self?.showFloatingPill()
        }
        shakeDetector?.start()
    }
    
    func stopMonitoring() {
        isMonitoring = false
        shakeDetector?.stop()
        shakeDetector = nil
        hideFloatingPill()
    }
    
    func showFloatingPill() {
        guard floatingPill == nil else { return }
        
        let pill = FloatingDebugPill()
        pill.onTap = { [weak self] in
            // Capture topVC BEFORE hiding the pill — hiding destroys its UIWindow
            // which changes what topViewController() returns.
            let topVC = UIApplication.shared.topViewController()
            self?.hideFloatingPill()
            self?.showDebugPanel(from: topVC)
        }
        pill.show()
        floatingPill = pill
        
        // Auto-hide after 10 seconds — only if this same pill is still showing
        let pillRef = pill
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.floatingPill === pillRef else { return }
            self.hideFloatingPill()
        }
    }
    
    private func hideFloatingPill() {
        floatingPill?.hide()
        floatingPill = nil
    }
    
    func showDebugPanel(from viewController: UIViewController?, onDismiss: (() -> Void)? = nil) {
        guard let topVC = viewController ?? UIApplication.shared.topViewController() else {
            onDismiss?()
            return
        }
        
        // Check if already presenting
        if let presented = topVC.presentedViewController as? UINavigationController,
           presented.viewControllers.first is DebugPanelViewController {
            print("[DebugPanelCoordinator] DebugPanel already presented, not presenting again")
            onDismiss?()
            return
        }
        
        let debugVC = DebugPanelViewController()
        let navVC = UINavigationController(rootViewController: debugVC)
        navVC.modalPresentationStyle = .fullScreen
        
        // Track dismissal to reset isPresenting flag
        debugVC.onDismiss = onDismiss
        
        topVC.present(navVC, animated: true)
    }
}

// MARK: - Helper Extensions

extension UIApplication {
    func topViewController() -> UIViewController? {
        // Find the main app window at normal level — ignore overlay windows
        // (e.g. the pill's UIWindow at .statusBar+1) so we present on the real VC.
        let allWindows = connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
        let mainWindow = allWindows
            .filter({ !$0.isHidden && $0.windowLevel == .normal })
            .first ?? allWindows.first(where: { $0.isKeyWindow })
        return mainWindow?.rootViewController?.topMostViewController()
    }
}

extension UIViewController {
    func topMostViewController() -> UIViewController {
        if let presented = presentedViewController {
            return presented.topMostViewController()
        }
        if let nav = self as? UINavigationController {
            return nav.visibleViewController?.topMostViewController() ?? nav
        }
        if let tab = self as? UITabBarController {
            return tab.selectedViewController?.topMostViewController() ?? tab
        }
        return self
    }
}
