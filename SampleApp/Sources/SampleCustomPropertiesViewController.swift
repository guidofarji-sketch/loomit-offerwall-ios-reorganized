//
//  SampleCustomPropertiesViewController.swift
//  LoomitOfferwallSampleApp
//
//  Pantalla para gestionar custom properties del publisher en el sample app.
//  Paridad con Android CustomPropertiesActivity + CustomPropertiesStore.
//

import UIKit

@MainActor
final class SampleCustomPropertiesViewController: UIViewController {

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(PropertyRowCell.self, forCellReuseIdentifier: PropertyRowCell.reuseId)
        tv.dataSource = self
        tv.rowHeight = UITableView.automaticDimension
        tv.estimatedRowHeight = 80
        tv.keyboardDismissMode = .onDrag
        return tv
    }()

    private lazy var saveButton: UIBarButtonItem = UIBarButtonItem(
        title: "Save",
        style: .done,
        target: self,
        action: #selector(didTapSave)
    )

    private lazy var addButton: UIBarButtonItem = UIBarButtonItem(
        barButtonSystemItem: .add,
        target: self,
        action: #selector(didTapAdd)
    )

    private var entries: [CustomPropertiesStore.Entry] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Custom Properties"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(didTapCancel)
        )
        navigationItem.rightBarButtonItems = [saveButton, addButton]

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        entries = CustomPropertiesStore.load()
        if entries.isEmpty { entries.append(.init(key: "", value: "")) }
        tableView.reloadData()
    }

    @objc private func didTapAdd() {
        entries.append(.init(key: "", value: ""))
        let indexPath = IndexPath(row: entries.count - 1, section: 0)
        tableView.insertRows(at: [indexPath], with: .automatic)
        if let cell = tableView.cellForRow(at: indexPath) as? PropertyRowCell {
            cell.focusKey()
        }
    }

    @objc private func didTapSave() {
        view.endEditing(true)
        collectCurrentValues()
        Task {
            await CustomPropertiesStore.save(entries)
            await MainActor.run {
                navigationController?.dismiss(animated: true)
            }
        }
    }

    @objc private func didTapCancel() {
        dismiss(animated: true)
    }

    private func collectCurrentValues() {
        for (i, _) in entries.enumerated() {
            if let cell = tableView.cellForRow(at: IndexPath(row: i, section: 0)) as? PropertyRowCell {
                entries[i] = cell.currentEntry()
            }
        }
    }
}

// MARK: - UITableViewDataSource

extension SampleCustomPropertiesViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        entries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: PropertyRowCell.reuseId, for: indexPath) as? PropertyRowCell else {
            return UITableViewCell()
        }
        cell.configure(with: entries[indexPath.row]) { [weak self] in
            self?.entries.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Key / Value pairs sent with every config request"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Tap Save to persist and apply to SDK. Changes take effect on next Fetch Config."
    }
}

// MARK: - PropertyRowCell

private final class PropertyRowCell: UITableViewCell {
    static let reuseId = "PropertyRowCell"

    private let keyField: UITextField = {
        let tf = UITextField()
        tf.placeholder = "Key"
        tf.borderStyle = .roundedRect
        tf.autocorrectionType = .no
        tf.autocapitalizationType = .none
        tf.font = .systemFont(ofSize: 14)
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()

    private let valueField: UITextField = {
        let tf = UITextField()
        tf.placeholder = "Value"
        tf.borderStyle = .roundedRect
        tf.autocorrectionType = .no
        tf.autocapitalizationType = .none
        tf.font = .systemFont(ofSize: 14)
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()

    private lazy var removeButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "minus.circle.fill"), for: .normal)
        btn.tintColor = .systemRed
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)
        return btn
    }()

    private var onRemove: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        let stack = UIStackView(arrangedSubviews: [keyField, valueField, removeButton])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        removeButton.widthAnchor.constraint(equalToConstant: 28).isActive = true

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with entry: CustomPropertiesStore.Entry, onRemove: @escaping () -> Void) {
        self.onRemove = onRemove
        keyField.text = entry.key
        valueField.text = entry.value
    }

    func currentEntry() -> CustomPropertiesStore.Entry {
        .init(key: keyField.text ?? "", value: valueField.text ?? "")
    }

    func focusKey() { keyField.becomeFirstResponder() }

    @objc private func removeTapped() { onRemove?() }
}
