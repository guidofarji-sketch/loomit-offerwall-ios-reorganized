//
//  IdentifiersViewController.swift
//  LoomitOfferwallDebug
//
//  Tab de Identifiers: XIFA, Publisher User ID, Advertising ID, etc.
//

import UIKit
import LoomitOfferwallCore

@MainActor
final class IdentifiersViewController: UIViewController {
    
    private let collector: DebugDataCollector
    
    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.isScrollEnabled = true
        return tv
    }()
    
    private var identifiers: [(title: String, value: String)] = []
    
    init(collector: DebugDataCollector) {
        self.collector = collector
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNavigation()
        tableView.dataSource = self
        tableView.delegate = self
        subscribeToUpdates()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadIdentifiers()
    }

    private func subscribeToUpdates() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onDebugDataUpdated),
            name: .debugDataUpdated,
            object: nil
        )
    }

    @objc private func onDebugDataUpdated() {
        loadIdentifiers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupUI() {
        view.backgroundColor = .systemGroupedBackground
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupNavigation() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(refreshIdentifiers)
        )
    }
    
    private func loadIdentifiers() {
        Task {
            let snapshot = await collector.snapshot()
            
            var items: [(title: String, value: String)] = []
            
            items.append(("XIFA (Internal UUID)", snapshot?.xifa ?? "N/A"))
            items.append(("Device Fingerprint", snapshot?.deviceFingerprint ?? "N/A"))
            items.append(("Bundle Identifier", snapshot?.bundleIdentifier ?? "N/A"))
            items.append(("Publisher User ID", snapshot?.publisherUserId ?? "Not set"))
            items.append(("Has Advertising ID", snapshot.map { $0.hasAdvertisingId ? "Yes" : "No" } ?? "N/A"))
            if let adId = snapshot?.advertisingId {
                items.append(("Advertising ID (IDFA)", adId))
            }
            
            identifiers = items
            tableView.reloadData()
        }
    }
    
    @objc private func refreshIdentifiers() {
        loadIdentifiers()
    }
}

// MARK: - UITableViewDataSource

extension IdentifiersViewController: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return identifiers.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        let item = identifiers[indexPath.row]
        
        var config = cell.defaultContentConfiguration()
        config.text = item.title
        config.secondaryText = item.value
        config.secondaryTextProperties.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        config.secondaryTextProperties.numberOfLines = 0
        config.secondaryTextProperties.lineBreakMode = .byTruncatingMiddle
        cell.contentConfiguration = config
        
        return cell
    }
}

// MARK: - UITableViewDelegate

extension IdentifiersViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let item = identifiers[indexPath.row]
        UIPasteboard.general.string = item.value
        
        let alert = UIAlertController(
            title: "Copied",
            message: "\(item.title) copied to clipboard",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
