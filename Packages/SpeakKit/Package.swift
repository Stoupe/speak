// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SpeakKit",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "SpeakCore", targets: ["SpeakCore"]),
        .library(name: "SpeakEngines", targets: ["SpeakEngines"]),
        .executable(name: "speak-bench", targets: ["speak-bench"]),
    ],
    targets: [
        // Pure logic: trigger state machine, polish rules, history. No system frameworks beyond Foundation/AVFAudio.
        .target(name: "SpeakCore"),
        // On-device engines: Apple SpeechAnalyzer transcription and Foundation Models polishing.
        .target(name: "SpeakEngines", dependencies: ["SpeakCore"]),
        // Headless dev tool: run engines against audio files / text without launching the app.
        .executableTarget(name: "speak-bench", dependencies: ["SpeakCore", "SpeakEngines"]),
        .testTarget(name: "SpeakCoreTests", dependencies: ["SpeakCore"]),
    ]
)
