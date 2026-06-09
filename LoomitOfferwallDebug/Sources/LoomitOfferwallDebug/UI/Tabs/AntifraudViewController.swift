//
//  AntifraudViewController.swift
//  LoomitOfferwallDebug
//
//  Tab de Antifraud: estado del SDK Antifraud.
//  Placeholder hasta que el SDK esté disponible.
//

import UIKit

@MainActor
final class AntifraudViewController: UIViewController {
    
    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()
    
    private lazy var contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Anti-Fraud Protection"
        label.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var statusCard: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemBackground
        view.layer.cornerRadius = 12
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.systemGray4.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var statusIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "exclamationmark.triangle.fill")
        imageView.tintColor = .systemOrange
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.text = "Not Available"
        label.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        label.textColor = .systemOrange
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var descriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "The Loomit Antifraud SDK is currently under development for iOS. This tab will display anti-fraud protection status, risk scores, and validation results when available."
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var infoCard: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemBackground
        view.layer.cornerRadius = 12
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.systemGray4.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var infoTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Expected Features"
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var featureStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNavigation()
    }
    
    private func setupUI() {
        view.backgroundColor = .systemGroupedBackground
        
        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(titleLabel)
        contentView.addSubview(statusCard)
        contentView.addSubview(infoCard)
        
        statusCard.addSubview(statusIcon)
        statusCard.addSubview(statusLabel)
        statusCard.addSubview(descriptionLabel)
        
        infoCard.addSubview(infoTitleLabel)
        infoCard.addSubview(featureStack)
        
        setupFeatureList()
        
        NSLayoutConstraint.activate([
            // ScrollView
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
            
            // Title
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Status card
            statusCard.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            statusCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            statusCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Status icon
            statusIcon.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: 20),
            statusIcon.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 20),
            statusIcon.widthAnchor.constraint(equalToConstant: 24),
            statusIcon.heightAnchor.constraint(equalToConstant: 24),
            
            // Status label
            statusLabel.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: 20),
            statusLabel.leadingAnchor.constraint(equalTo: statusIcon.trailingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -20),
            
            // Description label
            descriptionLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            descriptionLabel.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 20),
            descriptionLabel.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -20),
            descriptionLabel.bottomAnchor.constraint(equalTo: statusCard.bottomAnchor, constant: -20),
            
            // Info card
            infoCard.topAnchor.constraint(equalTo: statusCard.bottomAnchor, constant: 20),
            infoCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            infoCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            infoCard.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            
            // Info title
            infoTitleLabel.topAnchor.constraint(equalTo: infoCard.topAnchor, constant: 20),
            infoTitleLabel.leadingAnchor.constraint(equalTo: infoCard.leadingAnchor, constant: 20),
            infoTitleLabel.trailingAnchor.constraint(equalTo: infoCard.trailingAnchor, constant: -20),
            
            // Feature stack
            featureStack.topAnchor.constraint(equalTo: infoTitleLabel.bottomAnchor, constant: 16),
            featureStack.leadingAnchor.constraint(equalTo: infoCard.leadingAnchor, constant: 20),
            featureStack.trailingAnchor.constraint(equalTo: infoCard.trailingAnchor, constant: -20),
            featureStack.bottomAnchor.constraint(equalTo: infoCard.bottomAnchor, constant: -20)
        ])
    }
    
    private func setupFeatureList() {
        let features = [
            "SDK Availability Status",
            "Anti-Fraud Configuration",
            "Risk Score Display",
            "Validation Results",
            "Safety Config JSON",
            "Test Validation Button",
            "Debug Information"
        ]
        
        for feature in features {
            let featureView = createFeatureView(text: feature)
            featureStack.addArrangedSubview(featureView)
        }
    }
    
    private func createFeatureView(text: String) -> UIView {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        let bulletLabel = UILabel()
        bulletLabel.text = "•"
        bulletLabel.font = UIFont.systemFont(ofSize: 14)
        bulletLabel.textColor = .secondaryLabel
        bulletLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let featureLabel = UILabel()
        featureLabel.text = text
        featureLabel.font = UIFont.systemFont(ofSize: 14)
        featureLabel.textColor = .label
        featureLabel.translatesAutoresizingMaskIntoConstraints = false
        
        containerView.addSubview(bulletLabel)
        containerView.addSubview(featureLabel)
        
        NSLayoutConstraint.activate([
            bulletLabel.topAnchor.constraint(equalTo: containerView.topAnchor),
            bulletLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            bulletLabel.widthAnchor.constraint(equalToConstant: 20),
            
            featureLabel.topAnchor.constraint(equalTo: containerView.topAnchor),
            featureLabel.leadingAnchor.constraint(equalTo: bulletLabel.trailingAnchor),
            featureLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            featureLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        return containerView
    }
    
    private func setupNavigation() {
        // No additional navigation setup needed
    }
}
