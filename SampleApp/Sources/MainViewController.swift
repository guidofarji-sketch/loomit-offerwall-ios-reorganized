//
//  MainViewController.swift
//  LoomitOfferwallSampleApp
//
//  UI principal para probar el SDK LoomitOfferwall - igual que Kotlin Sample App
//

import UIKit
import AdSupport  // For ASIdentifierManager (IDFA)
import LoomitOfferwallAdapterAPI
import LoomitOfferwallCore
import LoomitOfferwallAdapterMyChips
import LoomitOfferwallAdapterTapjoy
import LoomitOfferwallDebug

// MARK: - AdSpaceStore

/// Helper for persisting ad_space values to disk.
/// Stores a list of user-defined ad_spaces and the currently selected one.
/// Paridad con Android AdSpaceStore.kt
private enum AdSpaceStore {
    private static let prefsName = "loomit_ad_spaces"
    private static let keyAdSpaces = "ad_space_list"
    private static let keySelected = "selected_ad_space"
    static let noneOption = "(none)"

    private static func getPrefs() -> UserDefaults {
        UserDefaults.standard
    }

    /// Returns the list of saved ad_spaces.
    /// Always includes "(none)" as the first option.
    static func getAdSpaces() -> [String] {
        let prefs = getPrefs()
        let saved = prefs.stringArray(forKey: keyAdSpaces) ?? []
        return [noneOption] + saved.sorted()
    }

    /// Adds a new ad_space to the list and persists it.
    /// Returns true if added, false if it already exists.
    static func addAdSpace(_ adSpace: String) -> Bool {
        let trimmed = adSpace.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == noneOption { return false }

        let prefs = getPrefs()
        var current = prefs.stringArray(forKey: keyAdSpaces) ?? []

        if current.contains(trimmed) { return false }

        current.append(trimmed)
        prefs.set(current, forKey: keyAdSpaces)
        return true
    }

    /// Removes an ad_space from the list.
    static func removeAdSpace(_ adSpace: String) {
        let prefs = getPrefs()
        var current = prefs.stringArray(forKey: keyAdSpaces) ?? []
        current.removeAll { $0 == adSpace }
        prefs.set(current, forKey: keyAdSpaces)

        // Clear selection if removing the selected one
        if getSelectedAdSpace() == adSpace {
            setSelectedAdSpace(nil)
        }
    }

    /// Gets the currently selected ad_space.
    /// Returns nil if "(none)" is selected or nothing is selected.
    static func getSelectedAdSpace() -> String? {
        let prefs = getPrefs()
        let selected = prefs.string(forKey: keySelected)
        return (selected == noneOption || selected?.isEmpty == true) ? nil : selected
    }

    /// Sets the currently selected ad_space.
    /// Pass nil or NONE_OPTION to clear the selection.
    static func setSelectedAdSpace(_ adSpace: String?) {
        let prefs = getPrefs()
        let value = (adSpace == noneOption || adSpace?.isEmpty == true) ? nil : adSpace
        prefs.set(value, forKey: keySelected)
    }

    /// Gets the index of the currently selected ad_space in the list.
    /// Returns 0 (none) if not found.
    static func getSelectedIndex() -> Int {
        guard let selected = getSelectedAdSpace() else { return 0 }
        let list = getAdSpaces()
        let index = list.firstIndex(of: selected)
        return index ?? 0
    }
}


@MainActor
final class MainViewController: UIViewController {
    
    // MARK: - UI Components - Input Fields
    private lazy var apiKeyTextField: UITextField = createTextField(
        placeholder: "API Key",
        text: "lmt_b1debf8669027a925c0e60cf3e0377e206c47e8c8dba3897"
    )
    
    private lazy var clientIdTextField: UITextField = createTextField(
        placeholder: "Client ID",
        text: "cl_417b8"
    )
    
    private lazy var appIdTextField: UITextField = createTextField(
        placeholder: "App ID",
        text: "ap_41d5f8d28c"
    )

    private lazy var publisherUserIdTextField: UITextField = createTextField(
        placeholder: "Publisher User ID (optional)",
        text: ""
    )
    
    // MARK: - UI Components - Buttons
    private lazy var fetchConfigButton: UIButton = createButton(
        title: "1. Fetch Config",
        color: .systemBlue,
        action: #selector(didTapFetchConfig)
    )
    
