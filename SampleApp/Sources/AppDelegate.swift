//
//  AppDelegate.swift
//  LoomitOfferwallSampleApp
//
//  Entry point de la sample app.
//

import UIKit
import AppTrackingTransparency

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        window = UIWindow(frame: UIScreen.main.bounds)
        let mainVC = MainViewController()
        let navController = UINavigationController(rootViewController: mainVC)
        window?.rootViewController = navController
        window?.makeKeyAndVisible()

        // Request ATT for IDFA tracking
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { status in
                print("[AppDelegate] ATT status: \(status.rawValue)")
                switch status {
                case .authorized:
                    print("[AppDelegate] IDFA tracking authorized")
                case .denied:
                    print("[AppDelegate] IDFA tracking denied")
                case .notDetermined:
                    print("[AppDelegate] IDFA tracking not determined")
                case .restricted:
                    print("[AppDelegate] IDFA tracking restricted")
                @unknown default:
                    print("[AppDelegate] IDFA tracking unknown status")
                }
            }
        }

        return true
    }
}
