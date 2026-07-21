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
    ],
    targets: [
        .target(name: "TranscriberDomain"),
        .testTarget(
            name: "TranscriberDomainTests",
            dependencies: ["TranscriberDomain"]
        ),
    ]
)
