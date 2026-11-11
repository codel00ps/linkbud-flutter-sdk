Pod::Spec.new do |s|
  s.name = 'linkbud_flutter'
  s.version = '1.0.0'
  s.summary = 'Flutter bridge to the LinkBud native SDKs.'
  s.description = 'Environment-scoped navigation hints and explicit recovery, using the unchanged native SDK sources.'
  s.homepage = 'https://github.com/codel00ps/linkbud-flutter-sdk'
  s.license = { :type => 'MIT', :file => '../LICENSE' }
  s.author = 'LinkBud'
  s.source = { :path => '.' }
  s.source_files = 'linkbud_flutter/Sources/linkbud_flutter/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.swift_version = '5.9'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
