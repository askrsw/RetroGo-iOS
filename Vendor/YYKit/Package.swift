// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription


let package = Package(
    name: "YYKit",
    platforms: [ .iOS(.v13) ],
    products: [
        .library(name: "YYBase", targets: ["YYBase"]),
        .library(name: "YYUtility", targets: ["YYUtility"]),
        .library(name: "YYCache", targets: ["YYCache"]),
        .library(name: "YYImage", targets: ["YYImage"]),
        .library(name: "YYText", targets: ["YYText"]),
    ],
    targets: [
        .target(
            name: "YYBase",
            path: "Sources/Base",
            publicHeadersPath: "Include",
            cSettings: [
                .headerSearchPath("Foundation"),
                .headerSearchPath("UIKit"),
                .headerSearchPath("Quartz")
            ]),
        .target(
            name: "YYUtility",
            dependencies: [ "YYBase" ],
            path: "Sources/Utility",
            publicHeadersPath: "Include"),
        .target(
            name: "YYModel",
            path: "Sources/Model",
            publicHeadersPath: "Include"),
        .target(
            name: "YYCache",
            dependencies: [ "YYBase" ],
            path: "Sources/Cache",
            publicHeadersPath: "Include"),
        .target(
            name: "YYImage",
            dependencies: [ "YYCache", "YYUtility" ],
            path: "Sources/Image",
            publicHeadersPath: "Include",
            cSettings: [ .headerSearchPath("Categories") ]),
        .target(
            name: "YYText",
            dependencies: [ "YYImage", "YYBase", "YYUtility" ],
            path: "Sources/Text",
            publicHeadersPath: "Include",
            cSettings: [
                .headerSearchPath("Component"),
                .headerSearchPath("String")
            ])
    ]
)
