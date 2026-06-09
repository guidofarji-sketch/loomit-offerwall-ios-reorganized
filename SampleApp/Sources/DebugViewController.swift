//
//  DebugViewController.swift
//  LoomitOfferwallSampleApp
//
//  Debug panel para inspeccionar eventos y estado del SDK.
//

import UIKit
import LoomitOfferwallDebug
import LoomitOfferwallCore

@MainActor
final class DebugViewController: UIViewController {
    
    private let collector: DebugDataCollector?
    
    private lazy var tableView: UITableView = {
        let tv = UITableView()
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(EventCell.self, forCellReuseIdentifier: EventCell.reuseId)
        tv.dataSource = self
        tv.delegate = self
        tv.rowHeight = UITableView.automaticDimension
        tv.estimatedRowHeight = 60
        return tv
    }()
    
    private lazy var refreshButton: UIBarButtonItem = {
        UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(didTapRefresh)
        )
    }()
    
    private lazy var clearButton: UIBarButtonItem = {
        UIBarButtonItem(
            title: "Limpiar",
            style: .plain,
            target: self,
            action: #selector(didTapClear)
        )
    }()
    
    private var events: [DebugEvent] = []
    private var refreshTimer: Timer?
    
    init(collector: DebugDataCollector?) {
        self.collector = collector
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Debug Panel"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItems = [refreshButton, clearButton]
        
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        loadEvents()
        
        // Auto-refresh every 2 seconds
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.loadEvents()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        refreshTimer?.invalidate()
    }
    
    @objc private func didTapRefresh() {
        loadEvents()
    }
    
    @objc private func didTapClear() {
        Task {
            await collector?.clearEvents()
            loadEvents()
        }
    }
    
    private func loadEvents() {
        Task {
            events = await collector?.recentEvents(limit: 50) ?? []
            tableView.reloadData()
        }
    }
}

// MARK: - UITableViewDataSource

extension DebugViewController: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return events.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: EventCell.reuseId, for: indexPath) as? EventCell else {
            return UITableViewCell()
        }
        let event = events[indexPath.row]
        cell.configure(with: event)
        return cell
    }
}

// MARK: - UITableViewDelegate

extension DebugViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let event = events[indexPath.row]
        let detailVC = EventDetailViewController(event: event)
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

// MARK: - EventCell

final class EventCell: UITableViewCell {
    
    static let reuseId = "EventCell"
    
    private let typeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let providerLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11)
        label.textColor = .tertiaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        contentView.addSubview(typeLabel)
        contentView.addSubview(providerLabel)
        contentView.addSubview(timeLabel)
        
        NSLayoutConstraint.activate([
            typeLabel.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            typeLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            typeLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            
            providerLabel.topAnchor.constraint(equalTo: typeLabel.bottomAnchor, constant: 4),
            providerLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            providerLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            
            timeLabel.topAnchor.constraint(equalTo: providerLabel.bottomAnchor, constant: 4),
            timeLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            timeLabel.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor)
        ])
    }
    
    func configure(with event: DebugEvent) {
        typeLabel.text = event.type
        providerLabel.text = "Provider: \(event.provider)"
        timeLabel.text = formatDate(event.timestamp)
        
        // Color based on level
        switch event.level {
        case .error:
            typeLabel.textColor = .systemRed
        case .warning:
            typeLabel.textColor = .systemOrange
        case .info:
            typeLabel.textColor = .systemBlue
        case .debug:
            typeLabel.textColor = .systemGreen
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

// MARK: - EventDetailViewController

final class EventDetailViewController: UIViewController {
    
    private let event: DebugEvent
    
    private lazy var textView: UITextView = {
        let tv = UITextView()
        tv.isEditable = false
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()
    
    init(event: DebugEvent) {
        self.event = event
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Event Details"
        view.backgroundColor = .systemBackground
        
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // Format details
        var details = """
        ID: \(event.id)
        Type: \(event.type)
        Level: \(event.level.rawValue)
        Provider: \(event.provider)
        Timestamp: \(event.timestamp)
        
        Payload:
        """
        
        for (key, value) in event.payload {
            details += "\n  \(key): \(value)"
        }
        
        textView.text = details
    }
}
