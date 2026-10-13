// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TVProfilePicker",
    platforms: [
        .tvOS(.v17),
        // macOS only so `swift test` runs on CI; the views are made for Apple TV.
        .macOS(.v14),
    ],
    products: [
        .library(name: "TVProfilePicker", targets: ["TVProfilePicker"]),
    ],
    targets: [
        .target(name: "TVProfilePicker"),
        .testTarget(name: "TVProfilePickerTests", dependencies: ["TVProfilePicker"]),
    ]
)
