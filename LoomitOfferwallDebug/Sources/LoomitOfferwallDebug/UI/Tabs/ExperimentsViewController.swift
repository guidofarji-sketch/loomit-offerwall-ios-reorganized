//
//  ExperimentsViewController.swift
//  LoomitOfferwallDebug
//
//  Tab de Experiments: visualizar y overridear experimentos A/B.
//  Paridad con Android ExperimentsFragment.kt
//

import UIKit
import LoomitOfferwallCore

@MainActor
final class ExperimentsViewController: UIViewController {

    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private lazy var contentView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var abTestCard: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .secondarySystemGroupedBackground
        v.layer.cornerRadius = 12
        v.layer.masksToBounds = true
        return v
    }()

    private lazy var abTestHeader: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 17, weight: .semibold)
        l.textColor = .label
        return l
    }()

    private lazy var abTestName: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 15, weight: .medium)
        l.textColor = .label
        return l
    }()

    private lazy var abTestGroup: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 13)
        l.textColor = .secondaryLabel
        l.numberOfLines = 0
        return l
    }()

    private lazy var abTestId: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 12)
        l.textColor = .tertiaryLabel
        return l
    }()

    private lazy var assignmentModeLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 14, weight: .medium)
        l.textColor = .label
        l.text = "Assignment Mode"
        return l
    }()

    private lazy var backendAssignmentOption: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.setTitle("Backend Assignment (Server Side)", for: .normal)
        b.setImage(UIImage(systemName: "circle"), for: .normal)
        b.setImage(UIImage(systemName: "circle.fill"), for: .selected)
        b.contentHorizontalAlignment = .left
        b.titleEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)
        return b
    }()

    private lazy var manualAssignmentOption: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.setTitle("Manual Assignment (Client Side)", for: .normal)
        b.setImage(UIImage(systemName: "circle"), for: .normal)
        b.setImage(UIImage(systemName: "circle.fill"), for: .selected)
        b.contentHorizontalAlignment = .left
        b.titleEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)
        return b
    }()

    private lazy var manualGroupContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        return v
    }()

    private lazy var manualGroupLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 13)
        l.textColor = .secondaryLabel
        l.text = "Force Group:"
        return l
    }()

    private lazy var manualGroupToggle: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["A", "B"])
        sc.translatesAutoresizingMaskIntoConstraints = false
        sc.selectedSegmentIndex = UISegmentedControl.noSegment
        return sc
    }()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private lazy var emptyState: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.text = "No experiments active"
        l.textAlignment = .center
        l.textColor = .secondaryLabel
        l.font = .systemFont(ofSize: 16)
        l.isHidden = true
        return l
    }()

    private let collector: DebugDataCollector
    private var experiments: [OfferwallSdk.ExperimentAssignment] = []
    private var overrides: [String: String] = [:]
    private var activeExperiment: OfferwallSdk.ExperimentAssignment?

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
        loadExperiments()
    }

    private func setupUI() {
        view.backgroundColor = .systemGroupedBackground

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(abTestCard)
        contentView.addSubview(tableView)
        contentView.addSubview(emptyState)

        abTestCard.addSubview(abTestHeader)
        abTestCard.addSubview(abTestName)
        abTestCard.addSubview(abTestGroup)
        abTestCard.addSubview(abTestId)
        abTestCard.addSubview(assignmentModeLabel)
        abTestCard.addSubview(backendAssignmentOption)
        abTestCard.addSubview(manualAssignmentOption)
        abTestCard.addSubview(manualGroupContainer)
        manualGroupContainer.addSubview(manualGroupLabel)
        manualGroupContainer.addSubview(manualGroupToggle)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            abTestCard.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            abTestCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            abTestCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            abTestHeader.topAnchor.constraint(equalTo: abTestCard.topAnchor, constant: 12),
            abTestHeader.leadingAnchor.constraint(equalTo: abTestCard.leadingAnchor, constant: 12),
            abTestHeader.trailingAnchor.constraint(equalTo: abTestCard.trailingAnchor, constant: -12),

            abTestName.topAnchor.constraint(equalTo: abTestHeader.bottomAnchor, constant: 8),
            abTestName.leadingAnchor.constraint(equalTo: abTestCard.leadingAnchor, constant: 12),
            abTestName.trailingAnchor.constraint(equalTo: abTestCard.trailingAnchor, constant: -12),

            abTestGroup.topAnchor.constraint(equalTo: abTestName.bottomAnchor, constant: 4),
            abTestGroup.leadingAnchor.constraint(equalTo: abTestCard.leadingAnchor, constant: 12),
            abTestGroup.trailingAnchor.constraint(equalTo: abTestCard.trailingAnchor, constant: -12),

            abTestId.topAnchor.constraint(equalTo: abTestGroup.bottomAnchor, constant: 4),
            abTestId.leadingAnchor.constraint(equalTo: abTestCard.leadingAnchor, constant: 12),
            abTestId.trailingAnchor.constraint(equalTo: abTestCard.trailingAnchor, constant: -12),

            assignmentModeLabel.topAnchor.constraint(equalTo: abTestId.bottomAnchor, constant: 16),
            assignmentModeLabel.leadingAnchor.constraint(equalTo: abTestCard.leadingAnchor, constant: 12),
            assignmentModeLabel.trailingAnchor.constraint(equalTo: abTestCard.trailingAnchor, constant: -12),

            backendAssignmentOption.topAnchor.constraint(equalTo: assignmentModeLabel.bottomAnchor, constant: 8),
            backendAssignmentOption.leadingAnchor.constraint(equalTo: abTestCard.leadingAnchor, constant: 12),
            backendAssignmentOption.trailingAnchor.constraint(equalTo: abTestCard.trailingAnchor, constant: -12),

            manualAssignmentOption.topAnchor.constraint(equalTo: backendAssignmentOption.bottomAnchor, constant: 8),
            manualAssignmentOption.leadingAnchor.constraint(equalTo: abTestCard.leadingAnchor, constant: 12),
            manualAssignmentOption.trailingAnchor.constraint(equalTo: abTestCard.trailingAnchor, constant: -12),

            manualGroupContainer.topAnchor.constraint(equalTo: manualAssignmentOption.bottomAnchor, constant: 8),
            manualGroupContainer.leadingAnchor.constraint(equalTo: abTestCard.leadingAnchor, constant: 12),
            manualGroupContainer.trailingAnchor.constraint(equalTo: abTestCard.trailingAnchor, constant: -12),
            manualGroupContainer.bottomAnchor.constraint(equalTo: abTestCard.bottomAnchor, constant: -12),

            manualGroupLabel.topAnchor.constraint(equalTo: manualGroupContainer.topAnchor),
            manualGroupLabel.leadingAnchor.constraint(equalTo: manualGroupContainer.leadingAnchor),
            manualGroupLabel.trailingAnchor.constraint(equalTo: manualGroupContainer.trailingAnchor),

            manualGroupToggle.topAnchor.constraint(equalTo: manualGroupLabel.bottomAnchor, constant: 8),
            manualGroupToggle.leadingAnchor.constraint(equalTo: manualGroupContainer.leadingAnchor),
            manualGroupToggle.trailingAnchor.constraint(equalTo: manualGroupContainer.trailingAnchor),
            manualGroupToggle.bottomAnchor.constraint(equalTo: manualGroupContainer.bottomAnchor),

            tableView.topAnchor.constraint(equalTo: abTestCard.bottomAnchor, constant: 16),
            tableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            emptyState.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        backendAssignmentOption.addTarget(self, action: #selector(backendAssignmentTapped), for: .touchUpInside)
        manualAssignmentOption.addTarget(self, action: #selector(manualAssignmentTapped), for: .touchUpInside)
        manualGroupToggle.addTarget(self, action: #selector(manualGroupChanged), for: .valueChanged)
    }

    private func setupNavigation() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(refreshExperiments)
        )
    }

    private func loadExperiments() {
        Task {
            experiments = await collector.getExperimentAssignments()
            overrides = await collector.getExperimentOverrides()
            activeExperiment = experiments.first { $0.isActive }
            tableView.reloadData()
            updateABTestCard()
        }
    }

    private func updateABTestCard() {
        guard let exp = activeExperiment else {
            abTestCard.isHidden = true
            tableView.isHidden = false
            emptyState.isHidden = !experiments.isEmpty
            return
        }

        abTestCard.isHidden = false
        tableView.isHidden = false
        emptyState.isHidden = true

        let experimentId = exp.rawPayload["experiment_id"] as? String
            ?? exp.rawPayload["id"] as? String
            ?? "N/A"

        abTestName.text = exp.name
        let currentOverride = overrides[exp.name]
        abTestHeader.text = currentOverride != nil ? "🔬 ACTIVE A/B TEST (Manual)" : "🔬 ACTIVE A/B TEST (Backend)"

        let normalizedBackend = exp.group?.uppercased()
        let normalizedOverride = currentOverride?.uppercased()

        abTestGroup.text = if normalizedOverride != nil {
            "Grupo backend: \(normalizedBackend ?? "N/A")\nOverride manual: \(normalizedOverride!)"
        } else {
            "Grupo backend: \(normalizedBackend ?? "N/A")"
        }

        abTestId.text = "ID: \(experimentId)"

        // Update radio buttons
        let manualSelected = normalizedOverride != nil
        backendAssignmentOption.isSelected = !manualSelected
        manualAssignmentOption.isSelected = manualSelected
        manualGroupContainer.isHidden = !manualSelected

        // Update toggle
        manualGroupToggle.selectedSegmentIndex = UISegmentedControl.noSegment
        if let override = normalizedOverride {
            if override == "A" {
                manualGroupToggle.selectedSegmentIndex = 0
            } else if override == "B" {
                manualGroupToggle.selectedSegmentIndex = 1
            }
        }
    }

    @objc private func refreshExperiments() {
        loadExperiments()
    }

    @objc private func backendAssignmentTapped() {
        guard let exp = activeExperiment else { return }
        backendAssignmentOption.isSelected = true
        manualAssignmentOption.isSelected = false
        manualGroupContainer.isHidden = true
        manualGroupToggle.selectedSegmentIndex = UISegmentedControl.noSegment

        Task {
            await collector.setExperimentOverride(experimentName: exp.name, group: nil)
            loadExperiments()
        }
    }

    @objc private func manualAssignmentTapped() {
        guard let exp = activeExperiment else { return }
        backendAssignmentOption.isSelected = false
        manualAssignmentOption.isSelected = true
        manualGroupContainer.isHidden = false

        if manualGroupToggle.selectedSegmentIndex == UISegmentedControl.noSegment {
            // Select A by default
            manualGroupToggle.selectedSegmentIndex = 0
            Task {
                await collector.setExperimentOverride(experimentName: exp.name, group: "A")
                loadExperiments()
            }
        }
    }

    @objc private func manualGroupChanged() {
        guard let exp = activeExperiment else { return }
        let group = manualGroupToggle.selectedSegmentIndex == 0 ? "A" : "B"
        Task {
            await collector.setExperimentOverride(experimentName: exp.name, group: group)
            loadExperiments()
        }
    }
}

