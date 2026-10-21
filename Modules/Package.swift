// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "SafwResearch", platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "SafwResearch", targets: ["SafwResearch"])],
    dependencies: [
        .package(path: "../../Packages/WhoopProtocol"),
        .package(path: "../../Packages/WhoopStore"),
        .package(path: "../../Packages/StrandAnalytics"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "6.29.3")
    ],
    targets: [
        .target(name: "SafwResearch", dependencies: [
            .product(name: "WhoopProtocol", package: "WhoopProtocol"),
            .product(name: "WhoopStore", package: "WhoopStore"),
            .product(name: "StrandAnalytics", package: "StrandAnalytics"),
            .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "SafwResearchTests", dependencies: [
            "SafwResearch",
            .product(name: "WhoopProtocol", package: "WhoopProtocol"),
            .product(name: "WhoopStore", package: "WhoopStore"),
            .product(name: "GRDB", package: "GRDB.swift")])
    ]
)
