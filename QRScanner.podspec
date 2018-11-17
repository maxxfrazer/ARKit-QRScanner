Pod::Spec.new do |s|
  # ―――  Spec Metadata  ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  s.name         = "QRScanner"
  s.version      = "0.2.0"
  s.summary      = "QRScanner helps to scan QR codes in ARKit"
  s.description  = <<-DESC
  					QRScanner scans an ARFrame, CIImage or CVPixelBuffer for a QR Code.
                   DESC
  s.homepage     = "https://github.com/maxxfrazer/ARKit-QRScanner"
  # ―――  Spec License  ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  s.license      = "MIT"
  # ――― Author Metadata  ――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  s.author             = "Max Cobb"
  # ――― Source Location ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  s.source       = { :git => "https://github.com/maxxfrazer/ARKit-QRScanner.git", :tag => "#{s.version}" }
  s.swift_version = '4.1'
  s.ios.deployment_target = '12.0'
  # ――― Source Code ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  s.source_files  = "ARKit-QRScanner/*.swift"
end
