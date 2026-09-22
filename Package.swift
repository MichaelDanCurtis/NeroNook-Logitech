// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "NeroNookLogitech", platforms: [.macOS(.v14)], products: [.executable(name: "LogitechPlugin", targets: ["LogitechPlugin"])], dependencies: [.package(path: "Vendor/NookPluginSDK")], targets: [
    .target(name: "LogitechCore", swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(name: "LogitechPlugin", dependencies: ["LogitechCore", .product(name: "NookPluginSDK", package: "NookPluginSDK")], swiftSettings: [.swiftLanguageMode(.v5)]),
    .testTarget(name: "LogitechCoreTests", dependencies: ["LogitechCore"], swiftSettings: [.swiftLanguageMode(.v5)])])
