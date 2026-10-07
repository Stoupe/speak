import Foundation

/// Writing style inferred from the app that will receive the text.
public enum AppStyle: String, Sendable, Equatable, CaseIterable {
    case general
    case chat
    case email
    /// Terminals, editors, IDEs: keep wording literal, no prose flourishes.
    case code

    public static func forBundleID(_ bundleID: String?) -> AppStyle {
        guard let id = bundleID?.lowercased() else { return .general }
        if chatApps.contains(id) { return .chat }
        if emailApps.contains(id) { return .email }
        if codeApps.contains(id) || codePrefixes.contains(where: id.hasPrefix) { return .code }
        return .general
    }

    private static let chatApps: Set<String> = [
        "com.tinyspeck.slackmacgap",
        "com.apple.mobilesms",
        "com.hnc.discord",
        "net.whatsapp.whatsapp",
        "desktop.whatsapp",
        "ru.keepcoder.telegram",
        "com.microsoft.teams2",
        "com.facebook.archon",
        "org.whispersystems.signal-desktop",
    ]

    private static let emailApps: Set<String> = [
        "com.apple.mail",
        "com.microsoft.outlook",
        "com.readdle.smartemail-mac",
        "com.superhuman.electron",
        "com.mimestream.mimestream",
    ]

    private static let codeApps: Set<String> = [
        "com.apple.dt.xcode",
        "com.microsoft.vscode",
        "com.microsoft.vscodeinsiders",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.apple.terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.warp-stable",
        "dev.zed.zed",
        "com.sublimetext.4",
        "com.panic.nova",
    ]

    private static let codePrefixes = ["com.jetbrains."]
}