// MARK: - UITableViewDataSource

extension ExperimentsViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return experiments.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "ExperimentCell")
        let exp = experiments[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = exp.name

        // Group
        if exp.group != nil {
            config.secondaryText = "Group: \(exp.group!)"
        } else {
            config.secondaryText = "Group: Not assigned"
        }

        // Status badge
        let currentOverride = overrides[exp.name]
        if let override = currentOverride {
            config.secondaryText = (config.secondaryText ?? "") + " | Override: " + override
            cell.accessoryType = .detailButton
            cell.tintColor = .systemOrange
        } else {
            cell.accessoryType = .detailButton
            cell.tintColor = exp.isActive ? .systemGreen : .systemGray
        }
        config.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = config

        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "All Experiments"
    }
}

// MARK: - UITableViewDelegate

extension ExperimentsViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        let exp = experiments[indexPath.row]
        let currentOverride = overrides[exp.name]

        if currentOverride != nil {
            // Clear override
            showClearOverrideDialog(experimentName: exp.name)
        } else {
            // Show force group dialog (like Android)
            showForceGroupDialog(experimentName: exp.name)
        }
    }

    private func showForceGroupDialog(experimentName: String) {
        let alert = UIAlertController(
            title: "Force Experiment Group",
            message: "Enter the group to force for '\(experimentName)':",
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.placeholder = "e.g., A, B, control"
        }

        alert.addAction(UIAlertAction(title: "Apply", style: .default) { [weak self] _ in
            // Capture value before resigning
            guard let self = self,
                  let groupName = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !groupName.isEmpty else {
                // Force resign even on early exit
                alert.textFields?.forEach { $0.resignFirstResponder() }
                return
            }
            // Force resign first responder to fix keyboard memory issues
            alert.textFields?.forEach { $0.resignFirstResponder() }
            Task {
                await self.collector.setExperimentOverride(experimentName: experimentName, group: groupName)
                self.loadExperiments()
            }
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            // Force resign first responder to fix keyboard memory issues
            alert.textFields?.forEach { $0.resignFirstResponder() }
        })

        present(alert, animated: true)
    }

    private func showClearOverrideDialog(experimentName: String) {
        let alert = UIAlertController(
            title: "Clear Override",
            message: "Clear override for '\(experimentName)'?",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            Task {
                await self?.collector.setExperimentOverride(experimentName: experimentName, group: nil)
                self?.loadExperiments()
            }
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        present(alert, animated: true)
    }
}
