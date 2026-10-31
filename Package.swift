// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Weft",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "WeftCore", targets: ["WeftCore"]),
        .library(name: "WeftUI", targets: ["WeftUI"]),
        .library(name: "WeftGitHub", targets: ["WeftGitHub"]),
        .executable(name: "weft", targets: ["weft"]),
        .executable(name: "WeftMac", targets: ["WeftMac"]),
    ],
    dependencies: [
        // The Reflect graph the wiki lives in, and the sync it shares.
        .package(path: "../reflect-mac"),
    ],
    targets: [
        // Tiddlers, their files, the wiki they make, and TiddlyWiki's import.
        // No AppKit or UIKit.
        .target(name: "WeftCore", dependencies: [.product(name: "ReflectCore", package: "reflect-mac")]),
        // The command line: importing a TiddlyWiki into a graph, and looking
        // at what is there.
        .executableTarget(name: "weft", dependencies: ["WeftCore"]),
        // The river of cards, its sidebar, cards and editor: the Mac's, the
        // iPad's and the iPhone's.
        .target(name: "WeftUI", dependencies: ["WeftCore", .product(name: "ReflectCore", package: "reflect-mac")]),
        // A graph kept in a GitHub repository, synced through libgit2 with
        // the account signed in with: the phone's.
        .target(name: "WeftGitHub", dependencies: ["WeftCore", .product(name: "ReflectGit2", package: "reflect-mac")]),
        // The Mac app around it. Wrapped as Weft.app by scripts/build-app.sh.
        .executableTarget(name: "WeftMac", dependencies: ["WeftCore", "WeftUI", "WeftGitHub", .product(name: "ReflectCore", package: "reflect-mac")]),
        .testTarget(name: "WeftCoreTests", dependencies: ["WeftCore"]),
    ],
    swiftLanguageModes: [.v5]
)
