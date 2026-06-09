//
//  DependenciesViewController.swift
//  LoomitOfferwallDebug
//
//  Tab de Dependencies: verificación de SDKs nativos de proveedores.
//

import UIKit

@MainActor
final class DependenciesViewController: UIViewController {
    
    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()
    
    private var dependencies: [DependencyInfo] = []
    
    struct DependencyInfo {
        let providerName: String
        let sdkName: String
        let adapterClass: String
        let adapterStatus: DependencyStatus
        let requiredClass: String?
        let sdkStatus: DependencyStatus
        let version: String?
        let errorMessage: String?
        let isService: Bool
    }
    
    enum DependencyStatus: String {
        case ok = "OK"
        case missing = "MISSING"
        case unknown = "UNKNOWN"
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNavigation()
        tableView.dataSource = self
        tableView.delegate = self
        loadDependencies()
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
            action: #selector(refreshDependencies)
        )
    }
    
    private func loadDependencies() {
        // Known iOS provider dependencies
        let knownDependencies: [(providerName: String, sdkName: String, adapterClass: String, requiredClass: String?, versionClass: String?, versionMethod: String?)] = [
            ("Tapjoy", "Tapjoy iOS SDK", "LoomitOfferwallAdapterTapjoy.TapjoyAdapter", "Tapjoy", "Tapjoy", "getVersion"),
            ("Digital Turbine", "FairBid SDK", "LoomitOfferwallAdapterDT.DTAdapter", "Fyber.FairBid", "Fyber.FairBid", "getVersion"),
            ("Ayet", "Ayet Publisher SDK", "LoomitOfferwallAdapterAyet.AyetAdapter", "AyetSdk", nil, nil),
            ("Playtime", "Adjoe Playtime iOS SDK", "LoomitOfferwallAdapterPlaytime.PlaytimeAdapter", "Adjoe.Playtime", "Adjoe.Playtime", "getVersion"),
            ("Xsolla", "N/A (WebView-based)", "LoomitOfferwallAdapterXsolla.XsollaAdapter", nil, nil, nil),
            ("Tyrads", "Tyrads iOS SDK", "LoomitOfferwallAdapterTyrads.TyradsAdapter", "Tyrads.Tyrads", nil, nil),
            ("MyChips", "MyChips Offerwall SDK", "LoomitOfferwallAdapterMyChips.MyChipsAdapter", "MyChipsSdk.MCOfferwallSDK", nil, nil),
        ]
        
        // Known Loomit services
        let knownServices: [(serviceName: String, displayName: String, requiredClass: String, versionField: String?)] = [
            ("Loomit Antifraud", "Anti-Fraud Protection", "LoomitAntifraud.LoomitAntifraud", "VERSION"),
        ]
        
        var results: [DependencyInfo] = []
        
        // Check provider dependencies
        for dep in knownDependencies {
            let result = checkProviderDependency(
                providerName: dep.providerName,
                sdkName: dep.sdkName,
                adapterClass: dep.adapterClass,
                requiredClass: dep.requiredClass,
                versionClass: dep.versionClass,
                versionMethod: dep.versionMethod
            )
            results.append(result)
        }
        
        // Check service dependencies
        for service in knownServices {
            let result = checkServiceDependency(
                serviceName: service.serviceName,
                displayName: service.displayName,
                requiredClass: service.requiredClass,
                versionField: service.versionField
            )
            results.append(result)
        }
        
        dependencies = results
        tableView.reloadData()
    }
    
    private func checkProviderDependency(
        providerName: String,
        sdkName: String,
        adapterClass: String,
        requiredClass: String?,
        versionClass: String?,
        versionMethod: String?
    ) -> DependencyInfo {
        // Check adapter first (always required)
        let adapterStatus = checkClassAvailability(className: adapterClass)
        
        // Check SDK (not required for Xsolla)
        let (sdkStatus, version, errorMsg): (DependencyStatus, String?, String?)
        if requiredClass == nil {
            // Xsolla doesn't need SDK
            (sdkStatus, version, errorMsg) = (.ok, nil, nil)
        } else {
            let result = checkSdkAvailability(
                requiredClass: requiredClass!,
                versionClass: versionClass,
                versionMethod: versionMethod
            )
            (sdkStatus, version, errorMsg) = result
        }
        
        return DependencyInfo(
            providerName: providerName,
            sdkName: sdkName,
            adapterClass: adapterClass,
            adapterStatus: adapterStatus,
            requiredClass: requiredClass,
            sdkStatus: sdkStatus,
            version: version,
            errorMessage: errorMsg,
            isService: false
        )
    }
    
    private func checkServiceDependency(
        serviceName: String,
        displayName: String,
        requiredClass: String,
        versionField: String?
    ) -> DependencyInfo {
        let (sdkStatus, version, errorMsg) = checkSdkAvailability(
            requiredClass: requiredClass,
            versionClass: requiredClass,
            versionMethod: nil  // Services use field, not method
        )
        
        return DependencyInfo(
            providerName: serviceName,
            sdkName: displayName,
            adapterClass: "N/A",
            adapterStatus: .ok,  // N/A for services
            requiredClass: requiredClass,
            sdkStatus: sdkStatus,
            version: version,
            errorMessage: errorMsg,
            isService: true
        )
    }
    
    private func checkClassAvailability(className: String) -> DependencyStatus {
        // Try to get the class from runtime
        let classParts = className.split(separator: ".")
        if classParts.count > 1 {
            // Module.ClassName format
            let moduleName = String(classParts[0])
            let classOnly = String(classParts[1])
            if NSClassFromString("\(moduleName).\(classOnly)") != nil {
                return .ok
            }
        }
        
        // Try plain class name
        if NSClassFromString(className) != nil {
            return .ok
        }
        
        return .missing
    }
    
    private func checkSdkAvailability(
        requiredClass: String,
        versionClass: String?,
        versionMethod: String?
    ) -> (DependencyStatus, String?, String?) {
        // Try to load the SDK class
        guard let _ = NSClassFromString(requiredClass) else {
            return (.missing, nil, "SDK not in classpath")
        }
        
        // Try to get version if available
        if let versionClass = versionClass, let versionMethod = versionMethod {
            if let cls = NSClassFromString(versionClass) as? NSObject.Type {
                let selector = NSSelectorFromString(versionMethod)
                if cls.responds(to: selector) {
                    if let version = cls.perform(selector).takeUnretainedValue() as? String {
                        return (.ok, version, nil)
                    }
                }
            }
        }
        
        return (.ok, nil, nil)
    }
    
    @objc private func refreshDependencies() {
        loadDependencies()
    }
}

