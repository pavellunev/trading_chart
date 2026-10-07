// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TradingChart",
    defaultLocalization: "en",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "TradingChart", targets: ["TradingChart"]),
        .library(name: "TradingChartCore", targets: ["TradingChartCore"]),
        .library(name: "TradingChartIndicators", targets: ["TradingChartIndicators"]),
    ],
    targets: [
        .target(name: "TradingChartCore"),
        .target(
            name: "TradingChartIndicators",
            dependencies: ["TradingChartCore"]
        ),
        .target(
            name: "TradingChart",
            dependencies: ["TradingChartCore", "TradingChartIndicators"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "TradingChartCoreTests",
            dependencies: ["TradingChartCore"]
        ),
        .testTarget(
            name: "TradingChartIndicatorsTests",
            dependencies: ["TradingChartIndicators", "TradingChartCore"]
        ),
        .testTarget(
            name: "TradingChartTests",
            dependencies: ["TradingChart"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
