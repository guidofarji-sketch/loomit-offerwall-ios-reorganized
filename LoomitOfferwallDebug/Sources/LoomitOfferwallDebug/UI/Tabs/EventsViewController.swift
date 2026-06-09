//
//  EventsViewController.swift
//  LoomitOfferwallDebug
//
//  Tab de eventos con filtros y exportación.
//

import UIKit
import LoomitOfferwallCore

@MainActor
final class EventsViewController: UIViewController {
    
    private let collector: DebugDataCollector
    
    private lazy var tableView: UITableView = {
        let tv = UITableView()
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(EventCell.self, forCellReuseIdentifier: EventCell.reuseId)
        tv.rowHeight = UITableView.automaticDimension
        tv.estimatedRowHeight = 60
        return tv
    }()
    
    private lazy var filterSegmented: UISegmentedControl = {
        let items = ["All", "Config", "Init", "Show", "Errors"]
        let sc = UISegmentedControl(items: items)
        sc.selectedSegmentIndex = 0
        sc.translatesAutoresizingMaskIntoConstraints = false
        sc.addTarget(self, action: #selector(filterChanged), for: .valueChanged)
        return sc
    }()
    
    private var allEvents: [DebugEvent] = []
    private var filteredEvents: [DebugEvent] = []
    private var notificationObserver: NSObjectProtocol?
    private var currentFilter: EventFilter = .all
    
    enum EventFilter {
        case all, config, init_, show, errors
    }
    
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
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .debugDataUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.loadEvents() }
        }
        loadEvents()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if let obs = notificationObserver {
            NotificationCenter.default.removeObserver(obs)
            notificationObserver = nil
        }
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        view.addSubview(filterSegmented)
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            filterSegmented.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            filterSegmented.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            filterSegmented.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            tableView.topAnchor.constraint(equalTo: filterSegmented.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupNavigation() {
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareEvents)),
            UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(clearEvents))
        ]
    }
    
    private func loadEvents() {
        Task {
            allEvents = await collector.recentEvents(limit: 100)
            applyFilter()
        }
    }
    
    private func applyFilter() {
        switch currentFilter {
        case .all:
            filteredEvents = allEvents
        case .config:
            filteredEvents = allEvents.filter { $0.type.contains("config") }
        case .init_:
            filteredEvents = allEvents.filter { $0.type.contains("init") }
        case .show:
            filteredEvents = allEvents.filter { 
                $0.type.contains("show") || $0.type.contains("content") 
            }
        case .errors:
            filteredEvents = allEvents.filter { 
                $0.level == .error || $0.type.contains("error") || $0.type.contains("fail")
            }
        }
        tableView.reloadData()
    }
    
    @objc private func filterChanged() {
        switch filterSegmented.selectedSegmentIndex {
        case 0: currentFilter = .all
        case 1: currentFilter = .config
        case 2: currentFilter = .init_
        case 3: currentFilter = .show
        case 4: currentFilter = .errors
        default: currentFilter = .all
        }
        applyFilter()
    }
    
    @objc private func clearEvents() {
        Task {
            await collector.clearEvents()
            loadEvents()
        }
    }
    
    @objc private func shareEvents() {
        let text = allEvents.map { event in
            "[\(formatDate(event.timestamp))] \(event.level.rawValue.uppercased()): \(event.type) - \(event.provider)"
        }.joined(separator: "\n")
        
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        present(activityVC, animated: true)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

// MARK: - UITableViewDataSource

extension EventsViewController: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredEvents.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: EventCell.reuseId, for: indexPath) as? EventCell else {
            return UITableViewCell()
        }
        let event = filteredEvents[indexPath.row]
        cell.configure(with: event)
        return cell
    }
}

// MARK: - UITableViewDelegate

extension EventsViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let event = filteredEvents[indexPath.row]
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
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        timeLabel.text = formatter.string(from: event.timestamp)
        
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
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
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
