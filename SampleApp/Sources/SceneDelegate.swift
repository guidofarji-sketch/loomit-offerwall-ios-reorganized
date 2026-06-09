//
//  SceneDelegate.swift
//  LoomitOfferwallSampleApp
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        window = UIWindow(windowScene: windowScene)
        window?.frame = windowScene.coordinateSpace.bounds
        
        // Reducir tamaño de fuentes globalmente
        if #available(iOS 13.0, *) {
            window?.overrideUserInterfaceStyle = .light
        }
        
        // Configurar navigation controller con fuentes más pequeñas
        let navController = UINavigationController(rootViewController: MainViewController())
        navController.navigationBar.prefersLargeTitles = false
        
        // Ajustar tamaño de fuente para toda la app
        UILabel.appearance().font = UIFont.systemFont(ofSize: 14)
        UIButton.appearance().titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        
        window?.rootViewController = navController
        window?.makeKeyAndVisible()
    }
}
