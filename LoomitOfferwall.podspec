Pod::Spec.new do |s|
  s.name             = 'LoomitOfferwall'
  s.version          = '0.3.0-beta'
  s.summary          = 'Loomit Offerwall SDK - Unified offerwall monetization layer'
  s.description      = <<-DESC
    Loomit Offerwall SDK provides a unified monetization layer with multi-provider 
    adapters (Tapjoy, MyChips, Tyrads, Adjoe/Playtime, Digital Turbine/FairBid, etc.),
    remote configuration from backend, A/B testing, and server-side provider selection.
  DESC

  s.homepage         = 'https://github.com/nickloomit/loomit-offerwall-ios'
  s.license          = { :type => 'Proprietary', :text => 'Copyright Loomit. All rights reserved.' }
  s.author           = { 'Loomit' => 'support@loomit.com' }
  # For local development, use path. For release, use git URL with tag.
  # s.source           = { :git => 'https://github.com/nickloomit/loomit-offerwall-ios.git', :tag => s.version.to_s }
  s.source           = { :path => '.' }

  s.ios.deployment_target = '14.0'
  s.swift_versions = ['5.0', '5.9', '6.0']
  
  # Static framework to prevent duplicate symbols when linked in multiple targets
  s.static_framework = true
  
  # Single monolithic target — all sources compiled once into one library.
  # Subspec architecture causes duplicate symbols with use_frameworks! :linkage => :static
  # because each subspec that depends on Core embeds Core's symbols independently.
  s.source_files = [
    'LoomitOfferwallAdapterAPI/Sources/**/*.swift',
    'LoomitOfferwallCore/Sources/**/*.swift',
    'LoomitOfferwallDebug/Sources/**/*.swift',
    'LoomitOfferwallAdapterTapjoy/Sources/**/*.swift',
    'LoomitOfferwallAdapterMyChips/Sources/**/*.swift'
  ]

  s.resource_bundles = {
    'LoomitOfferwallCore' => ['LoomitOfferwallCore/Resources/**/*']
  }

  s.frameworks = 'Foundation', 'UIKit', 'AdSupport'

  # MyChips SDK vendored xcframework
  s.vendored_frameworks = 'Frameworks/MyChipsSdk.xcframework'

  # TapjoySDK via CocoaPod
  s.dependency 'TapjoySDK', '~> 14.0'

  s.pod_target_xcconfig = {
    'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'YES',
    'SWIFT_VERSION' => '5.0',
    'OTHER_LDFLAGS' => '-ObjC'
  }

end