    private lazy var initProvidersButton: UIButton = createButton(
        title: "2. Initialize Providers",
        color: .systemOrange,
        action: #selector(didTapInitProviders)
    )
    
    private lazy var showButton: UIButton = createButton(
        title: "3. Show Offerwall",
        color: .systemGreen,
        action: #selector(didTapShow)
    )
    
    private lazy var debugButton: UIButton = createButton(
        title: "🔍 Debug Panel",
        color: .systemPurple,
        action: #selector(didTapDebug)
    )
    
    private lazy var checkEventsButton: UIButton = createButton(
        title: "📋 Check Events",
        color: .systemGray,
        action: #selector(didTapCheckEvents)
    )
    
    // MARK: - UI Components - Provider Selection
    private lazy var providerLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.text = "Provider:"
        return label
    }()
    
    private lazy var providerPicker: UIPickerView = {
        let picker = UIPickerView()
        picker.delegate = self
        picker.dataSource = self
        picker.tag = 1  // Tag to distinguish from adSpacePicker
        return picker
    }()
    
    private lazy var failoverButton: UIButton = createButton(
        title: "🔄 Force Failover",
        color: .systemRed,
        action: #selector(didTapFailover)
    )
    
    // MARK: - UI Components - Test Mode
    private lazy var testModeSwitch: UISwitch = {
        let sw = UISwitch()
        sw.isOn = true
        sw.addTarget(self, action: #selector(testModeChanged), for: .valueChanged)
        return sw
    }()

    private lazy var testModeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.text = "Test Mode: ON"
        return label
    }()

    // MARK: - UI Components - Ad Space
    private lazy var adSpaceLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.text = "Ad Space:"
        return label
    }()

    private lazy var adSpacePicker: UIPickerView = {
        let picker = UIPickerView()
        picker.delegate = self
        picker.dataSource = self
        return picker
    }()

    private lazy var addAdSpaceButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("+ Add Ad Space", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 14)
        btn.addTarget(self, action: #selector(didTapAddAdSpace), for: .touchUpInside)
        return btn
    }()
    
    private lazy var idfaLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        label.text = "IDFA: Loading..."
        return label
    }()
    
    // MARK: - UI Components - Custom Properties
    private lazy var manageCustomPropertiesButton: UIButton = createButton(
        title: "Manage Custom Properties",
        color: .systemTeal,
        action: #selector(didTapManageCustomProperties)
    )

    // MARK: - UI Components - Info Display
    private lazy var configInfoTextView: UITextView = {
        let tv = UITextView()
        tv.isEditable = false
        tv.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.backgroundColor = .secondarySystemBackground
        tv.layer.cornerRadius = 8
        tv.text = "Config Info:\n\nPresiona 'Fetch Config' para cargar la configuración del servidor..."
        return tv
    }()
    
    private lazy var consoleTextView: UITextView = {
        let tv = UITextView()
        tv.isEditable = false
        tv.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.backgroundColor = .black
        tv.textColor = .green
        tv.layer.cornerRadius = 8
        tv.text = "Console Logs...\n"
        return tv
    }()
    
    // MARK: - Dependencies
    private let sdk = OfferwallSdk.shared
    private var debugCollector: DebugDataCollector?
    private var trackingListener: SampleTrackingListener?
    
    // MARK: - State
    private var fetchedConfig: ConfigResponse?
    private var availableProviders: [String] = ["Auto"]  // "Auto" + provider keys
    private var selectedProviderIndex: Int = 0  // 0 = Auto, 1+ = specific provider
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Loomit Offerwall SDK v1.0.14"
        view.backgroundColor = .systemBackground
        setupUI()

        // Enable debugging (activates shake gesture and debug panel)
        Task {
            await sdk.setDebuggingEnabled(true)
        }
        DebugPanel.setEnabled(true)

        // Load IDFA for test device identification
        loadIDFA()

        // Setup debug collector
        debugCollector = DebugDataCollector()

        // Initialize DebugPanel with DebugDataCollector (injeta en SDK)
        if let collector = debugCollector {
            DebugPanel.initialize(dataCollector: collector)
        }

        // Setup console logging + debug event recording
        trackingListener = SampleTrackingListener(
            collector: debugCollector,
            onEvent: { [weak self] message in
                self?.log(message)
            }
        )
        Task {
            await sdk.setListener(self)
            await sdk.setTrackingListener(trackingListener!)
        }

        // Load ad spaces
        loadAdSpaces()
        Task { await CustomPropertiesStore.applySavedProperties() }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        becomeFirstResponder()
        Task { await CustomPropertiesStore.applySavedProperties() }
    }
    
    // MARK: - Setup
    private func setupUI() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.layoutMargins = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.isLayoutMarginsRelativeArrangement = true
        scrollView.addSubview(stack)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
        
        // Section: Credentials
        stack.addArrangedSubview(createSectionTitle("Credentials (Staging)"))
        stack.addArrangedSubview(apiKeyTextField)
        stack.addArrangedSubview(clientIdTextField)
        stack.addArrangedSubview(appIdTextField)

        // Section: User Identity
        stack.addArrangedSubview(createSectionTitle("User Identity"))
        publisherUserIdTextField.text = UserDefaults.standard.string(forKey: "loomit_publisher_user_id") ?? ""
        publisherUserIdTextField.addTarget(self, action: #selector(publisherUserIdChanged), for: .editingChanged)
        stack.addArrangedSubview(publisherUserIdTextField)

        // Section: Custom Properties
        stack.addArrangedSubview(createSectionTitle("Custom Properties"))
        stack.addArrangedSubview(manageCustomPropertiesButton)
        
        // Section: Test Mode
        stack.addArrangedSubview(createSectionTitle("Debug Settings"))
        let testModeStack = UIStackView(arrangedSubviews: [testModeLabel, testModeSwitch])
        testModeStack.axis = .horizontal
        testModeStack.distribution = .equalSpacing
        stack.addArrangedSubview(testModeStack)
        stack.addArrangedSubview(idfaLabel)

        // Section: Ad Space
        stack.addArrangedSubview(createSectionTitle("Ad Space"))
        let adSpaceStack = UIStackView(arrangedSubviews: [adSpaceLabel, addAdSpaceButton])
        adSpaceStack.axis = .horizontal
        adSpaceStack.distribution = .equalSpacing
        stack.addArrangedSubview(adSpaceStack)
        adSpacePicker.heightAnchor.constraint(equalToConstant: 100).isActive = true
        stack.addArrangedSubview(adSpacePicker)
        
        // Section: Provider Selection
        stack.addArrangedSubview(createSectionTitle("Provider Selection"))
        let providerStack = UIStackView(arrangedSubviews: [providerLabel, providerPicker])
        providerStack.axis = .horizontal
        providerStack.distribution = .fillProportionally
        providerStack.spacing = 8
        providerPicker.heightAnchor.constraint(equalToConstant: 100).isActive = true
        stack.addArrangedSubview(providerStack)
        stack.addArrangedSubview(failoverButton)
        failoverButton.isEnabled = false
        
        // Section: Actions
        stack.addArrangedSubview(createSectionTitle("Actions"))
        stack.addArrangedSubview(fetchConfigButton)
        stack.addArrangedSubview(initProvidersButton)
        stack.addArrangedSubview(showButton)
        stack.addArrangedSubview(debugButton)
        stack.addArrangedSubview(checkEventsButton)
        
        // Section: Config Info
        stack.addArrangedSubview(createSectionTitle("Offerwall Plan"))
        configInfoTextView.heightAnchor.constraint(equalToConstant: 200).isActive = true
        stack.addArrangedSubview(configInfoTextView)
        
        // Section: Console
        stack.addArrangedSubview(createSectionTitle("SDK Events"))
        consoleTextView.heightAnchor.constraint(equalToConstant: 150).isActive = true
        stack.addArrangedSubview(consoleTextView)
        
        initProvidersButton.isEnabled = false
        showButton.isEnabled = false
    }
    
    private func createSectionTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .bold)
        label.textColor = .secondaryLabel
        label.text = text.uppercased()
        return label
    }
    
    private func createTextField(placeholder: String, text: String) -> UITextField {
        let tf = UITextField()
        tf.borderStyle = .roundedRect
        tf.placeholder = placeholder
        tf.text = text
        tf.font = .systemFont(ofSize: 14)
        tf.autocorrectionType = .no
        tf.autocapitalizationType = .none
        return tf
    }
    
    private func createButton(title: String, color: UIColor, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.backgroundColor = color
        btn.setTitleColor(.white, for: .normal)
        btn.layer.cornerRadius = 8
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        btn.heightAnchor.constraint(equalToConstant: 44).isActive = true
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }
    
    // MARK: - Actions
    
    @objc private func didTapManageCustomProperties() {
        let vc = SampleCustomPropertiesViewController()
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }

    @objc private func publisherUserIdChanged() {
        let value = publisherUserIdTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        UserDefaults.standard.set(value.isEmpty ? nil : value, forKey: "loomit_publisher_user_id")
    }

    @objc private func didTapFetchConfig() {
        log("🚀 Fetching Config...")
        fetchConfigButton.isEnabled = false

        Task {
            // Set credentials from text fields
            await sdk.setLoomitApiKey(apiKeyTextField.text ?? "")
            await sdk.setClientId(clientIdTextField.text ?? "")
            await sdk.setAppId(appIdTextField.text ?? "")
            await sdk.setEnvironment(.live)

            // Apply publisher user ID (mirrors Android applyPublisherUserId())
            let rawUserId = publisherUserIdTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if rawUserId.isEmpty {
                await sdk.clearPublisherUserId()
            } else {
                await sdk.setPublisherUserId(rawUserId)
                log("👤 Publisher user ID: \(rawUserId.prefix(8))…")
            }
            
            // Attach debug collector to SDK bridge
            await debugCollector?.attach(bridge: sdk.debugBridge())
            
            // Register adapters
            let myChipsAdapter = MyChipsAdapter()
            await sdk.registerAdapter(myChipsAdapter)

            let tapjoyAdapter = TapjoyAdapter()
            await sdk.registerAdapter(tapjoyAdapter)
            
            // Fetch config
            do {
                let config = try await sdk.fetchConfig()
                fetchedConfig = config
                
                log("✅ Config fetched successfully")
                await updateConfigInfo()
                
                initProvidersButton.isEnabled = true
                fetchConfigButton.isEnabled = true
            } catch {
                log("❌ Error fetching config: \(error)")
                fetchConfigButton.isEnabled = true
            }
        }
    }
    
    @objc private func didTapInitProviders() {
        log("🚀 Initializing Providers...")
        initProvidersButton.isEnabled = false
        
        Task {
            await sdk.initAllFromPlan()
            log("✅ Providers initialized")
            
            let hasAvail = await sdk.hasAvailableOfferwall()
            log("📊 Offerwall available: \(hasAvail)")
            
            showButton.isEnabled = hasAvail
            failoverButton.isEnabled = hasAvail
            initProvidersButton.isEnabled = true
        }
    }
    
    @objc private func didTapShow() {
        let selectedAdSpace = AdSpaceStore.getSelectedAdSpace()
        
        // Determine provider override based on picker selection
        let providerOverride: String?
        if selectedProviderIndex > 0 && selectedProviderIndex < availableProviders.count {
            providerOverride = availableProviders[selectedProviderIndex]
            log("📱 Showing Offerwall... (adSpace: \(selectedAdSpace ?? "none"), provider: \(providerOverride!))")
        } else {
            providerOverride = nil
            log("📱 Showing Offerwall... (adSpace: \(selectedAdSpace ?? "none"), provider: Auto)")
        }

        Task {
            await sdk.show(from: self, providerOverride: providerOverride, adSpace: selectedAdSpace)
        }
    }
    
    @objc private func didTapFailover() {
        log("🔄 Forcing failover to next provider...")
        
        Task {
            let success = await sdk.failoverToNext(from: self, adSpace: AdSpaceStore.getSelectedAdSpace())
            if success {
                log("✅ Failover successful")
            } else {
                log("❌ Failover failed - no more providers available")
            }
        }
    }

    @objc private func didTapAddAdSpace() {
        let alert = UIAlertController(
            title: "Add Ad Space",
            message: "Enter a unique identifier for the ad placement:",
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.placeholder = "e.g., level_completed, dashboard"
        }

        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self] _ in
            guard let self = self,
                  let newAdSpace = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !newAdSpace.isEmpty else {
                return
            }
            let added = AdSpaceStore.addAdSpace(newAdSpace)
            if added {
                self.loadAdSpaces()
                // Select the newly added ad_space
                let adSpaces = AdSpaceStore.getAdSpaces()
                if let newIndex = adSpaces.firstIndex(of: newAdSpace) {
                    self.adSpacePicker.selectRow(newIndex, inComponent: 0, animated: true)
                    AdSpaceStore.setSelectedAdSpace(newAdSpace)
                }
                self.log("✅ Ad Space '\(newAdSpace)' added")
            } else {
                self.log("❌ Ad Space already exists")
            }
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        present(alert, animated: true)
    }

    // MARK: - Ad Space

    private func loadAdSpaces() {
        let adSpaces = AdSpaceStore.getAdSpaces()
        adSpacePicker.reloadAllComponents()

        // Restore selection
        let selectedIndex = AdSpaceStore.getSelectedIndex()
        if selectedIndex < adSpaces.count {
            adSpacePicker.selectRow(selectedIndex, inComponent: 0, animated: false)
        }
    }
    
    @objc private func didTapDebug() {
        // Use the new full debugging suite
        DebugPanel.show(from: self)
    }
    
    @objc private func didTapCheckEvents() {
        let events = trackingListener?.getRecentEvents() ?? []
        log("📋 Recent events captured: \(events.count)")
        for event in events {
            log("  - \(event)")
        }
    }
    
    @objc private func testModeChanged() {
        let isOn = testModeSwitch.isOn
        testModeLabel.text = "Test Mode: \(isOn ? "ON" : "OFF")"
        
        // Enable/disable debugging (activates shake gesture and debug panel)
        Task {
            await sdk.setDebuggingEnabled(isOn)
        }
        DebugPanel.setEnabled(isOn)
        
        log("🧪 Test mode changed to \(isOn)")
        log("   Debugging enabled: \(isOn)")
    }
    
    // MARK: - IDFA
    
    private func loadIDFA() {
        // iOS uses IDFA (Identifier for Advertising) via ASIdentifierManager
        // Note: This requires AppTrackingTransparency framework and user consent
        let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
        
        // Report to SDK
        if idfa != "00000000-0000-0000-0000-000000000000" {
            Task {
                await sdk.setAdvertisingId(idfa)
                await sdk.setHasAdvertisingId(true)
            }
            idfaLabel.text = "IDFA: \(idfa.prefix(8))...\n(Tracking enabled)"
            log("📱 IDFA loaded: \(idfa.prefix(8))...")
        } else {
            Task {
                await sdk.setAdvertisingId(nil)
                await sdk.setHasAdvertisingId(false)
            }
            idfaLabel.text = "IDFA: Not available\n(Tracking disabled or denied)"
            log("📱 IDFA not available (tracking disabled)")
        }
    }
    
    // MARK: - Helpers
    
    private func updateConfigInfo() async {
        guard let config = fetchedConfig else {
            configInfoTextView.text = "No config loaded"
            return
        }
        
        var info = "📋 Config Response:\n"
        info += "Segment: \(config.segment ?? "default")\n"
        info += "Debugging: \(config.debuggingStatus ?? false)\n\n"
        
        if let offerwall = config.offerwall {
            info += "Default Waterfall (\(offerwall.defaultWaterfall.count) providers):\n"
            for (index, entry) in offerwall.defaultWaterfall.enumerated() {
                info += "  \(index + 1). \(entry.providerId)"
                info += " (active: \(entry.isActive), priority: \(entry.priority))\n"
            }
            
            if !offerwall.adSpaceOverrides.isEmpty {
                info += "\nAd Space Overrides: \(offerwall.adSpaceOverrides.keys.joined(separator: ", "))\n"
            }
        }
        
        // Use providerPlan instead of configurations (includes ad_space_overrides)
        let providerPlan = await OfferwallSdk.shared.getProviderPlan()
        info += "\nProvider Plan (\(providerPlan.count) providers):\n"
        for (index, entry) in providerPlan.enumerated() {
            info += "  \(index + 1). \(entry.providerId) (priority: \(entry.priority))\n"
        }
        
        // Update available providers list for picker (keep "Auto" first, then add providers from plan)
        var providers = ["Auto"]
        providers.append(contentsOf: providerPlan.map { $0.providerId })
        availableProviders = providers
        
        await MainActor.run {
            self.configInfoTextView.text = info
            self.providerPicker.reloadAllComponents()
        }
    }
    
    private func log(_ message: String) {
        DispatchQueue.main.async {
            let formatter = DateFormatter()
            formatter.timeStyle = .medium
            let timestamp = formatter.string(from: Date())
            self.consoleTextView.text += "[\(timestamp)] \(message)\n"
            let bottom = NSMakeRange(self.consoleTextView.text.count - 1, 1)
            self.consoleTextView.scrollRangeToVisible(bottom)
        }
    }
}

