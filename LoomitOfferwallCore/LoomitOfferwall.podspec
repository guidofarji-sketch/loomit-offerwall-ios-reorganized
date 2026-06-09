Pod::Spec.new do |s|
  s.name             = 'LoomitOfferwall'
  s.version          = '0.3.0-beta.26'
  s.summary          = 'Loomit Offerwall SDK for iOS'
  s.description      = <<-DESC
    Loomit Offerwall SDK provides a unified monetization layer with multi-provider
    offerwall support (Tapjoy, MyChips). Sources are compiled locally so the SDK
    works with any Swift/Xcode version.
  DESC

  s.homepage         = 'https://github.com/guidofarji-sketch/loomit-offerwall-ios'
  s.license          = { :type => 'Proprietary', :text => 'Copyright Loomit. All rights reserved.' }
  s.author           = { 'Loomit' => 'support@loomit.com' }
  s.source           = { :git => 'https://github.com/guidofarji-sketch/loomit-offerwall-ios.git', :tag => s.version.to_s }

  s.ios.deployment_target = '14.0'
  s.swift_versions = ['5.0', '5.9', '6.0']

  # Static framework to prevent duplicate symbols when linked in multiple targets
  s.static_framework = true

  # Single monolithic target — all sources compiled once into one library.
  # Subspec architecture causes duplicate symbols with use_frameworks! :linkage => :static
  # because each subspec that depends on Core embeds Core's symbols independently.
  s.source_files = [
    'Sources/LoomitOfferwallAdapterAPI/**/*.swift',
    'Sources/LoomitOfferwallCore/**/*.swift',
    'Sources/LoomitOfferwallDebug/**/*.swift',
    'Sources/LoomitOfferwallAdapterTapjoy/**/*.swift',
    'Sources/LoomitOfferwallAdapterMyChips/**/*.swift'
  ]

  s.resource_bundles = {
    'LoomitOfferwallCore' => ['Resources/**/*']
  }

  s.frameworks = 'Foundation', 'UIKit', 'AdSupport'

  s.vendored_frameworks = 'Frameworks/MyChipsSdk.xcframework'

  s.dependency 'TapjoySDK', '~> 14.0'

  s.pod_target_xcconfig = {
    'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'YES',
    'SWIFT_VERSION' => '5.0',
    'OTHER_LDFLAGS' => '-ObjC'
  }

end
