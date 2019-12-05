// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "QRScanner",
  platforms: [.iOS("12.0")],
  products: [
    .library(name: "QRScanner", targets: ["QRScanner"])
  ],
  targets: [
    .target(name: "QRScanner", path: "ARKit-QRScanner")
  ],
  swiftLanguageVersions: [.v5]
)
