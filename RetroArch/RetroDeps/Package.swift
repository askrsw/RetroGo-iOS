// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let defines: [CSetting] = [
    .define("FLAC__HAS_OGG", to: "0"),
    .define("HAVE_7ZIP"),
    .define("HAVE_ACCESSIBILITY"),
    .define("HAVE_AL"),
    .define("HAVE_AUDIOMIXER"),
    .define("HAVE_BSV_MOVIE"),
    .define("HAVE_CC_RESAMPLER"),
    .define("HAVE_CHD"),
    .define("HAVE_CHEATS"),
    .define("HAVE_CHEEVOS"),
    .define("HAVE_CLOUDSYNC"),
    .define("HAVE_COCOA_METAL"),
    .define("HAVE_COMMAND"),
    .define("HAVE_CONFIGFILE"),
    .define("HAVE_COREAUDIO"),
    .define("HAVE_CORELOCATION"),
    .define("HAVE_CORETEXT"),
    .define("HAVE_DR_FLAC"),
    .define("HAVE_DR_MP3"),
    .define("HAVE_DSP_FILTER"),
    .define("HAVE_DYNAMIC"),
    .define("HAVE_EASTEREGG"),
    .define("HAVE_FILTERS_BUILTIN"),
    .define("HAVE_FLAC"),
    .define("HAVE_GCD"),
    .define("HAVE_GLSL"),
    .define("HAVE_GLSLANG"),
    .define("HAVE_HID"),
    .define("HAVE_IFINFO"),
    .define("HAVE_IMAGEVIEWER"),
    .define("HAVE_LANGEXTRA"),
    .define("HAVE_LIBRETRODB"),
    .define("HAVE_METAL"),
    .define("HAVE_MFI"),
    .define("HAVE_MMAP"),
    .define("HAVE_NEAREST_RESAMPLER"),
    .define("HAVE_NETPLAYDISCOVERY"),
    .define("HAVE_NETPLAYDISCOVERY_NSNET"),
    .define("HAVE_NETWORKGAMEPAD"),
    .define("HAVE_NETWORKING"),
    .define("HAVE_NETWORK_CMD"),
    .define("HAVE_OPENGL"),
    .define("HAVE_PATCH"),
    .define("HAVE_REWIND"),
    .define("HAVE_RUNAHEAD"),
    .define("HAVE_SCREENSHOTS"),
    .define("HAVE_SHADERPIPELINE"),
    .define("HAVE_SLANG"),
    .define("HAVE_SPIRV_CROSS"),
    .define("HAVE_SSL"),
    .define("HAVE_STB_FONT"),
    .define("HAVE_STB_VORBIS"),
    .define("HAVE_THREADS"),
    .define("HAVE_TRANSLATE"),
    .define("HAVE_VIDEO_FILTER"),
    .define("HAVE_VULKAN"),
    .define("HAVE_XDELTA"),
    .define("HAVE_ZLIB"),
    .define("HAVE_ZSTD"),
    .define("INLINE", to: "inline"),
    .define("RARCH_INTERNAL"),
    .define("RC_DISABLE_LUA"),
    .define("WANT_GLSLANG"),
    .define("WANT_RAW_DATA_SECTOR", to: "1"),
    .define("WANT_SUBCODE", to: "1"),
    .define("_7ZIP_ST"),
    .define("__LIBRETRO__"),
    .define("__ARM_NEON__"),
    .define("HAVE_NEON"),
    .define("GL_SILENCE_DEPRECATION", .when(platforms: [.macOS])),
    .define("HAVE_AVF", .when(platforms: [.macOS])),
    .define("HAVE_COREAUDIO3", .when(platforms: [.macOS])),
    .define("HAVE_COREMIDI", .when(platforms: [.macOS])),
    .define("HAVE_DISCORD", .when(platforms: [.macOS])),
    .define("HAVE_DYLIB", .when(platforms: [.macOS])),
    .define("HAVE_GETOPT_LONG", .when(platforms: [.macOS])),
    .define("HAVE_IOHIDMANAGER", .when(platforms: [.macOS])),
    .define("HAVE_OPENGL_CORE", .when(platforms: [.macOS])),
    .define("HAVE_PRESENCE", .when(platforms: [.macOS])),
    .define("HAVE_STDIN_CMD", .when(platforms: [.macOS])),
    .define("OSX", .when(platforms: [.macOS])),
    .define("GLES_SILENCE_DEPRECATION", .when(platforms: [.iOS, .tvOS])),
    .define("HAVE_BTSTACK", .when(platforms: [.iOS, .tvOS])),
    .define("HAVE_COCOATOUCH", .when(platforms: [.iOS, .tvOS])),
    .define("HAVE_MAIN", .when(platforms: [.iOS, .tvOS])),
    .define("HAVE_OPENGLES", to: "1", .when(platforms: [.iOS, .tvOS])),
    .define("HAVE_OPENGLES3", to: "1", .when(platforms: [.iOS, .tvOS])),
    .define("IOS", .when(platforms: [.iOS, .tvOS])),
    .define("RARCH_MOBILE", .when(platforms: [.iOS, .tvOS])),
    .define("HAVE_AVF", .when(platforms: [.iOS])),
    .define("HAVE_COREMIDI", .when(platforms: [.iOS])),
    .define("HAVE_COREMOTION", .when(platforms: [.iOS])),
    .define("DEBUG", to: "1", .when(configuration: .debug)),
    .define("_DEBUG", to: "1", .when(configuration: .debug)),
    .define("NDEBUG", to: "1", .when(configuration: .release)),
    .define("NS_BLOCK_ASSERTIONS", to: "1", .when(configuration: .release)),

    //from griffin.c
    .define("VFS_FRONTEND"),
    .define("HAVE_IBXM", to: "1"),
    .define("HAVE_COMPRESSION", to: "1"),
    .define("RC_CLIENT_SUPPORTS_HASH", to: "1"),

    .define("HAVE_RBMP"),
    .define("HAVE_RJPEG"),
    .define("HAVE_RPNG"),
    .define("HAVE_RTGA"),
    .define("HAVE_RWAV"),
    .define("HAVE_OVERLAY"),
    .define("HAVE_UPDATE_ASSETS"),
    .define("HAVE_UPDATE_CORE_INFO"),
    .define("HAVE_ONLINE_UPDATER", .when(platforms: [.iOS, .tvOS])),
]

