// swift-tools-version: 5.9
//
// CI / テスト専用のパッケージ定義です。
//
// iPad の Swift Playgrounds で開くのは `SiliconFlowLab.swiftpm` の方です。
// こちらは同じソース（SiliconFlowKit）を Linux / macOS でビルド・テストするためのもので、
// AppleProductTypes（Playgrounds 専用）に依存しないので `swift test` で動きます。

import PackageDescription

let kitPath = "SiliconFlowLab.swiftpm/Sources/SiliconFlowKit"

let package = Package(
    name: "SiliconFlowLabCI",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
    ],
    products: [
        .library(name: "SiliconFlowKit", targets: ["SiliconFlowKit"]),
        .executable(name: "catalog-builder", targets: ["CatalogBuilder"]),
    ],
    targets: [
        .target(
            name: "SiliconFlowKit",
            path: kitPath
        ),
        .executableTarget(
            name: "CatalogBuilder",
            dependencies: ["SiliconFlowKit"],
            path: "Tools/CatalogBuilder"
        ),
        .testTarget(
            name: "SiliconFlowKitTests",
            dependencies: ["SiliconFlowKit"],
            path: "Tests/SiliconFlowKitTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
