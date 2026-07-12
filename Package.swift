// swift-tools-version:5.9
import Foundation
import PackageDescription

// Tooling (claude-mem) drops CLAUDE.md context files into target directories;
// exclude them from SPM only when present so builds stay warning-free.
func excludedNonSources(_ targetPath: String) -> [String] {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let candidate = root.appendingPathComponent(targetPath).appendingPathComponent("CLAUDE.md")
    return FileManager.default.fileExists(atPath: candidate.path) ? ["CLAUDE.md"] : []
}

let package = Package(
    name: "WindowKeeper",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "WindowKeeperCore", exclude: excludedNonSources("Sources/WindowKeeperCore")),
        .executableTarget(
            name: "WindowKeeper",
            dependencies: ["WindowKeeperCore"],
            exclude: excludedNonSources("Sources/WindowKeeper")
        ),
        .testTarget(
            name: "WindowKeeperCoreTests",
            dependencies: ["WindowKeeperCore"],
            exclude: excludedNonSources("Tests/WindowKeeperCoreTests")
        ),
    ]
)
