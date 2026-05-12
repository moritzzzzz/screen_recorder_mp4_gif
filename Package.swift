// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenRecorder",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ScreenRecorder",
            path: "Sources/ScreenRecorder",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UniformTypeIdentifiers"),
            ]
        )
    ]
)
