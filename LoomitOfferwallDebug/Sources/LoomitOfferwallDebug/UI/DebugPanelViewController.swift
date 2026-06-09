//
//  DebugPanelViewController.swift
//  LoomitOfferwallDebug
//
//  Main view controller del debug panel con tabs.
//  Paridad con Android DebugPanelActivity.
//

import UIKit
import LoomitOfferwallCore

/// View controller principal del debug panel con tabs
@MainActor
final class DebugPanelViewController: UITabBarController {

    private let collector: DebugDataCollector
    private var secretTapCount = 0
    var onDismiss: (() -> Void)?

    init() {
        // Usar el collector inyectado en DebugPanel, o crear uno nuevo si no existe
        if let injectedCollector = DebugPanel.getCollector() as? DebugDataCollector {
            self.collector = injectedCollector
        } else {
            self.collector = DebugDataCollector()
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTabs()
        setupNavigation()
        attachCollector()
    }
    
    private func setupNavigation() {
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationController?.navigationBar.backgroundColor = UIColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0)
        navigationController?.navigationBar.shadowImage = UIImage()
        navigationController?.navigationBar.setBackgroundImage(UIImage(), for: .default)

        // Título tappable — 7 taps activan el environment switcher
        let titleLabel = UILabel()
        titleLabel.text = "Debug Panel"
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = UIColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1)
        titleLabel.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(titleTapped))
        titleLabel.addGestureRecognizer(tap)
        navigationItem.titleView = titleLabel

        let closeButton = UIBarButtonItem(title: "Close", style: .plain, target: self, action: #selector(dismissPanel))
        closeButton.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 14)], for: .normal)
        navigationItem.rightBarButtonItem = closeButton
    }

    @objc private func titleTapped() {
        secretTapCount += 1
        if secretTapCount >= 7 {
            secretTapCount = 0
            showEnvironmentSwitcher()
        }
    }

    private func showEnvironmentSwitcher() {
        Task { @MainActor in
            let bridge = await OfferwallSdk.shared.debugBridge()
            let current = await bridge.currentEnvironment()

            let options: [(label: String, env: BackendEnvironment)] = [
                ("LIVE \u{2014} Production", .live),
                ("TEST \u{2014} Staging",    .test)
            ]
            let currentIndex = options.firstIndex { $0.env == current } ?? 0

            let alert = UIAlertController(
                title: "Environment Switcher",
                message: "Developer only. Requires test mode enabled.\nRestart fetch config to apply.",
                preferredStyle: .alert
            )
            for (i, opt) in options.enumerated() {
                let mark = i == currentIndex ? "\u{2713} " : "   "
                alert.addAction(UIAlertAction(title: "\(mark)\(opt.label)", style: .default) { _ in
                    guard i != currentIndex else { return }
                    Task {
                        await bridge.setEnvironmentForDebug(opt.env)
                    }
                })
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alert, animated: true)
        }
    }
    
    @objc private func dismissPanel() {
        dismiss(animated: true) { [weak self] in
            self?.onDismiss?()
        }
    }
    
    private func attachCollector() {
        Task {
            let bridge = await OfferwallSdk.shared.debugBridge()
            await collector.attach(bridge: bridge)
            await bridge.applyPersistedEnvironmentIfNeeded()
        }
    }
    
    private func setupTabs() {
        // Tab bar minimalista sin íconos - estilo Android
        tabBar.backgroundColor = UIColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0)
        tabBar.shadowImage = UIImage()
        tabBar.backgroundImage = UIImage()
        tabBar.tintColor = UIColor(red: 0.4, green: 0.97, blue: 0.47, alpha: 1.0)
        tabBar.unselectedItemTintColor = .darkGray
        
        // Configurar tabs sin íconos - Android order
        let tabs: [(UIViewController, String)] = [
            (IdentifiersViewController(collector: collector), "Identifiers"),
            (ConfigViewController(collector: collector), "Config"),
            (EventsViewController(collector: collector), "Events"),
            (CacheViewController(collector: collector), "Cache"),
            (ProvidersViewController(collector: collector), "Providers"),
            (ExperimentsViewController(collector: collector), "Experiments"),
            (CustomPropertiesViewController(collector: collector), "Properties"),
            (DependenciesViewController(), "Dependencies"),
            (AntifraudViewController(), "Antifraud")
        ]
        
        viewControllers = tabs.map { vc, title in
            vc.title = title
            let tabBarItem = UITabBarItem(title: title, image: nil, selectedImage: nil)
            vc.tabBarItem = tabBarItem
            return UINavigationController(rootViewController: vc)
        }
        
        // Apariencia minimalista
        if #available(iOS 15.0, *) {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0)
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: UIColor(red: 0.4, green: 0.97, blue: 0.47, alpha: 1.0)]
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.darkGray]
            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
        }
    }
}
