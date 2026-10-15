#if DEBUG
import AppKit

/// The app's side of `Tools/demo.sh`, which captures the scene. They talk through files in `/tmp/speak-demo`:
/// - `info` (app): `capture=…` and `region=x,y,w,h` (points, from the top left of the main display), in shell syntax;
/// - `start` (script): play the steps, so a recording catches them from the beginning;
/// - `done` (app): the steps have played;
/// - `menu` (app, menu scenes): `region=…` around the menu, once the script has opened it.
@MainActor
enum DemoCapture {
    private static let directory = URL(filePath: "/tmp/speak-demo")

    static func announce(_ capture: DemoScene.Capture, region frame: NSRect) {
        write("info", "capture=\(capture.rawValue)\nregion=\(format(globalRect(frame)))\n")
    }

    static func waitForStart() async {
        let url = directory.appending(path: "start")
        while !FileManager.default.fileExists(atPath: url.path) { await delay(0.05) }
    }

    static func finished() {
        write("done", "")
    }

    /// Waits for the script to open the menu, then reports where it is, with room around it (but not over the
    /// menu bar).
    static func reportMenu() async {
        let pid = ProcessInfo.processInfo.processIdentifier
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        while true {
            let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
            if let menu = windows.first(where: {
                $0[kCGWindowOwnerPID as String] as? pid_t == pid && $0[kCGWindowLayer as String] as? Int == menuLevel
            }),
               let bounds = menu[kCGWindowBounds as String] as? NSDictionary,
               let rect = CGRect(dictionaryRepresentation: bounds),
               let screen = NSScreen.screens.first {
                let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
                var region = rect.insetBy(dx: -40, dy: -40)
                region.size.height -= max(0, menuBarHeight - region.minY)
                region.origin.y = max(region.minY, menuBarHeight)
                await delay(0.5) // let it finish appearing
                write("menu", "region=\(format(region))\n")
                return
            }
            await delay(0.1)
        }
    }

    /// AppKit's bottom-left screen coordinates → the top-left ones `screencapture` and window lists use.
    private static func globalRect(_ frame: NSRect) -> CGRect {
        let height = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
    }

    private static func format(_ rect: CGRect) -> String {
        [rect.minX, rect.minY, rect.width, rect.height].map { String(Int($0.rounded())) }.joined(separator: ",")
    }

    private static func write(_ name: String, _ contents: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? contents.write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
    }
}

/// `Task.sleep` in seconds, ignoring cancellation.
func delay(_ seconds: Double) async {
    guard seconds > 0 else { return }
    try? await Task.sleep(for: .seconds(seconds))
}
#endif
