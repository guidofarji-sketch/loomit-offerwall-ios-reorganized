//
//  CustomPropertiesViewController.swift
//  LoomitOfferwallDebug
//
//  Root cause fix: UIBarButtonItem with style:.plain resolves navigation bar
//  adaptive tintColor via _performWithFallbackEnvironment:block:, which calls
//  os_log → dyld_image_path_containing_address in iOS 26 simulator — extremely slow.
//  Fix: use UIButton(type:.custom) with hardcoded colors as customView bar items.
//

import UIKit
import LoomitOfferwallCore

// MARK: - Section model

private enum Section: Int, CaseIterable {
    case app = 0
    case dsAdded = 1
    case pending = 2

    var title: String {
        switch self {
        case .app:     return "App Properties"
        case .dsAdded: return "DS-Added"
        case .pending: return "Pending Rules"
        }
    }

    var footer: String? {
        switch self {
        case .app:     return "Properties set by the publisher. Tap to override or inhibit."
        case .dsAdded: return "Injected by the Debug Suite. Not present in the publisher\u{2019}s app."
        case .pending: return "Rules saved on disk. Will apply automatically when the publisher loads these properties."
        }
    }
}

@MainActor
final class CustomPropertiesViewController: UIViewController {

    private weak var collector: DebugDataCollector?
    private var pendingTask: Task<Void, Never>?
    private var notificationObserver: NSObjectProtocol?

