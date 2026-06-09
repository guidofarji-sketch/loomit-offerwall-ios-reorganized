Pod::Spec.new do |s|
  s.name             = 'LoomitOfferwallAdapterMyChips'
  s.version          = '0.3.0-beta.33'
  s.summary          = 'Loomit Offerwall Adapter for MyChips/MAF'
  s.description      = <<-DESC
    MyChips/MAF offerwall adapter for Loomit Offerwall SDK iOS.
    Integrates with MyChips iOS SDK (https://docs.mychips.io/ios/install-sdk).
  DESC

  s.homepage         = 'https://github.com/guidofarji-sketch/loomit-offerwall-ios-reorganized'
  s.license          = { :type => 'Proprietary', :text => 'Copyright Loomit. All rights reserved.' }
  s.author           = { 'Loomit' => 'support@loomit.com' }

  s.ios.deployment_target = '14.0'
  s.swift_version = '5.0'

  s.source           = { :git => 'https://github.com/guidofarji-sketch/loomit-offerwall-ios-reorganized.git', :tag => s.version.to_s }

  s.source_files = 'LoomitOfferwallAdapterMyChips/Sources/**/*.swift'

  s.dependency 'LoomitOfferwallCore', '~> 0.3.0-beta'

  s.vendored_frameworks = 'Frameworks/MyChipsSdk.xcframework'

  s.static_framework = true

  s.pod_target_xcconfig = {
    'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'YES',
    'SWIFT_VERSION' => '5.0'
  }
end