let package = Package(
    name: "RetroDeps",
    defaultLocalization: "en",
    platforms: [ .iOS(.v15) ],
    products: [
        .library(name: "mbedtls", targets: ["mbedtls"]),
        .library(name: "yxml", targets: ["yxml"]),
        .library(name: "7zip", targets: ["7zip"]),
        .library(name: "zstd", targets: ["zstd"]),
        .library(name: "ibxm", targets: ["ibxm"]),
        .library(name: "rcheevos", targets: ["rcheevos"]),
        .library(name: "libFLAC", targets: ["libFLAC"]),
        .library(name: "spirvcross", targets: ["spirvcross"]),
        .library(name: "xdelta3", targets: ["xdelta3"]),
        .library(name: "libDR", targets: ["libDR"]),
        .library(name: "glslang", targets: ["glslang"]),
        .library(name: "stb", targets: ["stb"]),
        .library(name: "signalsmith", targets: ["signalsmith"]),
    ],
    dependencies: [
        .package(path: "../RetroBase"),
    ],
    targets: [
        .target(
            name: "glslang",
            cSettings: [
                .define("DEBUG", to: "1", .when(configuration: .debug)),
                .define("NDEBUG", to: "1", .when(configuration: .release)),
            ]
        ),
        .target(
            name: "stb",
            dependencies: [ .product(name: "RetroBase", package: "RetroBase") ],
            cSettings: defines
        ),
        .target(
            name: "libDR",
            dependencies: [ .product(name: "RetroBase", package: "RetroBase") ],
            cSettings: defines
        ),
        .target(
            name: "xdelta3",
            dependencies: [ .product(name: "RetroBase", package: "RetroBase") ],
            cSettings: defines
        ),
        .target(
            name: "spirvcross",
            cSettings: defines + [
                .unsafeFlags([
                    "-Wno-deprecated-this-capture",
                ]),
            ]
        ),
        .target(
            name: "libFLAC",
            dependencies: [ .product(name: "RetroBase", package: "RetroBase") ],
            cSettings: defines
        ),
        .target(
            name: "rcheevos",
            dependencies: [ .product(name: "RetroBase", package: "RetroBase") ],
            cSettings: defines + [
                .unsafeFlags([
                    "-Wno-shorten-64-to-32",
                    "-Wno-deprecated-declarations",
                ]),
            ]
        ),
        .target(
            name: "signalsmith",
            exclude: ["doc"],
            cxxSettings: [
                .define("SIGNALSMITH_USE_ACCELERATE", .when(platforms: [.iOS])),
                .define("ACCELERATE_NEW_LAPACK", .when(platforms: [.iOS])),
            ],
            linkerSettings: [
                .linkedFramework("Accelerate", .when(platforms: [.iOS])),
            ]
        ),
        .target(
            name: "ibxm",
            cSettings: defines
        ),
        .target(
            name: "zstd",
            cSettings: defines
        ),
        .target(
            name: "7zip",
            cSettings: defines
        ),
        .target(
            name: "yxml",
            dependencies: [ .product(name: "RetroBase", package: "RetroBase") ],
            cSettings: defines
        ),
        .target(
            name: "mbedtls",
            dependencies: [ .product(name: "RetroBase", package: "RetroBase") ],
            cSettings: defines
        ),
    ]
)