    // Sectioned data
    private var appProps:     [DebugCustomProperty] = []
    private var dsAddedProps: [DebugCustomProperty] = []
    private var pendingProps: [DebugCustomProperty] = []

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tv.dataSource = self
        tv.delegate = self
        return tv
    }()

    private lazy var emptyLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.text = "No custom properties set.\nUse \"+\" to inject debug-only extras."
        l.textAlignment = .center
        l.numberOfLines = 0
        l.font = UIFont.systemFont(ofSize: 14)
        l.textColor = UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        l.isHidden = true
        return l
    }()

    init(collector: DebugDataCollector?) {
        self.collector = collector
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        view.addSubview(tableView)
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
        setupNavButtons()
    }

    private func setupNavButtons() {
        // UIBarButtonItem(style:.plain) uses adaptive tintColor → triggers _performWithFallbackEnvironment
        // in iOS 26 simulator → extremely slow. Use UIButton(type:.custom) with hardcoded colors.
        let addBtn = UIButton(type: .custom)
        addBtn.setTitle("+", for: .normal)
        addBtn.titleLabel?.font = UIFont.systemFont(ofSize: 22, weight: .light)
        addBtn.setTitleColor(UIColor(red: 0.2, green: 0.2, blue: 0.8, alpha: 1), for: .normal)
        addBtn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)
        addBtn.addTarget(self, action: #selector(addProperty), for: .touchUpInside)

        let clearBtn = UIButton(type: .custom)
        clearBtn.setTitle("Clear All", for: .normal)
        clearBtn.titleLabel?.font = UIFont.systemFont(ofSize: 14)
        clearBtn.setTitleColor(UIColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1), for: .normal)
        clearBtn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)
        clearBtn.addTarget(self, action: #selector(clearAll), for: .touchUpInside)

        // Separate items so they don't look like a single tappable block
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(customView: clearBtn),
            UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil),
            UIBarButtonItem(customView: addBtn)
        ]
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .debugDataUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.loadData() }
        }
        loadData()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        pendingTask?.cancel()
        if let obs = notificationObserver {
            NotificationCenter.default.removeObserver(obs)
            notificationObserver = nil
        }
    }

    deinit {
        pendingTask?.cancel()
        if let obs = notificationObserver { NotificationCenter.default.removeObserver(obs) }
    }

    private func loadData() {
        pendingTask?.cancel()
        pendingTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            let state = await self.collector?.getCustomPropertyDebugState() ?? [:]
            guard !Task.isCancelled else { return }
            let all = state.values.sorted { $0.key < $1.key }
            self.appProps     = all.filter { !$0.isPending && !($0.originalValue.isEmpty && $0.isOverridden) }
            self.dsAddedProps = all.filter { !$0.isPending && $0.originalValue.isEmpty && $0.isOverridden }
            self.pendingProps = all.filter { $0.isPending }
            let empty = all.isEmpty
            self.tableView.isHidden = empty
            self.emptyLabel.isHidden = !empty
            self.tableView.reloadData()
        }
    }

    @objc private func addProperty() {
        let alert = UIAlertController(title: "Add Property", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Key" }
        alert.addTextField { $0.placeholder = "Value" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            // Force resign first responder to fix keyboard memory issues
            alert.textFields?.forEach { $0.resignFirstResponder() }
        })
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self] _ in
            // Capture text field values before resigning
            let key   = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let value = alert.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Force resign first responder to fix keyboard memory issues
            alert.textFields?.forEach { $0.resignFirstResponder() }
            guard !key.isEmpty, !value.isEmpty else { return }
            Task { [weak self] in
                await self?.collector?.setCustomPropertyOverride(key, value: value)
                await MainActor.run { self?.loadData() }
            }
        })
        present(alert, animated: true)
    }

    @objc private func clearAll() {
        let confirm = UIAlertController(title: "Clear All Overrides", message: nil, preferredStyle: .alert)
        confirm.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        confirm.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            Task { [weak self] in
                await self?.collector?.clearCustomPropertyOverrides()
                await MainActor.run { self?.loadData() }
            }
        })
        present(confirm, animated: true)
    }

    // MARK: - Helpers

    private func prop(at indexPath: IndexPath) -> DebugCustomProperty? {
        switch Section(rawValue: indexPath.section) {
        case .app:     return appProps.indices.contains(indexPath.row)     ? appProps[indexPath.row]     : nil
        case .dsAdded: return dsAddedProps.indices.contains(indexPath.row) ? dsAddedProps[indexPath.row] : nil
        case .pending: return pendingProps.indices.contains(indexPath.row) ? pendingProps[indexPath.row] : nil
        case .none:    return nil
        }
    }

    /// Inline badge label: small pill with text and background color.
    private func makeBadge(text: String, color: UIColor) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        let container = UIView()
        container.backgroundColor = color
        container.layer.cornerRadius = 4
        container.clipsToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -5)
        ])
        return container
    }

    private func configureAppCell(_ cell: UITableViewCell, prop: DebugCustomProperty) {
        var cfg = cell.defaultContentConfiguration()
        cfg.text = prop.key
        cfg.secondaryText = prop.isInhibited ? prop.originalValue : prop.currentValue
        if prop.isInhibited {
            cfg.secondaryTextProperties.color = UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
            cfg.textProperties.color = UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        } else if prop.isOverridden {
            cfg.secondaryText = "\(prop.currentValue)  \u{2190} \(prop.originalValue)"
            cfg.secondaryTextProperties.color = UIColor(red: 0, green: 0.4, blue: 0.8, alpha: 1)
        } else {
            cfg.secondaryTextProperties.color = UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1)
        }
        cell.contentConfiguration = cfg

        // Remove previous badge stack if any
        cell.accessoryView = nil
        cell.accessoryType = .none

        var badges: [UIView] = []
        if prop.isInhibited {
            badges.append(makeBadge(text: "INHIBITED", color: UIColor(red: 0.8, green: 0.35, blue: 0, alpha: 1)))
        } else if prop.isOverridden {
            badges.append(makeBadge(text: "OVERRIDDEN", color: UIColor(red: 0.1, green: 0.4, blue: 0.85, alpha: 1)))
        }

        if badges.isEmpty {
            cell.accessoryType = .disclosureIndicator
        } else {
            let stack = UIStackView(arrangedSubviews: badges)
            stack.axis = .horizontal
            stack.spacing = 4
            stack.alignment = .center
            // Add chevron after badges
            let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
            chevron.tintColor = UIColor(red: 0.78, green: 0.78, blue: 0.8, alpha: 1)
            chevron.contentMode = .scaleAspectFit
            chevron.translatesAutoresizingMaskIntoConstraints = false
            chevron.widthAnchor.constraint(equalToConstant: 8).isActive = true
            stack.addArrangedSubview(chevron)
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.sizeToFit()
            cell.accessoryView = stack
        }
    }
}

// MARK: - UITableViewDataSource

