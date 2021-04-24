// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftyHealthKit",
    platforms: [
        .iOS(.v14), .watchOS(.v7)
    ],
    products: [
        .library(name: "SwiftyHealthKit",targets: ["SwiftyHealthKit"]),
    ],
    dependencies: [
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "SwiftyHealthKit",
            dependencies: []
        ),
        .testTarget(
            name: "SwiftyHealthKitTests",
            dependencies: ["SwiftyHealthKit"]
        ),
    ]
)