// MARK: - OfferwallListener

extension MainViewController: OfferwallListener {

    func offerwall(didReceiveConfig result: Result<ConfigResponse, OfferwallError>) {}

    func offerwallDidInitialize() {
        log("✅ Offerwall initialized (listener callback)")
    }

    func offerwall(didFailToInitialize reason: String) {
        log("❌ Offerwall failed to initialize: \(reason)")
    }

    func offerwall(didChangeAvailability isAvailable: Bool) {
        log("📊 Availability changed: \(isAvailable ? "available ✅" : "unavailable")")
        showButton.isEnabled = isAvailable
        failoverButton.isEnabled = isAvailable
    }

    func offerwall(didShow providerKey: String, adSpace: String?) {
        log("👀 Offerwall shown (\(providerKey))")
    }

    func offerwall(didClose providerKey: String) {
        log("❌ Offerwall closed (\(providerKey))")
    }

    func offerwall(didFailToShow error: OfferwallError, adSpace: String?) {
        log("❌ Offerwall failed to show: \(error.localizedDescription)")
    }

    func offerwall(didEarnRewardAmount amount: Int, currency: String, providerKey: String) {
        log("🏆 Reward: \(amount) \(currency) from \(providerKey)")
    }
}

// MARK: - UIPickerViewDataSource

