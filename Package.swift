// swift-tools-version:5.9
import PackageDescription

// HubiplanKern: alles, was ohne Oberfläche auskommt (Schnittstelle, Anmeldung, Formate, Push).
// Baut und testet auch unter Linux (WSL); dort ersetzt swift-crypto das CryptoKit von Apple.
let package = Package(
    name: "HubiplanKern",
    defaultLocalization: "de",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "HubiplanKern", targets: ["HubiplanKern"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "HubiplanKern",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
            ],
            resources: [.process("Texte"), .process("Gestaltung")]
        ),
        .testTarget(name: "HubiplanKernTests", dependencies: ["HubiplanKern"]),
    ]
)
