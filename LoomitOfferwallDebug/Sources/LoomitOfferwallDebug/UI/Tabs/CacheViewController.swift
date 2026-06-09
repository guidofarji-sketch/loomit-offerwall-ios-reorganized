//
//  CacheViewController.swift
//  LoomitOfferwallDebug
//
//  Tab de Cache: config cacheada + cola de eventos pendientes.
//  Paridad con Android CacheFragment.
//

import UIKit
import LoomitOfferwallCore

@MainActor
final class CacheViewController: UIViewController {

    private let collector: DebugDataCollector

    // MARK: - Scroll container
    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()
    private lazy var stackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 16
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    // MARK: - Cached config section
    private lazy var configSectionLabel = makeSectionHeader("Cached Config")
    private lazy var configEmptyLabel: UILabel = {
        let l = UILabel()
        l.text = "No config in cache"
        l.textColor = .secondaryLabel
        l.font = .systemFont(ofSize: 14)
        return l
    }()
    private lazy var configCard: UIView = {
        let v = UIView()
        v.backgroundColor = .secondarySystemBackground
        v.layer.cornerRadius = 8
        return v
    }()
    private lazy var configSourceLabel = makeMonoLabel()
    private lazy var configAgeLabel    = makeMonoLabel()
    private lazy var configJsonView: UITextView = {
        let tv = UITextView()
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.backgroundColor = .clear
        return tv
    }()
    private lazy var copyConfigButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("Copy JSON", for: .normal)
        b.addTarget(self, action: #selector(copyConfigTapped), for: .touchUpInside)
        return b
    }()

    // MARK: - Pending events section
    private lazy var eventsSectionLabel = makeSectionHeader("Pending Events Queue")
    private lazy var eventsEmptyLabel: UILabel = {
        let l = UILabel()
        l.text = "No pending events"
        l.textColor = .secondaryLabel
        l.font = .systemFont(ofSize: 14)
        return l
    }()
    private lazy var eventsStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 8
        return sv
    }()

    // MARK: - Init

    init(collector: DebugDataCollector) {
        self.collector = collector
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(refresh)
        )
        loadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadData()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground
        view.addSubview(scrollView)
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32)
        ])

        // Config section
        stackView.addArrangedSubview(configSectionLabel)
        stackView.addArrangedSubview(configEmptyLabel)
        buildConfigCard()
        stackView.addArrangedSubview(configCard)

        // Events section
        stackView.addArrangedSubview(eventsSectionLabel)
        stackView.addArrangedSubview(eventsEmptyLabel)
        stackView.addArrangedSubview(eventsStackView)
    }

    private func buildConfigCard() {
        configCard.translatesAutoresizingMaskIntoConstraints = false
        let inner = UIStackView()
        inner.axis = .vertical
        inner.spacing = 6
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.addArrangedSubview(configSourceLabel)
        inner.addArrangedSubview(configAgeLabel)
        inner.addArrangedSubview(configJsonView)
        inner.addArrangedSubview(copyConfigButton)
        configCard.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: configCard.topAnchor, constant: 12),
            inner.leadingAnchor.constraint(equalTo: configCard.leadingAnchor, constant: 12),
            inner.trailingAnchor.constraint(equalTo: configCard.trailingAnchor, constant: -12),
            inner.bottomAnchor.constraint(equalTo: configCard.bottomAnchor, constant: -12)
        ])
    }

    // MARK: - Load

    private func loadData() {
        Task {
            let snapshot = await collector.snapshot()
            let pending  = await collector.pendingEvents()

            // Config section
            if let cached = snapshot?.cachedConfig, !cached.json.isEmpty {
                configEmptyLabel.isHidden = true
                configCard.isHidden = false

                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd HH:mm:ss"
                configSourceLabel.text = "Source: \(cached.source)"
                configAgeLabel.text    = "Age: \(formatAge(cached.age))  •  \(df.string(from: cached.timestamp))"
                configJsonView.text    = prettyJson(cached.json)
            } else {
                configEmptyLabel.isHidden = false
                configCard.isHidden = true
            }

            // Events section
            eventsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
            if pending.isEmpty {
                eventsEmptyLabel.isHidden = false
            } else {
                eventsEmptyLabel.isHidden = true
                for info in pending {
                    eventsStackView.addArrangedSubview(makeEventCard(info))
                }
            }
        }
    }

    // MARK: - Helpers

    private func makeEventCard(_ info: PendingEventInfo) -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 8

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let date = Date(timeIntervalSince1970: Double(info.timestamp) / 1000)

        let headerRow = UIStackView()
        headerRow.axis = .horizontal
        headerRow.distribution = .fill
        let typeLabel = makeMonoLabel()
        typeLabel.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
        typeLabel.text = info.type
        let tsLabel = makeMonoLabel()
        tsLabel.text = df.string(from: date)
        tsLabel.textAlignment = .right
        headerRow.addArrangedSubview(typeLabel)
        headerRow.addArrangedSubview(tsLabel)

        let providerLabel = makeMonoLabel()
        providerLabel.text = "Provider: \(info.provider)"
        let retryLabel = makeMonoLabel()
        retryLabel.text = "Retries: \(info.retryCount)  •  Priority: \(info.priority)"

        stack.addArrangedSubview(headerRow)
        stack.addArrangedSubview(providerLabel)
        stack.addArrangedSubview(retryLabel)

        if info.payload != "{}" && !info.payload.isEmpty {
            let payloadLabel = makeMonoLabel()
            payloadLabel.text = prettyJson(info.payload)
            payloadLabel.numberOfLines = 0
            stack.addArrangedSubview(payloadLabel)
        }

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10)
        ])
        return card
    }

    private func makeSectionHeader(_ title: String) -> UILabel {
        let l = UILabel()
        l.text = title
        l.font = .systemFont(ofSize: 16, weight: .bold)
        l.textColor = .label
        return l
    }

    private func makeMonoLabel() -> UILabel {
        let l = UILabel()
        l.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        l.textColor = .label
        l.numberOfLines = 0
        return l
    }

    private func prettyJson(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
           let str = String(data: pretty, encoding: .utf8) {
            return str
        }
        return raw
    }

    private func formatAge(_ age: TimeInterval) -> String {
        let s = Int(age)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(sec)s" }
        return "\(max(1, sec))s"
    }

    // MARK: - Actions

    @objc private func refresh() { loadData() }

    @objc private func copyConfigTapped() {
        UIPasteboard.general.string = configJsonView.text
        let alert = UIAlertController(title: nil, message: "Copied to clipboard", preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { alert.dismiss(animated: true) }
    }
}
