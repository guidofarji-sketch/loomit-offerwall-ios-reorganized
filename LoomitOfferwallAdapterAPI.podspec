Pod::Spec.new do |s|
  s.name             = 'LoomitOfferwallAdapterAPI'
  s.version          = '0.3.0-beta.32'
  s.summary          = 'Loomit Offerwall Adapter API for iOS'
  s.description      = <<-DESC
    Adapter API interface for Loomit Offerwall SDK iOS.
    Defines the protocol that offerwall adapters must implement.
  DESC

  s.homepage         = 'https://github.com/guidofarji-sketch/loomit-offerwall-ios-reorganized'
  s.license          = { :type => 'Proprietary', :text => 'Copyright Loomit. All rights reserved.' }
  s.author           = { 'Loomit' => 'support@loomit.com' }

  s.ios.deployment_target = '14.0'
  s.swift_version = '5.0'

  s.source           = { :git => 'https://github.com/guidofarji-sketch/loomit-offerwall-ios-reorganized.git', :tag => s.version.to_s }

  s.source_files = 'LoomitOfferwallAdapterAPI/Sources/**/*.swift'

  s.static_framework = true

  s.pod_target_xcconfig = {
    'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'YES',
    'SWIFT_VERSION' => '5.0'
  }
end
