//
//  FloatingDebugPill.swift
//  LoomitOfferwallDebug
//
//  Pill flotante que aparece al detectar shake, similar a Android.
//

import UIKit

/// Pill flotante que aparece temporalmente para abrir el debug panel
@MainActor
final class FloatingDebugPill {
    
    private var pillView: UIView?
    private var window: UIWindow?
    
    var onTap: (() -> Void)?
    
    func show() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            return
        }
        
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .statusBar + 1
        window.backgroundColor = .clear
        // A transparent root VC is required for the window to receive and forward touch events
        let rootVC = UIViewController()
        rootVC.view.backgroundColor = .clear
        window.rootViewController = rootVC
        window.isHidden = false
        self.window = window
        
        let pillView = createPillView(in: scene.screen.bounds)
        rootVC.view.addSubview(pillView)
        self.pillView = pillView
        
        // Animate in from right
        pillView.transform = CGAffineTransform(translationX: 100, y: 0)
        UIView.animate(withDuration: 0.3) {
            pillView.transform = .identity
        }
        
        // Add tap gesture
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        pillView.addGestureRecognizer(tap)
    }
    
    func hide() {
        guard let pillView = pillView else { return }
        
        UIView.animate(withDuration: 0.3, animations: {
            pillView.transform = CGAffineTransform(translationX: 100, y: 0)
            pillView.alpha = 0
        }) { [weak self] _ in
            self?.pillView?.removeFromSuperview()
            self?.pillView = nil
            self?.window?.isHidden = true
            self?.window = nil
        }
    }
    
    private func createPillView(in screenBounds: CGRect) -> UIView {
        let pillWidth: CGFloat = 80
        let pillHeight: CGFloat = 40
        let container = UIView(frame: CGRect(
            x: screenBounds.width - pillWidth - 10,
            y: screenBounds.height / 2 - pillHeight / 2,
            width: pillWidth,
            height: pillHeight
        ))
        container.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 0.95)
        container.layer.cornerRadius = pillHeight / 2
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOffset = CGSize(width: 0, height: 2)
        container.layer.shadowRadius = 6
        container.layer.shadowOpacity = 0.4
        
        let loomitGreen = UIColor(red: 0, green: 1, blue: 0.741, alpha: 1) // #00FFBD
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: pillWidth, height: pillHeight))
        label.text = "loomit"
        label.font = .systemFont(ofSize: 15, weight: .bold)
        label.textColor = loomitGreen
        label.textAlignment = .center
        
        container.addSubview(label)
        
        return container
    }
    
    @objc private func handleTap() {
        onTap?()
    }
}
