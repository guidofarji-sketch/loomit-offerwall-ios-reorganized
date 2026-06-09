//
//  ConfigViewController.swift
//  LoomitOfferwallDebug
//
//  Config Tab: muestra request/response JSON del backend - replicando Android layout.
//

import UIKit
import LoomitOfferwallCore

@MainActor
final class ConfigViewController: UIViewController {

    private let collector: DebugDataCollector
    private var notificationObserver: NSObjectProtocol?
    private var pendingRefreshTask: Task<Void, Never>?
    
    // UI Components - Android style cards
    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.showsVerticalScrollIndicator = true
        return sv
    }()
    
    private lazy var contentView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    // Config Response Card
    private lazy var configResponseCard: UIView = createCard()
    private lazy var configResponseHeader: UIView = createCardHeader()
    private lazy var configResponseTitleLabel: UILabel = createHeaderTitle(text: "Backend Config Response")
    private lazy var configSourceBadge: UILabel = createConfigSourceBadge()
    private lazy var configResponseTextView: UITextView = createJsonTextView()
    private lazy var copyConfigButton: UIButton = createCopyButton(title: "Copy to Clipboard")
    
    // Config Request Card
    private lazy var configRequestCard: UIView = createCard()
    private lazy var configRequestHeader: UIView = createCardHeader()
    private lazy var configRequestTitleLabel: UILabel = createHeaderTitle(text: "Request Sent to Backend")
    private lazy var configRequestTextView: UITextView = createJsonTextView()
    private lazy var copyRequestButton: UIButton = createCopyButton(title: "Copy to Clipboard")
    
    // Segment Card
    private lazy var segmentCard: UIView = createCard()
    private lazy var segmentHeader: UIView = createCardHeader()
    private lazy var segmentTitleLabel: UILabel = createHeaderTitle(text: "Resolved Segment")
    private lazy var segmentLabel: UILabel = UILabel()
    
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
        Task { await collector.attach(bridge: OfferwallSdk.shared.debugBridge()) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .debugDataUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshData() }
        }
        refreshData()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        pendingRefreshTask?.cancel()
        if let obs = notificationObserver {
            NotificationCenter.default.removeObserver(obs)
            notificationObserver = nil
        }
    }
    
    private func setupUI() {
        view.backgroundColor = UIColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0) // #F8F8F8
        
        // Setup scroll view
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        // Setup Config Response Card
        setupConfigResponseCard()
        
        // Setup Config Request Card  
        setupConfigRequestCard()
        
        // Setup Segment Card
        setupSegmentCard()
        
        setupConstraints()
    }
    
    private func createCard() -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0)
        card.layer.cornerRadius = 8
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOffset = CGSize(width: 0, height: 2)
        card.layer.shadowRadius = 4
        card.layer.shadowOpacity = 0.1
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }
    
    private func createCardHeader() -> UIView {
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        return header
    }
    
    private func createHeaderTitle(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 16, weight: .bold)
        label.textColor = UIColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1.0) // #212121
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    
    private func createConfigSourceBadge() -> UILabel {
        let badge = UILabel()
        badge.font = .systemFont(ofSize: 10, weight: .bold)
        badge.textColor = UIColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1.0)
        badge.backgroundColor = UIColor(red: 0.4, green: 0.97, blue: 0.47, alpha: 1.0) // #67F877
        badge.textAlignment = .center
        badge.layer.cornerRadius = 4
        badge.clipsToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.isUserInteractionEnabled = true
        
        
        return badge
    }
    
    private func createJsonTextView() -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.textColor = UIColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1.0)
        tv.backgroundColor = UIColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0)
        tv.layer.cornerRadius = 4
        tv.layer.borderWidth = 1
        tv.layer.borderColor = UIColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0).cgColor
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }
    
    private func createCopyButton(title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(UIColor(red: 0.4, green: 0.97, blue: 0.47, alpha: 1.0), for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 12)
        button.layer.cornerRadius = 4
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor(red: 0.4, green: 0.97, blue: 0.47, alpha: 1.0).cgColor
        button.backgroundColor = UIColor.clear
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
    
    private func setupConfigResponseCard() {
        // Header
        configResponseHeader.addSubview(configResponseTitleLabel)
        configResponseHeader.addSubview(configSourceBadge)
        
        // Card content
        configResponseCard.addSubview(configResponseHeader)
        configResponseCard.addSubview(configResponseTextView)
        configResponseCard.addSubview(copyConfigButton)
        
        contentView.addSubview(configResponseCard)
        
        // Button action
        copyConfigButton.addTarget(self, action: #selector(copyConfigTapped), for: .touchUpInside)
    }
    
    private func setupConfigRequestCard() {
        // Header
        configRequestHeader.addSubview(configRequestTitleLabel)
        
        // Card content
        configRequestCard.addSubview(configRequestHeader)
        configRequestCard.addSubview(configRequestTextView)
        configRequestCard.addSubview(copyRequestButton)
        
        contentView.addSubview(configRequestCard)
        
        // Button action
        copyRequestButton.addTarget(self, action: #selector(copyRequestTapped), for: .touchUpInside)
    }
    
    private func setupSegmentCard() {
        // Header
        segmentHeader.addSubview(segmentTitleLabel)
        
        // Segment label
        segmentLabel.font = .systemFont(ofSize: 14)
        segmentLabel.textColor = UIColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1.0)
        segmentLabel.numberOfLines = 0
        segmentLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Card content
        segmentCard.addSubview(segmentHeader)
        segmentCard.addSubview(segmentLabel)
        
        contentView.addSubview(segmentCard)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Content view
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            // Config Response Card
            configResponseCard.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            configResponseCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            configResponseCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            // Config Response Header
            configResponseHeader.topAnchor.constraint(equalTo: configResponseCard.topAnchor, constant: 16),
            configResponseHeader.leadingAnchor.constraint(equalTo: configResponseCard.leadingAnchor, constant: 16),
            configResponseHeader.trailingAnchor.constraint(equalTo: configResponseCard.trailingAnchor, constant: -16),
            configResponseHeader.heightAnchor.constraint(equalToConstant: 32),
            
            // Config Response Title
            configResponseTitleLabel.leadingAnchor.constraint(equalTo: configResponseHeader.leadingAnchor),
            configResponseTitleLabel.centerYAnchor.constraint(equalTo: configResponseHeader.centerYAnchor),
            
            // Config Source Badge
            configSourceBadge.trailingAnchor.constraint(equalTo: configResponseHeader.trailingAnchor),
            configSourceBadge.centerYAnchor.constraint(equalTo: configResponseHeader.centerYAnchor),
            configSourceBadge.widthAnchor.constraint(equalToConstant: 60),
            configSourceBadge.heightAnchor.constraint(equalToConstant: 20),
            
            // Config Response Text View
            configResponseTextView.topAnchor.constraint(equalTo: configResponseHeader.bottomAnchor, constant: 8),
            configResponseTextView.leadingAnchor.constraint(equalTo: configResponseCard.leadingAnchor, constant: 16),
            configResponseTextView.trailingAnchor.constraint(equalTo: configResponseCard.trailingAnchor, constant: -16),
            configResponseTextView.heightAnchor.constraint(equalToConstant: 200),
            
            // Copy Config Button
            copyConfigButton.topAnchor.constraint(equalTo: configResponseTextView.bottomAnchor, constant: 8),
            copyConfigButton.leadingAnchor.constraint(equalTo: configResponseCard.leadingAnchor, constant: 16),
            copyConfigButton.bottomAnchor.constraint(equalTo: configResponseCard.bottomAnchor, constant: -16),
            copyConfigButton.widthAnchor.constraint(equalToConstant: 120),
            copyConfigButton.heightAnchor.constraint(equalToConstant: 32),
            
            // Config Request Card
            configRequestCard.topAnchor.constraint(equalTo: configResponseCard.bottomAnchor, constant: 16),
            configRequestCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            configRequestCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            // Config Request Header
            configRequestHeader.topAnchor.constraint(equalTo: configRequestCard.topAnchor, constant: 16),
            configRequestHeader.leadingAnchor.constraint(equalTo: configRequestCard.leadingAnchor, constant: 16),
            configRequestHeader.trailingAnchor.constraint(equalTo: configRequestCard.trailingAnchor, constant: -16),
            configRequestHeader.heightAnchor.constraint(equalToConstant: 32),
            
            // Config Request Title
            configRequestTitleLabel.leadingAnchor.constraint(equalTo: configRequestHeader.leadingAnchor),
            configRequestTitleLabel.centerYAnchor.constraint(equalTo: configRequestHeader.centerYAnchor),
            
            // Config Request Text View
            configRequestTextView.topAnchor.constraint(equalTo: configRequestHeader.bottomAnchor, constant: 8),
            configRequestTextView.leadingAnchor.constraint(equalTo: configRequestCard.leadingAnchor, constant: 16),
            configRequestTextView.trailingAnchor.constraint(equalTo: configRequestCard.trailingAnchor, constant: -16),
            configRequestTextView.heightAnchor.constraint(equalToConstant: 200),
            
            // Copy Request Button
            copyRequestButton.topAnchor.constraint(equalTo: configRequestTextView.bottomAnchor, constant: 8),
            copyRequestButton.leadingAnchor.constraint(equalTo: configRequestCard.leadingAnchor, constant: 16),
            copyRequestButton.bottomAnchor.constraint(equalTo: configRequestCard.bottomAnchor, constant: -16),
            copyRequestButton.widthAnchor.constraint(equalToConstant: 120),
            copyRequestButton.heightAnchor.constraint(equalToConstant: 32),
            
            // Segment Card
            segmentCard.topAnchor.constraint(equalTo: configRequestCard.bottomAnchor, constant: 16),
            segmentCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            segmentCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            segmentCard.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            
            // Segment Header
            segmentHeader.topAnchor.constraint(equalTo: segmentCard.topAnchor, constant: 16),
            segmentHeader.leadingAnchor.constraint(equalTo: segmentCard.leadingAnchor, constant: 16),
            segmentHeader.trailingAnchor.constraint(equalTo: segmentCard.trailingAnchor, constant: -16),
            segmentHeader.heightAnchor.constraint(equalToConstant: 32),
            
            // Segment Title
            segmentTitleLabel.leadingAnchor.constraint(equalTo: segmentHeader.leadingAnchor),
            segmentTitleLabel.centerYAnchor.constraint(equalTo: segmentHeader.centerYAnchor),
            
            // Segment Label
            segmentLabel.topAnchor.constraint(equalTo: segmentHeader.bottomAnchor, constant: 8),
            segmentLabel.leadingAnchor.constraint(equalTo: segmentCard.leadingAnchor, constant: 16),
            segmentLabel.trailingAnchor.constraint(equalTo: segmentCard.trailingAnchor, constant: -16),
            segmentLabel.bottomAnchor.constraint(equalTo: segmentCard.bottomAnchor, constant: -16)
        ])
    }
    
    private func setupNavigation() {
        title = "Config"
        navigationController?.navigationBar.prefersLargeTitles = false
        
        // Minimalista navigation bar
        navigationController?.navigationBar.backgroundColor = UIColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0)
        navigationController?.navigationBar.shadowImage = UIImage()
        navigationController?.navigationBar.setBackgroundImage(UIImage(), for: .default)
        navigationController?.navigationBar.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 14, weight: .medium)]
    }
    
    private func refreshData() {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }

            let configJson = await self.collector.getLastConfigJson()
            guard !Task.isCancelled else { return }
            if let configJson = configJson, !configJson.isEmpty {
                self.configResponseTextView.text = self.formatJson(configJson)
            } else {
                self.configResponseTextView.text = "No config response received yet"
            }

            let requestJson = await self.collector.getLastRequestJson()
            guard !Task.isCancelled else { return }
            if let requestJson = requestJson, !requestJson.isEmpty {
                self.configRequestTextView.text = self.formatJson(requestJson)
            } else {
                self.configRequestTextView.text = "No config request sent yet"
            }

            let snapshot = await self.collector.snapshot()
            guard !Task.isCancelled else { return }

            if let segment = snapshot?.lastConfigSegment, !segment.isEmpty {
                self.segmentLabel.text = segment
            } else {
                self.segmentLabel.text = "Default (no specific segment)"
            }

            if let source = snapshot?.lastConfigSource, !source.isEmpty {
                self.configSourceBadge.text = source.uppercased()
                self.configSourceBadge.isHidden = false
            } else {
                self.configSourceBadge.isHidden = true
            }
        }
    }
    
    private func formatJson(_ json: String) -> String {
        return json.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Actions
    
    @objc private func copyConfigTapped() {
        let text = configResponseTextView.text
        UIPasteboard.general.string = text
        showToast("Config Response copied to clipboard")
    }
    
    @objc private func copyRequestTapped() {
        let text = configRequestTextView.text
        UIPasteboard.general.string = text
        showToast("Config Request copied to clipboard")
    }
    
    private func showToast(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                alert.dismiss(animated: true)
            }
        }
    }
}