// MARK: - UITableViewDataSource

extension DependenciesViewController: UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return dependencies.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: "DependencyCell")
        cell.selectionStyle = .none
        
        let dep = dependencies[indexPath.row]
        
        // Limpiar vistas previas
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        
        // Status Icon (izquierda) - como Android
        let statusIcon = UIImageView()
        statusIcon.contentMode = .scaleAspectFit
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(statusIcon)
        
        // Determinar icono y color principal
        let overallStatus = dep.isService ? dep.sdkStatus : 
            (dep.adapterStatus == .ok ? dep.sdkStatus : dep.adapterStatus)
        
        switch overallStatus {
        case .ok:
            statusIcon.image = UIImage(systemName: "checkmark.circle.fill")
            statusIcon.tintColor = UIColor(red: 0.30, green: 0.69, blue: 0.31, alpha: 1.0) // #4CAF50
        case .missing:
            statusIcon.image = UIImage(systemName: "xmark.circle.fill")
            statusIcon.tintColor = UIColor(red: 0.96, green: 0.26, blue: 0.21, alpha: 1.0) // #F44336
        case .unknown:
            statusIcon.image = UIImage(systemName: "questionmark.circle.fill")
            statusIcon.tintColor = UIColor(red: 0.95, green: 0.61, blue: 0.07, alpha: 1.0) // #FF9800
        }
        
        // Contenedor central para texto (como Android)
        let textContainer = UIStackView()
        textContainer.axis = .vertical
        textContainer.spacing = 2
        textContainer.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(textContainer)
        
        // Provider Name
        let providerLabel = UILabel()
        providerLabel.text = dep.providerName
        providerLabel.font = .systemFont(ofSize: 16, weight: .bold)
        providerLabel.textColor = UIColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1.0) // #212121
        textContainer.addArrangedSubview(providerLabel)
        
        // SDK Name
        let sdkLabel = UILabel()
        sdkLabel.text = dep.sdkName
        sdkLabel.font = .systemFont(ofSize: 12)
        sdkLabel.textColor = UIColor(red: 0.46, green: 0.46, blue: 0.46, alpha: 1.0) // #757575
        textContainer.addArrangedSubview(sdkLabel)
        
        // Adapter Status
        let adapterStatusLabel = UILabel()
        adapterStatusLabel.font = .systemFont(ofSize: 11)
        if dep.isService {
            adapterStatusLabel.text = "Service (optional)"
            adapterStatusLabel.textColor = UIColor(red: 0.33, green: 0.33, blue: 0.33, alpha: 1.0) // #555555
        } else {
            switch dep.adapterStatus {
            case .ok:
                adapterStatusLabel.text = "Adapter: \u{2713} OK"
                adapterStatusLabel.textColor = UIColor(red: 0.30, green: 0.69, blue: 0.31, alpha: 1.0) // #4CAF50
            case .missing:
                adapterStatusLabel.text = "Adapter: \u{2717} MISSING"
                adapterStatusLabel.textColor = UIColor(red: 0.96, green: 0.26, blue: 0.21, alpha: 1.0) // #F44336
            case .unknown:
                adapterStatusLabel.text = "Adapter: ? UNKNOWN"
                adapterStatusLabel.textColor = UIColor(red: 0.95, green: 0.61, blue: 0.07, alpha: 1.0) // #FF9800
            }
        }
        textContainer.addArrangedSubview(adapterStatusLabel)
        
        // SDK Status
        let sdkStatusLabel = UILabel()
        sdkStatusLabel.font = .systemFont(ofSize: 11)
        if dep.requiredClass == nil {
            sdkStatusLabel.text = "Native SDK: N/A"
            sdkStatusLabel.textColor = UIColor(red: 0.33, green: 0.33, blue: 0.33, alpha: 1.0) // #555555
        } else {
            let statusLabel = dep.isService ? "SDK" : "Native SDK"
            switch dep.sdkStatus {
            case .ok:
                sdkStatusLabel.text = "\(statusLabel): \u{2713} OK"
                sdkStatusLabel.textColor = UIColor(red: 0.30, green: 0.69, blue: 0.31, alpha: 1.0) // #4CAF50
            case .missing:
                sdkStatusLabel.text = dep.isService ? "\(statusLabel): Not included" : "\(statusLabel): \u{2717} Not included"
                sdkStatusLabel.textColor = dep.isService ? UIColor(red: 0.33, green: 0.33, blue: 0.33, alpha: 1.0) : UIColor(red: 0.96, green: 0.26, blue: 0.21, alpha: 1.0)
            case .unknown:
                sdkStatusLabel.text = "\(statusLabel): ? UNKNOWN"
                sdkStatusLabel.textColor = UIColor(red: 0.95, green: 0.61, blue: 0.07, alpha: 1.0) // #FF9800
            }
        }
        textContainer.addArrangedSubview(sdkStatusLabel)
        
        // Version (si existe)
        if let version = dep.version {
            let versionLabel = UILabel()
            versionLabel.text = "Version: \(version)"
            versionLabel.font = .systemFont(ofSize: 11)
            versionLabel.textColor = UIColor(red: 0.62, green: 0.62, blue: 0.62, alpha: 1.0) // #9E9E9E
            textContainer.addArrangedSubview(versionLabel)
        }
        
        // Error message (si existe y no es service)
        if let errorMessage = dep.errorMessage, !dep.isService {
            let errorLabel = UILabel()
            errorLabel.text = errorMessage
            errorLabel.font = .systemFont(ofSize: 11)
            errorLabel.textColor = UIColor(red: 0.96, green: 0.26, blue: 0.21, alpha: 1.0) // #F44336
            textContainer.addArrangedSubview(errorLabel)
        }
        
        // Status Badge (derecha) - como Android
        let statusBadge = UILabel()
        statusBadge.font = .systemFont(ofSize: 12, weight: .bold)
        statusBadge.textAlignment = .center
        statusBadge.textColor = UIColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1.0) // #212121
        statusBadge.layer.cornerRadius = 4
        statusBadge.clipsToBounds = true
        statusBadge.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(statusBadge)
        
        switch overallStatus {
        case .ok:
            statusBadge.text = "OK"
            statusBadge.backgroundColor = UIColor(red: 0.96, green: 0.98, blue: 0.96, alpha: 1.0) // #F5F5F5
        case .missing:
            statusBadge.text = "ERROR"
            statusBadge.backgroundColor = UIColor(red: 0.96, green: 0.98, blue: 0.96, alpha: 1.0) // #F5F5F5
        case .unknown:
            statusBadge.text = "WARN"
            statusBadge.backgroundColor = UIColor(red: 0.96, green: 0.98, blue: 0.96, alpha: 1.0) // #F5F5F5
        }
        
        // Constraints - replicar Android layout
        NSLayoutConstraint.activate([
            // Status icon (izquierda)
            statusIcon.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            statusIcon.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            statusIcon.widthAnchor.constraint(equalToConstant: 32),
            statusIcon.heightAnchor.constraint(equalToConstant: 32),
            
            // Text container (centro)
            textContainer.leadingAnchor.constraint(equalTo: statusIcon.trailingAnchor, constant: 16),
            textContainer.trailingAnchor.constraint(lessThanOrEqualTo: statusBadge.leadingAnchor, constant: -16),
            textContainer.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            
            // Status badge (derecha)
            statusBadge.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            statusBadge.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            statusBadge.widthAnchor.constraint(equalToConstant: 60),
            statusBadge.heightAnchor.constraint(equalToConstant: 24),
            
            // Cell height
            cell.contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 80)
        ])
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "SDK Dependencies"
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return "A: = Adapter status | S: = SDK status\nOK = Detected | MISSING = Not found | UNKNOWN = Error"
    }
}

// MARK: - UITableViewDelegate

extension DependenciesViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let dep = dependencies[indexPath.row]
        
        var message = "SDK: \(dep.sdkName)\n"
        message += "Adapter Class: \(dep.adapterClass)\n"
        message += "Adapter Status: \(dep.adapterStatus.rawValue)\n"
        
        if dep.isService {
            message += "Service: Yes\n"
        } else {
            if let requiredClass = dep.requiredClass {
                message += "SDK Class: \(requiredClass)\n"
                message += "SDK Status: \(dep.sdkStatus.rawValue)\n"
            } else {
                message += "SDK Class: N/A (WebView-based)\n"
                message += "SDK Status: N/A\n"
            }
        }
        
        if let version = dep.version {
            message += "Version: \(version)\n"
        }
        
        if let error = dep.errorMessage {
            message += "Error: \(error)\n"
        }
        
        let alert = UIAlertController(
            title: dep.providerName,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
