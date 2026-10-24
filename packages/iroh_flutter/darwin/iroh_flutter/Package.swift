// swift-tools-version: 5.9
//
// iOS and macOS part of the iroh_flutter plugin for Swift Package Manager.
//
// A Swift package cannot run cargo during the build, because Xcode runs build tool plugins in a
// sandbox. Thus this package does not use cargokit. It uses the prebuilt dynamic framework
// irohdart_ffi.xcframework. The workflow .github/workflows/xcframework.yml builds this framework
// from ../../rust and attaches it to the GitHub release `xcframework-v<version>`. The workflow
// also writes `version` and `checksum` below. The release workflow makes sure that the framework
// agrees with the crate before it publishes the plugin.
//
// For local development, run `tool/build_xcframework.sh` in the root of the repository. The
// script writes the framework to Frameworks/irohdart_ffi.xcframework in this directory. If this
// directory contains the framework, the package uses it and does not download the release.
//
// CocoaPods does not use this file. It uses ../iroh_flutter.podspec.

import Foundation
import PackageDescription

let version = "1.2.0"
let checksum = "0000000000000000000000000000000000000000000000000000000000000000"

let localFramework = "Frameworks/irohdart_ffi.xcframework"
let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let hasLocalFramework = FileManager.default.fileExists(
    atPath: packageDirectory.appendingPathComponent(localFramework).path)

let nativeLibrary: Target = hasLocalFramework
    ? .binaryTarget(name: "irohdart_ffi", path: localFramework)
    : .binaryTarget(
        name: "irohdart_ffi",
        url: "https://github.com/snowpinelabs/iroh_dart/releases/download/xcframework-v\(version)/irohdart_ffi.xcframework.zip",
        checksum: checksum)

let package = Package(
    name: "iroh_flutter",
    platforms: [
        .iOS("13.0"),
        .macOS("11.0"),
    ],
    products: [
        .library(name: "iroh-flutter", targets: ["iroh_flutter"]),
    ],
    // Flutter writes the FlutterFramework package next to the plugin packages. The flutter tool
    // requires this dependency in each plugin package.
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "iroh_flutter",
            dependencies: [
                "irohdart_ffi",
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ]
        ),
        nativeLibrary,
    ]
)
