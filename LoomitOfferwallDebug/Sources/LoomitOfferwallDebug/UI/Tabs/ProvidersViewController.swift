//
//  ProvidersViewController.swift
//  LoomitOfferwallDebug
//
//  Tab de Providers: lista de proveedores del plan actual con estados.
//

import UIKit
import LoomitOfferwallCore

@MainActor
final class ProvidersViewController: UIViewController {

    private let tableView = UITableView()
    private var providerPlan: [ProviderPlanInfo] = []
    private let collector: DebugDataCollector

    init(collector: DebugDataCollector) {
        self.collector = collector
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        Task { @MainActor in
            await loadProviders()
        }

        // Listen for provider plan changes from DebugDataCollector
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("com.loomit.debug.providerPlanUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.loadProviders()
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { @MainActor in
            await loadProviders()
        }
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        title = "Providers"
        view.backgroundColor = .systemBackground
        
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(ProviderCell.self, forCellReuseIdentifier: ProviderCell.reuseId)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 100
        
        view.addSubview(tableView)
        
        // Add refresh control
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshProviders), for: .valueChanged)
        tableView.refreshControl = refreshControl
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - Data Loading

    private func loadProviders() async {
        providerPlan = await collector.getProviderPlan()
        tableView.reloadData()
        tableView.refreshControl?.endRefreshing()
    }

    @objc private func refreshProviders() {
        Task {
            await loadProviders()
        }
    }

    private func testProvider(_ providerName: String) {
        // Present from the debug suite's nav controller (currently on screen).
        // MyChipsProvider now always presents modally fullscreen, so the offerwall
        // will appear on top of the debug suite. When the offerwall closes,
        // the debug suite is back in the foreground.
        let presenter = navigationController ?? self

        Task {
            await OfferwallSdk.shared.show(
                from: presenter,
                providerOverride: providerName,
                adSpace: nil
            )
        }
    }

    private func findTopPresentingViewController() -> UIViewController? {
        // Try presentingViewController first
        if let presenter = presentingViewController {
            return presenter
        }

        // Try parent's presentingViewController
        if let parent = parent, let presenter = parent.presentingViewController {
            return presenter
        }

        // Try to find the root view controller
        if let windowScene = view.window?.windowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            return findTopViewController(from: rootVC)
        }

        return nil
    }

    private func findTopViewController(from viewController: UIViewController) -> UIViewController {
        if let presented = viewController.presentedViewController {
            return findTopViewController(from: presented)
        }

        if let navigationController = viewController as? UINavigationController,
           let topVC = navigationController.topViewController {
            return findTopViewController(from: topVC)
        }

        if let tabBarController = viewController as? UITabBarController,
           let selectedVC = tabBarController.selectedViewController {
            return findTopViewController(from: selectedVC)
        }

        return viewController
    }

    private func showToast(_ message: String) {
        let alert = UIAlertController(
            title: nil,
            message: message,
            preferredStyle: .alert
        )
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            alert.dismiss(animated: true)
        }
    }
}

// MARK: - UITableViewDataSource

extension ProvidersViewController: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return providerPlan.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: ProviderCell.reuseId,
            for: indexPath
        ) as? ProviderCell else {
            return UITableViewCell()
        }
        let info = providerPlan[indexPath.row]
        cell.configure(with: info, isActive: indexPath.row == 0)
        cell.onTestTapped = { [weak self] providerName in
            self?.testProvider(providerName)
        }
        return cell
    }
}

// MARK: - UITableViewDelegate

extension ProvidersViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

// MARK: - ProviderCell

final class ProviderCell: UITableViewCell {
    
    static let reuseId = "ProviderCell"
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let priorityLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.backgroundColor = .systemBlue
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let statusStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private let testButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private var providerName: String = ""
    var onTestTapped: ((String) -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        contentView.addSubview(nameLabel)
        contentView.addSubview(priorityLabel)
        contentView.addSubview(statusStack)
        contentView.addSubview(testButton)
        
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            
            priorityLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            priorityLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 8),
            priorityLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.layoutMarginsGuide.trailingAnchor),
            priorityLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
            priorityLabel.heightAnchor.constraint(equalToConstant: 20),
            
            statusStack.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 8),
            statusStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            statusStack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            
            testButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            testButton.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor)
        ])
        
        testButton.addTarget(self, action: #selector(testButtonTapped), for: .touchUpInside)
    }
    
    func configure(with info: ProviderPlanInfo, isActive: Bool) {
        providerName = info.provider
        nameLabel.text = info.provider
        priorityLabel.text = "Priority: \(info.priority)"
        
        // Active indicator
        if isActive {
            contentView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.1)
        } else {
            contentView.backgroundColor = nil
        }
        
        statusStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // Init status
        let initLabel = createStatusLabel(
            text: info.isInitialized ? "✓ Initialized" : "✗ Not Initialized",
            isOk: info.isInitialized
        )
        
        // Content status
        let contentLabel = createStatusLabel(
            text: info.hasContent ? "✓ Content Available" : "✗ No Content",
            isOk: info.hasContent
        )
        
        statusStack.addArrangedSubview(initLabel)
        statusStack.addArrangedSubview(contentLabel)
        
        // Test button
        let canTest = info.isInitialized && info.hasContent
        testButton.isEnabled = canTest
        testButton.setTitle(canTest ? "Test \(info.provider)" : "Cannot Test", for: .normal)
        testButton.setTitleColor(canTest ? .systemBlue : .systemGray, for: .normal)
    }
    
    @objc private func testButtonTapped() {
        onTestTapped?(providerName)
    }
    
    private func createStatusLabel(text: String, isOk: Bool) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 12)
        label.textColor = isOk ? .systemGreen : (text.contains("No Content") ? .systemOrange : .systemRed)
        return label
    }
}
