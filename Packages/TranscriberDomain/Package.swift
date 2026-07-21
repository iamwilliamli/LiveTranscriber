// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TranscriberDomain",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "TranscriberDomain",
            targets: ["TranscriberDomain"]
        ),
        .library(
            name: "TranscriberCore",
            targets: ["TranscriberCore"]
        ),
    ],
    targets: [
        .target(name: "TranscriberDomain"),
        .target(
            name: "TranscriberCore",
            dependencies: ["TranscriberDomain"]
        ),
        .testTarget(
            name: "TranscriberDomainTests",
            dependencies: ["TranscriberDomain"]
        ),
        .testTarget(
            name: "TranscriberCoreTests",
            dependencies: ["TranscriberCore", "TranscriberDomain"]
        ),
    ]
)
