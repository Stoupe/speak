import SpeakCore
import SwiftUI

/// The floating pill: live waveform while listening, a gentle wave while polishing. Once words arrive it
/// grows, like the Dynamic Island, into a glass card showing the text as it's recognized and cleaned up, and
/// shrinks back into the pill when the text is pasted. One glass shape throughout; only its size changes.
struct PillView: View {
    let model: PillModel

    private var expanded: Bool {
        if case .notice = model.phase { return false }
        return model.showsCard && !model.live.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.cardBelow {
                controls
                text
            } else {
                text
                controls
            }
        }
        .frame(width: expanded ? Metrics.cardWidth : nil)
        // The text is laid out at full width from the start; the clip reveals it as the shape grows.
        .clipShape(shape)
        .glassEffect(.regular, in: shape)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.glassFrame = $0 }
        // When both change at once (the final text arrives as the card closes), the open/close spring wins.
        .animation(expanded ? Metrics.open : Metrics.close, value: expanded)
        .animation(Metrics.grow, value: model.live)
        .gesture(WindowDragGesture())
        .padding(.vertical, Metrics.margin)
        // The pill stays put; the card grows away from it, upwards unless the pill is at the top of the screen.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.cardBelow ? .top : .bottom)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: expanded ? Metrics.cardCornerRadius : Metrics.pillHeight / 2, style: .continuous)
    }

    @ViewBuilder private var text: some View {
        if expanded {
            LiveText(live: model.live)
                .padding(.horizontal, Metrics.textInset)
                .padding(model.cardBelow ? .bottom : .top, Metrics.textInset - 4)
                .padding(model.cardBelow ? .top : .bottom, 2)
                .transition(AsymmetricTransition(
                    insertion: Reveal().animation(Metrics.reveal),
                    removal: Reveal().animation(Metrics.hide)))
        }
    }

    private var controls: some View {
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
        .frame(height: Metrics.pillHeight)
        .animation(.smooth(duration: 0.2), value: model.handsFree)
        .animation(.smooth(duration: 0.2), value: model.phase)
    }
}

/// Sizes and timing for the pill and its card, in one place for tuning.
private enum Metrics {
    static let pillHeight: CGFloat = 34
    static let cardWidth: CGFloat = 420
    static let cardCornerRadius: CGFloat = 22
    static let textInset: CGFloat = 18
    /// Room around the glass for its shadow inside the transparent panel (see `PillPanel.pillInset`).
    static let margin: CGFloat = 11

    /// Opening: a little bounce, like the Dynamic Island.
    static let open = Animation.spring(duration: 0.5, bounce: 0.25)
    /// Closing: settles without overshooting, so it doesn't wobble as the text is pasted.
    static let close = Animation.spring(duration: 0.4, bounce: 0.1)
    /// The card getting taller as lines are added.
    static let grow = Animation.smooth(duration: 0.35)
    /// Text settles in once the shape has mostly opened…
    static let reveal = Animation.easeOut(duration: 0.3).delay(0.18)
    /// …and leaves quickly when it closes, before the shape has shrunk much.
    static let hide = Animation.easeIn(duration: 0.12)
}

/// Fades and un-blurs content into place.
private struct Reveal: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .blur(radius: phase.isIdentity ? 0 : 8)
    }
}

/// The dictation so far: cleaned-up text in full colour, raw text waiting for cleanup dimmed, and words the
/// recognizer may still change dimmer still. Long dictations scroll, keeping the newest line in view.
private struct LiveText: View {
    static let maxHeight: CGFloat = 104

    let live: LiveTranscript
    @State private var textHeight: CGFloat = 0

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
