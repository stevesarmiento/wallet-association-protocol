// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "WalletAssociationProtocol",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(name: "WalletAssociationCore", targets: ["WalletAssociationCore"]),
        .library(name: "WalletAssociationLocalhost", targets: ["WalletAssociationLocalhost"]),
        .library(name: "WalletAssociationRelay", targets: ["WalletAssociationRelay"])
    ],
    targets: [
        .target(
            name: "WalletAssociationCore",
            path: "Sources/WalletAssociationCore"
        ),
        .target(
            name: "WalletAssociationLocalhost",
            dependencies: ["WalletAssociationCore"],
            path: "Sources/WalletAssociationLocalhost"
        ),
        .target(
            name: "WalletAssociationRelay",
            dependencies: ["WalletAssociationCore"],
            path: "Sources/WalletAssociationRelay"
        ),
        .testTarget(
            name: "WalletAssociationCoreTests",
            dependencies: ["WalletAssociationCore"],
            path: "Tests/WalletAssociationCoreTests"
        ),
        .testTarget(
            name: "WalletAssociationLocalhostTests",
            dependencies: ["WalletAssociationCore", "WalletAssociationLocalhost"],
            path: "Tests/WalletAssociationLocalhostTests"
        ),
        .testTarget(
            name: "WalletAssociationRelayTests",
            dependencies: ["WalletAssociationCore", "WalletAssociationRelay"],
            path: "Tests/WalletAssociationRelayTests"
        )
    ]
)
