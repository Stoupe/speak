#if DEBUG
import SwiftUI

/// The text field of the backdrop's app: where demo dictations are pasted.
@MainActor
@Observable
final class DemoDocument {
    /// Typed but not sent.
    var draft = ""
    /// Sent with Return, oldest first.
    var sent: [String] = []

    func paste(_ text: String) {
        draft += text
    }

    func submit() {
        guard !draft.isEmpty else { return }
        sent.append(draft)
        draft = ""
    }
}

/// What sits behind the pill in a demo scene, so captures don't show whatever happens to be on screen: a
/// wallpaper-like gradient, optionally with a mock app window on it.
struct DemoBackdrop: View {
    enum Kind {
        case plain
        /// A blank email draft.
        case mail
        /// Claude Code in a terminal.
        case terminal
    }

    let kind: Kind
    let document: DemoDocument

    static func show(_ kind: Kind, document: DemoDocument, frame: NSRect) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        // Above normal windows, below the pill (status bar level).
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: DemoBackdrop(kind: kind, document: document))
        window.orderFrontRegardless()
        return window
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.98, green: 0.72, blue: 0.55), Color(red: 0.62, green: 0.55, blue: 0.95)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            switch kind {
            case .plain:
                EmptyView()
            case .mail:
                DemoMail(document: document)
                    .mockWindow(.white)
                    .padding(.horizontal, 90)
                    .padding(.top, 50)
                    .padding(.bottom, -40)
            case .terminal:
                DemoTerminal(document: document)
                    .mockWindow(DemoTerminal.background, title: "claude — weather-app")
                    .environment(\.colorScheme, .dark)
                    .padding(.horizontal, 60)
                    .padding(.top, 40)
                    .padding(.bottom, 130)
            }
        }
        .clipped()
    }
}

extension View {
    /// A plain macOS-style window around the content: rounded, with traffic lights and an optional title.
    func mockWindow(_ background: Color, title: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if let title {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 7) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.8)).frame(width: 11) }
                    Spacer()
                }
            }
            .padding(14)
            self
            Spacer(minLength: 0)
        }
        .background(background, in: .rect(cornerRadius: 14))
        .compositingGroup()
        .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
    }
}

private struct DemoMail: View {
    let document: DemoDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            field("To:", "Sam")
            field("Subject:", "Launch")
            Text(document.draft)
                .font(.system(size: 13))
                .padding(18)
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(label).foregroundStyle(.secondary)
                Text(value)
                Spacer()
            }
            .font(.system(size: 13))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            Divider().padding(.leading, 18)
        }
    }
}
#endif
