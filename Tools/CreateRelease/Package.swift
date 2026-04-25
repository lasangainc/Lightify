// swift-tools-version: 5.9
// Build: cd Tools/CreateRelease && swift build -c release
// Run:  .build/release/CreateRelease --help

import PackageDescription

let package = Package(
    name: "CreateRelease",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "create-release", targets: ["CreateRelease"])
    ],
    targets: [
        .executableTarget(
            name: "CreateRelease",
            path: "Sources/CreateRelease",
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        )
    ]
)
