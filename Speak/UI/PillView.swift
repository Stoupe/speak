import SwiftUI

/// The floating capsule: live waveform while listening, a gentle wave while polishing.
struct PillView: View {
    let model: PillModel

    var body: some View {
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
        .animation(.smooth(duration: 0.2), value: model.handsFree)
        .animation(.smooth(duration: 0.2), value: model.phase)
        .gesture(WindowDragGesture())
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.onResetPosition() })
        // Leave room around the capsule for its shadow inside the transparent panel.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
