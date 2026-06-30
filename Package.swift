// swift-tools-version:6.0
import PackageDescription

// NimbusKit is the pure-Swift domain/service core. It is intentionally
// FFI-free so it builds and unit-tests with no Rust toolchain present
// (`swift build`, `swift test`). The Rust accelerator, the SwiftUI app target,
// and the privileged helper are wired in the Xcode project — see
// docs/DISTRIBUTION.md and docs/FFI.md. NimbusKit talks to the accelerator only
// through the `ContentHashing` / `PerceptualHashing` protocols, which the Xcode
// app satisfies with the UniFFI-generated `nimbus_core` bindings.
let package = Package(
    name: "Nimbus",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NimbusKit", targets: ["NimbusKit"]),
        .library(name: "NimbusViewModels", targets: ["NimbusViewModels"]),
    ],
    targets: [
        .target(
            name: "NimbusKit",
            path: "Sources/NimbusKit",
            swiftSettings: [
                // Pragmatic first cut: Swift 5 language mode keeps the initial
                // build clean while we still use async/await + actors throughout.
                // Migrating to full Swift 6 strict concurrency is a tracked follow-up.
                .swiftLanguageMode(.v5)
            ]
        ),
        // The MVVM view models live here — UI logic with no SwiftUI dependency,
        // so they compile and unit-test headlessly. The Xcode app target adds the
        // thin SwiftUI views on top and injects the Rust-backed hashers.
        .target(
            name: "NimbusViewModels",
            dependencies: ["NimbusKit"],
            path: "Sources/NimbusViewModels",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "NimbusKitTests",
            dependencies: ["NimbusKit"],
            path: "Tests/NimbusKitTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "NimbusViewModelsTests",
            dependencies: ["NimbusViewModels"],
            path: "Tests/NimbusViewModelsTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
