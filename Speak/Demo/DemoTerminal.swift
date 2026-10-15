#if DEBUG
import SwiftUI

/// A mock of Claude Code running in a terminal: welcome box, prompts sent so far, and the prompt box holding the
/// document's draft.
struct DemoTerminal: View {
    static let background = Color(red: 0.11, green: 0.11, blue: 0.12)
    private static let accent = Color(red: 0.85, green: 0.47, blue: 0.34)
    private static let dim = Color.white.opacity(0.45)

    let document: DemoDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            box(Self.accent) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(Text("✻ ").foregroundStyle(Self.accent))\(Text("Welcome to Claude Code!").bold())")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("/help for help, /status for your current setup")
                        Text("cwd: ~/dev/weather-app")
                    }
                    .foregroundStyle(Self.dim)
                    .padding(.leading, 18)
                }
            }

            ForEach(document.sent.indices, id: \.self) { index in
                Text("> " + document.sent[index]).foregroundStyle(Self.dim)
                if index == document.sent.indices.last { Thinking(accent: Self.accent) }
            }

            VStack(alignment: .leading, spacing: 6) {
                box(Self.dim) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("> ")
                        Text("\(document.draft)\(Text("█").foregroundStyle(Self.dim))")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text("? for shortcuts").foregroundStyle(Self.dim).padding(.leading, 18)
            }
        }
        .font(.system(size: 13, design: .monospaced))
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 18)
        .padding(.top, 4)
    }

    private func box(_ border: Color, @ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(border, lineWidth: 1))
    }
}

/// Claude Code's working indicator: a cycling star and a word.
private struct Thinking: View {
    let accent: Color
    private static let frames = ["·", "✢", "✳", "✶", "✻", "✽", "✻", "✶", "✳", "✢"]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.12)) { context in
            let index = Int(context.date.timeIntervalSinceReferenceDate / 0.12) % Self.frames.count
            Text(Self.frames[index] + " Thinking…")
                .foregroundStyle(accent)
        }
    }
}
#endif
