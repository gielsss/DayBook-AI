// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PersonalPlanner",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "PersonalPlanner",
            targets: ["PersonalPlanner"]
        )
    ],
    targets: [
        .executableTarget(
            name: "PersonalPlanner",
            path: "Sources/PersonalPlanner"
        )
    ]
)
