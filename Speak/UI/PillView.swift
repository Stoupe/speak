import SpeakCore
import SwiftUI

/// The floating capsule: live waveform while listening, a gentle wave while polishing. Once words arrive, a
/// glass card grows out of it showing the text as it's recognized and cleaned up, and folds back into the
/// capsule when the text is pasted.
struct PillView: View {
    static let cardWidth: CGFloat = 420

    let model: PillModel
    @Namespace private var glass

    private var cardVisible: Bool {
        if case .notice = model.phase { return false }
        return model.showsCard && !model.live.isEmpty
    }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 10) {
                if model.cardBelow {
                    capsule
                    card
                } else {
                    card
                    capsule
                }
            }
        }
        .animation(.spring(duration: 0.5, bounce: 0.2), value: cardVisible)
        .padding(.vertical, 11)
        // Leave room around the glass for its shadow inside the transparent panel.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.cardBelow ? .top : .bottom)
    }

    private var capsule: some View {
        HStack(spacing: 8) {
            switch model.phase {
            case .listening:
                Waveform(levels: model.levels)
                if model.handsFree {
                    Button(action: model.onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 18, height: 18)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .transition(.scale.combined(with: .opacity))
                }
            case .processing:
                ThinkingWave()
            case .notice(let message):
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .glassEffect(.regular, in: .capsule)
        .glassEffectID("capsule", in: glass)
        .animation(.smooth(duration: 0.2), value: model.handsFree)
        .animation(.smooth(duration: 0.2), value: model.phase)
        .gesture(WindowDragGesture())
    }

    @ViewBuilder private var card: some View {
        if cardVisible {
            LiveText(live: model.live)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(width: Self.cardWidth)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
                .glassEffectID("card", in: glass)
                .glassEffectTransition(.matchedGeometry)
                .transition(.blurReplace)
                // The card grows a line at a time as you talk.
                .animation(.smooth(duration: 0.35), value: model.live)
                .gesture(WindowDragGesture())
        }
    }
}

/// The dictation so far: cleaned-up text in full colour, raw text waiting for cleanup dimmed, and words the
/// recognizer may still change dimmer still. Long dictations scroll, keeping the newest line in view.
private struct LiveText: View {
    static let maxHeight: CGFloat = 104

    let live: LiveTranscript
    @State private var textHeight: CGFloat = 0
    @State private var revealed = false

    var body: some View {
        Text(styled)
            .font(.system(size: 14))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Words that stay put stay put; new and repaired ones fade in.
            .contentTransition(.interpolate)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
            .frame(maxHeight: Self.maxHeight, alignment: .bottom)
            .fixedSize(horizontal: false, vertical: true)
            .clipped()
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: textHeight > Self.maxHeight ? .clear : .black, location: 0),
                        .init(color: .black, location: 0.22),
                    ],
                    startPoint: .top, endPoint: .bottom)
            }
            // The text settles in just after the glass has opened.
            .opacity(revealed ? 1 : 0)
            .blur(radius: revealed ? 0 : 6)
            .onAppear {
                withAnimation(.easeOut(duration: 0.4).delay(0.15)) { revealed = true }
            }
    }

    private var styled: AttributedString {
        let polished = AttributedString(live.polished)
        var pending = AttributedString(live.pending)
        pending.foregroundColor = .secondary
        var volatile = AttributedString(live.volatile)
        volatile.foregroundColor = Color.secondary.opacity(0.6)
        return polished + pending + volatile
    }
}

private struct Waveform: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .frame(width: 2.5, height: 4 + CGFloat(levels[index]) * 16)
            }
        }
        .foregroundStyle(.primary.opacity(0.85))
        .animation(.easeOut(duration: 0.08), value: levels)
        .frame(height: 20)
    }
}

/// Bars rippling in a slow sine wave: "working on it".
private struct ThinkingWave: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<PillModel.barCount, id: \.self) { index in
                    let phase = t * 5 - Double(index) * 0.35
                    Capsule()
                        .frame(width: 2.5, height: 4 + 6 * (1 + sin(phase)) / 2)
                        .opacity(0.35 + 0.4 * (1 + sin(phase)) / 2)
                }
            }
            .frame(height: 20)
        }
        .foregroundStyle(.primary)
    }
}
