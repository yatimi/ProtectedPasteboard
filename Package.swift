// swift-tools-version: 6.2
//
//  Package.swift
//  ProtectedPasteboard
//
//  Created by Tommy on 04.08.2026.
//

import PackageDescription

let package = Package(
    name: "ProtectedPasteboard",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "ProtectedPasteboard",
            targets: ["ProtectedPasteboard"]
        ),
    ],
    targets: [
        .target(name: "ProtectedPasteboard"),
        .testTarget(
            name: "ProtectedPasteboardTests",
            dependencies: ["ProtectedPasteboard"]
        ),
    ]
)
