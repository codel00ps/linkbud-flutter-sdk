// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "linkbud_flutter",
    platforms: [.iOS(.v15)],
    products: [.library(name: "linkbud-flutter", targets: ["linkbud_flutter"])],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "linkbud_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
