// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "AICCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "AICCore", targets: ["AICCore"]),
        .executable(name: "AICCoreValidation", targets: ["AICCoreValidation"]),
        .executable(name: "AICPackStatusValidation", targets: ["AICPackStatusValidation"])
    ],
    targets: [
        .target(
            name: "AICCore",
            path: "AICCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "AICCoreTests",
            dependencies: ["AICCore"],
            path: "Tests/AICCoreTests"
        ),
        .executableTarget(
            name: "AICCoreValidation",
            dependencies: ["AICCore"],
            path: "Validation",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "AICPackStatusValidation",
            dependencies: ["AICCore"],
            path: "StatusValidation"
        )
    ]
)