extension CustomPropertiesViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .app:     return appProps.count
        case .dsAdded: return dsAddedProps.count
        case .pending: return pendingProps.count
        case .none:    return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let s = Section(rawValue: section) else { return nil }
        let count: Int
        switch s {
        case .app:     count = appProps.count
        case .dsAdded: count = dsAddedProps.count
        case .pending: count = pendingProps.count
        }
        guard count > 0 else { return nil }
        return "\(s.title) (\(count))"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let s = Section(rawValue: section) else { return nil }
        let count: Int
        switch s {
        case .app:     count = appProps.count
        case .dsAdded: count = dsAddedProps.count
        case .pending: count = pendingProps.count
        }
        return count > 0 ? s.footer : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        guard let p = prop(at: indexPath) else { return cell }

        switch Section(rawValue: indexPath.section) {
        case .app:
            configureAppCell(cell, prop: p)

        case .dsAdded:
            var cfg = cell.defaultContentConfiguration()
            cfg.text = p.key
            cfg.secondaryText = p.currentValue
            cfg.secondaryTextProperties.color = UIColor(red: 0, green: 0.5, blue: 0.3, alpha: 1)
            cell.contentConfiguration = cfg
            cell.accessoryView = nil
            cell.accessoryType = .disclosureIndicator

        case .pending:
            var cfg = cell.defaultContentConfiguration()
            cfg.text = p.key
            cfg.textProperties.color = UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
            if p.isInhibited {
                cfg.secondaryText = "Will be inhibited when loaded"
            } else {
                cfg.secondaryText = "Will be overridden to \u{201C}\(p.currentValue)\u{201D}"
            }
            cfg.secondaryTextProperties.color = UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
            cell.contentConfiguration = cfg

            let badgeColor = p.isInhibited
                ? UIColor(red: 0.7, green: 0.35, blue: 0, alpha: 1)
                : UIColor(red: 0.3, green: 0.3, blue: 0.7, alpha: 1)
            let badge = makeBadge(text: "PENDING", color: badgeColor)
            badge.translatesAutoresizingMaskIntoConstraints = false
            cell.accessoryView = badge
            cell.accessoryType = .none

        case .none:
            break
        }

        return cell
    }
}

// MARK: - UITableViewDelegate

extension CustomPropertiesViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let p = prop(at: indexPath) else { return }

        switch Section(rawValue: indexPath.section) {

        case .app:
            let sheet = UIAlertController(title: p.key, message: nil, preferredStyle: .actionSheet)
            if p.isInhibited {
                sheet.addAction(UIAlertAction(title: "Restore", style: .default) { [weak self] _ in
                    Task { [weak self] in
                        await self?.collector?.setCustomPropertyInhibited(p.key, inhibited: false)
                        await MainActor.run { self?.loadData() }
                    }
                })
            } else {
                sheet.addAction(UIAlertAction(title: "Override", style: .default) { [weak self] _ in
                    self?.showEditAlert(for: p)
                })
                sheet.addAction(UIAlertAction(title: "Inhibit", style: .destructive) { [weak self] _ in
                    Task { [weak self] in
                        await self?.collector?.setCustomPropertyInhibited(p.key, inhibited: true)
                        await MainActor.run { self?.loadData() }
                    }
                })
                if p.isOverridden {
                    sheet.addAction(UIAlertAction(title: "Clear Override", style: .default) { [weak self] _ in
                        Task { [weak self] in
                            await self?.collector?.setCustomPropertyOverride(p.key, value: nil)
                            await MainActor.run { self?.loadData() }
                        }
                    })
                }
            }
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            popoverIfNeeded(sheet, at: indexPath)
            present(sheet, animated: true)

        case .dsAdded:
            let sheet = UIAlertController(title: p.key, message: nil, preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: "Edit", style: .default) { [weak self] _ in
                self?.showEditAlert(for: p)
            })
            sheet.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
                Task { [weak self] in
                    await self?.collector?.setCustomPropertyOverride(p.key, value: nil)
                    await MainActor.run { self?.loadData() }
                }
            })
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            popoverIfNeeded(sheet, at: indexPath)
            present(sheet, animated: true)

        case .pending:
            let sheet = UIAlertController(
                title: p.key,
                message: "Rule saved on disk. Will apply when the publisher loads this property.",
                preferredStyle: .actionSheet
            )
            sheet.addAction(UIAlertAction(title: "Clear Rule", style: .destructive) { [weak self] _ in
                Task { [weak self] in
                    await self?.collector?.setCustomPropertyOverride(p.key, value: nil)
                    await MainActor.run { self?.loadData() }
                }
            })
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            popoverIfNeeded(sheet, at: indexPath)
            present(sheet, animated: true)

        case .none:
            break
        }
    }

    private func popoverIfNeeded(_ alert: UIAlertController, at indexPath: IndexPath) {
        guard let pop = alert.popoverPresentationController else { return }
        let cell = tableView.cellForRow(at: indexPath)
        pop.sourceView = cell ?? view
        pop.sourceRect = cell?.bounds ?? view.bounds
    }

    private func showEditAlert(for prop: DebugCustomProperty) {
        let alert = UIAlertController(title: prop.key, message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = prop.currentValue
            tf.placeholder = "New value"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            // Force resign first responder to fix keyboard memory issues
            alert.textFields?.forEach { $0.resignFirstResponder() }
        })
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            // Capture text field value before resigning
            let newValue = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Force resign first responder to fix keyboard memory issues
            alert.textFields?.forEach { $0.resignFirstResponder() }
            guard !newValue.isEmpty else { return }
            Task { [weak self] in
                await self?.collector?.setCustomPropertyOverride(prop.key, value: newValue)
                await MainActor.run { self?.loadData() }
            }
        })
        present(alert, animated: true)
    }
}