extension MainViewController: UIPickerViewDataSource {
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        if pickerView.tag == 1 {
            // Provider picker
            return availableProviders.count
        } else {
            // Ad Space picker
            return AdSpaceStore.getAdSpaces().count
        }
    }
}

// MARK: - UIPickerViewDelegate

extension MainViewController: UIPickerViewDelegate {
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        if pickerView.tag == 1 {
            // Provider picker
            return availableProviders[row]
        } else {
            // Ad Space picker
            return AdSpaceStore.getAdSpaces()[row]
        }
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if pickerView.tag == 1 {
            // Provider picker
            selectedProviderIndex = row
            let provider = availableProviders[row]
            log("📱 Provider selected: \(provider)")
        } else {
            // Ad Space picker
            let selectedAdSpace = AdSpaceStore.getAdSpaces()[row]
            if selectedAdSpace == AdSpaceStore.noneOption {
                AdSpaceStore.setSelectedAdSpace(nil)
                log("📍 Ad Space cleared (none selected)")
            } else {
                AdSpaceStore.setSelectedAdSpace(selectedAdSpace)
                log("📍 Ad Space selected: \(selectedAdSpace)")
            }
        }
    }
}

// MARK: - Sample Tracking Listener

@MainActor
final class SampleTrackingListener: OfferwallTrackingListener {
    
