//
//  ShakeDetector.swift
//  LoomitOfferwallDebug
//
//  Detector de shake gesture para activar el debug panel.
//  Paridad con Android ShakeDetector.
//

import UIKit
import CoreMotion

/// Detecta movimientos bruscos (shake) del dispositivo
@MainActor
final class ShakeDetector {
    
    private let motionManager = CMMotionManager()
    private var isDetecting = false
    private var lastShakeTime: Date = .distantPast
    private let cooldownInterval: TimeInterval = 1.5 // 1.5s entre shakes
    private let threshold: Double = 2.5 // ~18 m/s² en Gs (2.5 * 9.8 ≈ 24.5)
    
    var onShake: (() -> Void)?
    
    func start() {
        guard motionManager.isAccelerometerAvailable, !isDetecting else { return }
        
        isDetecting = true
        motionManager.accelerometerUpdateInterval = 0.1 // 10Hz
        
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self = self, let data = data else { return }
            self.processAcceleration(data.acceleration)
        }
    }
    
    func stop() {
        isDetecting = false
        motionManager.stopAccelerometerUpdates()
    }
    
    private func processAcceleration(_ acceleration: CMAcceleration) {
        let magnitude = sqrt(
            acceleration.x * acceleration.x +
            acceleration.y * acceleration.y +
            acceleration.z * acceleration.z
        )
        
        // Detect shake when magnitude exceeds threshold
        if magnitude > threshold {
            let now = Date()
            if now.timeIntervalSince(lastShakeTime) > cooldownInterval {
                lastShakeTime = now
                onShake?()
            }
        }
    }
}

// Alternative: Use UIEvent motion detection for view-based shake
extension UIViewController {
    
    /// Enable shake detection via UIEvent (works when app is active)
    func enableDebugShakeDetection(onShake: @escaping () -> Void) {
        // Store callback in associated object
        objc_setAssociatedObject(
            self,
            &shakeCallbackKey,
            onShake as AnyObject,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        
        // Become first responder to receive motion events
        _ = self.becomeFirstResponder()
    }
    
    open override var canBecomeFirstResponder: Bool {
        return true
    }
    
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            if let callback = objc_getAssociatedObject(self, &shakeCallbackKey) as? () -> Void {
                callback()
            }
        }
        super.motionEnded(motion, with: event)
    }
}

private var shakeCallbackKey: UInt8 = 0
