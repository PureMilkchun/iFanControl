// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MacFanControl",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(
            name: "FanCurveEditor",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation")
            ]
        ),
        .executableTarget(
            name: "MacFanControl",
            dependencies: ["FanCurveEditor"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation")
            ]
        ),
    ]
)
