import Foundation
import FoundationModels
import SpeakCore

/// Cleans up transcripts with Apple's on-device Foundation Model.
public final class FoundationModelsPolisher: TextPolisher {
    private let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
    /// Created on prewarm and consumed by the next polish, so the model is warm when Fn is released.
    private let warmSession = Locked<(context: PolishContext, session: LanguageModelSession)?>(nil)

    public init() {}

    public func availability() -> PolisherAvailability {
        switch model.availability {
        case .available:
            return .available
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(reason: "Apple Intelligence is turned off")
        case .unavailable(.deviceNotEligible):
            return .unavailable(reason: "This Mac doesn't support Apple Intelligence")
        case .unavailable(.modelNotReady):
            return .unavailable(reason: "Apple Intelligence model is still downloading")
        case .unavailable:
            return .unavailable(reason: "Apple Intelligence is unavailable")
        }
    }

    public func prewarm(context: PolishContext) {
        guard model.isAvailable else { return }
        let session = makeSession(context)
        session.prewarm()
        warmSession.withLock { $0 = (context, session) }
    }

    public func polish(_ raw: String, context: PolishContext) async throws -> String {
        let session = warmSession.withLock { warm in
            defer { warm = nil }
            return warm?.context == context ? warm?.session : nil
        } ?? makeSession(context)

        let response = try await session.respond(
            to: PolishPrompt.prompt(raw),
            generating: CleanedTranscript.self,
            options: GenerationOptions(
                samplingMode: .greedy,
                maximumResponseTokens: max(64, raw.count / 2 + 64)))
        return response.content.text
    }

    private func makeSession(_ context: PolishContext) -> LanguageModelSession {
        LanguageModelSession(model: model, instructions: PolishPrompt.instructions(context))
    }
}

@Generable
struct CleanedTranscript {
    @Guide(description: "The cleaned-up transcript, and nothing else.")
    var text: String
}
