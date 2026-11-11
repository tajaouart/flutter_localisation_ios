// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "FlutterLocalisation",
    platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
    products: [
        .library(name: "FlutterLocalisation", targets: ["FlutterLocalisation"]),
    ],
    targets: [
        .target(name: "FlutterLocalisation"),
        .testTarget(
            name: "FlutterLocalisationTests",
            dependencies: ["FlutterLocalisation"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
