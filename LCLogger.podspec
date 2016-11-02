Pod::Spec.new do |s|
  s.name = 'LCLogger'
  s.version = '1.3.3'
  s.summary = 'LogCentral logger for iOS'
  s.homepage = 'https://github.com/backav/ios-lclogger'
  s.author = { 'http://xiangyang.li' => 'wo@xiangyang.li' }
  s.source = { :git => 'https://github.com/backav/ios-lclogger.git', :tag => "#{s.version}" }
  s.source_files = 'LCLogger/*.{h,m}'
  s.ios.deployment_target = '6.0'
  s.requires_arc = true
  s.license = 'MIT'
end
