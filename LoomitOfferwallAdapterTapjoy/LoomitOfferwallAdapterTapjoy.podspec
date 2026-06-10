Pod::Spec.new do |s|
  s.name             = 'LoomitOfferwallAdapterTapjoy'
  s.version          = '0.3.0-beta.34'
  s.summary          = 'Loomit Offerwall Adapter for Tapjoy'
  s.description      = <<-DESC
    Tapjoy offerwall adapter for Loomit Offerwall SDK iOS.
    Integrates with Tapjoy iOS SDK (https://docs.unity.com/grow/offerwall/ios).
  DESC

  s.homepage         = 'https://github.com/guidofarji-sketch/loomit-offerwall-ios-reorganized'
  s.license          = { :type => 'Proprietary', :text => 'Copyright Loomit. All rights reserved.' }
  s.author           = { 'Loomit' => 'support@loomit.com' }

  s.ios.deployment_target = '14.0'
  s.swift_version = '5.0'

  s.source           = { :git => 'https://github.com/guidofarji-sketch/loomit-offerwall-ios-reorganized.git', :tag => s.version.to_s }

  s.source_files = 'LoomitOfferwallAdapterTapjoy/Sources/**/*.swift'

  s.dependency 'LoomitOfferwallAdapterAPI', '~> 0.3.0-beta'
  s.dependency 'TapjoySDK', '~> 14.7.0'

  s.static_framework = true
end
