import Observation
import SpeakCore
import SwiftUI

@MainActor
@Observable
final class PillModel {
    enum Phase: Equatable {
        case listening
        case processing
        /// A short message (e.g. "Microphone access needed") shown briefly.
        case notice(String)
    }

    static let barCount = 24

    /// Whether the panel should be on screen. Kept separate from `phase` so the content doesn't change while fading out.
    var isVisible = false
    var phase: Phase = .listening
    var handsFree = false
    /// The text card above the pill. It opens with the first words and closes back into the pill as the
    /// text is pasted.
    var showsCard = false
    var live = LiveTranscript()
    /// The card opens below the pill when there's no room above it (pill dragged to the top of the screen).
    var cardBelow = false
    /// Where the glass is drawn, in the panel's content view (origin top left). Clicks elsewhere in the panel
    /// fall through to the app underneath.
    @ObservationIgnored var glassFrame = CGRect.zero
    /// Most recent loudness values, oldest first.
    private(set) var levels = [Float](repeating: 0, count: PillModel.barCount)

    @ObservationIgnored var onCancel: () -> Void = {}

    func push(_ newLevels: [Float]) {
        guard !newLevels.isEmpty else { return }
        levels.append(contentsOf: newLevels)
        levels.removeFirst(max(0, levels.count - Self.barCount))
    }

    func resetLevels() {
        levels = [Float](repeating: 0, count: Self.barCount)
    }
}