    private let onEvent: (String) -> Void
    private let collector: DebugDataCollector?
    private var recentEvents: [String] = []
    private let maxEvents = 50
    
    init(collector: DebugDataCollector?, onEvent: @escaping (String) -> Void) {
        self.collector = collector
        self.onEvent = onEvent
    }
    
    func offerwallTracking(didDispatchEvent name: String, payload: [String: LoomitOfferwallCore.JSONValue]) {
        let payloadStr = payload.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        let eventStr = "📊 \(name): \(payloadStr)"
        
        // Debug print to console
        print("[SampleTrackingListener] Received event: \(name)")
        
        // Store in local buffer
        recentEvents.append(eventStr)
        if recentEvents.count > maxEvents {
            recentEvents.removeFirst(recentEvents.count - maxEvents)
        }
        
        // Note: Events are already recorded to DebugDataCollector by SDK via sendDebugEvent
        // We don't need to record them again here to avoid duplication
        
        onEvent(eventStr)
    }
    
    func getRecentEvents() -> [String] {
        return recentEvents
    }
    
    func clearEvents() {
        recentEvents.removeAll()
    }
}

// MARK: - Shake detection for Debug Pill
extension MainViewController {
    public override var canBecomeFirstResponder: Bool { true }

    public override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            DebugPanel.handleShake()
        }
        super.motionEnded(motion, with: event)
    }
}
