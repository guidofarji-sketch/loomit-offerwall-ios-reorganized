Pod::Spec.new do |s|
  s.name             = 'LoomitOfferwallCore'
  s.version          = '0.3.0-beta.32'
  s.summary          = 'Loomit Offerwall Core SDK for iOS'
  s.description      = <<-DESC
    Loomit Offerwall Core SDK provides the base functionality for the offerwall.
    Use with specific adapters for providers (Tapjoy, MyChips, etc.).
  DESC

  s.homepage         = 'https://github.com/guidofarji-sketch/loomit-offerwall-ios-reorganized'
  s.license          = { :type => 'Proprietary', :text => 'Copyright Loomit. All rights reserved.' }
  s.author           = { 'Loomit' => 'support@loomit.com' }
  s.source           = { :git => 'https://github.com/guidofarji-sketch/loomit-offerwall-ios-reorganized.git', :tag => s.version.to_s }

  s.ios.deployment_target = '14.0'
  s.swift_version = '5.0'

  # Static framework to prevent duplicate symbols when linked in multiple targets
  s.static_framework = true

  s.source_files = 'LoomitOfferwallCore/Sources/**/*.swift'

  s.resource_bundles = {
    'LoomitOfferwallCore' => ['LoomitOfferwallCore/Resources/**/*']
  }

  s.frameworks = 'Foundation', 'UIKit', 'AdSupport'

  s.vendored_frameworks = 'Frameworks/MyChipsSdk.xcframework'

  s.dependency 'TapjoySDK', '~> 14.0'

  s.pod_target_xcconfig = {
    'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'YES',
    'SWIFT_VERSION' => '5.0'
  }

end
