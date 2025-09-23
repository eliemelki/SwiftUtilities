// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LBSwiftUtilities",
    platforms: [ .iOS(.v15) ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "LBSwiftUtilities",
            targets: ["LBSwiftUtilities"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "LBSwiftUtilities"),
        .testTarget(
            name: "LBSwiftUtilitiesTests",
            dependencies: ["LBSwiftUtilities"]
        ),
    ]
)
for target in package.targets {
    var settings = target.swiftSettings ?? []
    settings.append(.unsafeFlags(["-Xfrontend", "-strict-concurrency=minimal"]))
    target.swiftSettings = settings
}
