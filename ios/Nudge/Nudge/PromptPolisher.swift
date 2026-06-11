// PromptPolisher.swift — Nudge (iOS)
// Turns a terse, quickly-jotted "Claude - …" note into a clearer prompt using
// Apple's on-device model (FoundationModels, iOS 26 Apple Intelligence) — free,
// private, no API key. Falls back to the raw note if the model is unavailable
// (e.g. Apple Intelligence off, or running in the Simulator).

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum PromptPolisher {
    static let instructions = """
    You rewrite a user's terse, quickly-jotted note into a single clear, well-formed prompt for an AI assistant. \
    Preserve the original intent exactly. Do NOT invent specifics, constraints, topics, or details the user did not write. \
    If the note is already clear, return it almost unchanged. Keep it concise. \
    Output ONLY the rewritten prompt — no preamble, quotes, labels, or explanation.
    """

    /// Returns a polished prompt, or the original note if polishing isn't possible.
    static func polish(_ note: String) async -> String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return note }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else { return note }
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: trimmed)
                let out = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return out.isEmpty ? note : out
            } catch {
                return note
            }
        }
        #endif
        return note
    }
}
