import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// Milestone 9 (swipe-final-architecture.md §5). FM-3: on-device only, enforced by convention (no
// lint tooling in this project) — every reference goes through SystemLanguageModel.default; never
// construct a session against a remote/cloud configuration. Review checklist item, not automated.
//
// Requires Xcode 26 to compile against at all (FoundationModels doesn't exist in the Xcode 16.x
// SDK) — this file is written to still compile cleanly under Xcode 16.4 via #if canImport, since
// that's this project's default CI toolchain today.
enum FoundationModelsFallback {
    // Double gate (§5): device availability AND language availability. Callable unconditionally —
    // false on any OS/SDK where FoundationModels doesn't exist, so callers never need their own
    // #if canImport guard just to ask "is FM usable right now."
    static func isAvailable(forLanguageCode code: String) -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            guard case .available = SystemLanguageModel.default.availability else { return false }
            return SystemLanguageModel.default.supportsLocale(Locale(identifier: code))
        }
        #endif
        return false
    }

    #if canImport(FoundationModels)
    @available(iOS 26, *)
    @Generable
    struct RefinedFields {
        @Guide(description: "The task title, with date/time/priority phrases already removed")
        var title: String
        @Guide(description: "ISO 8601 date (YYYY-MM-DD) if the text states or implies a due date, otherwise omit this field")
        var dueDate: String?
        @Guide(description: "Priority level, only if explicitly stated or strongly implied", .anyOf(["low", "medium", "high"]))
        var priority: String?
    }

    // Stage 4 (§5): refines ONLY the candidate passed to it, with the rules output as context —
    // whether to call this at all (i.e. "is this candidate low-confidence") is the CALLER's
    // decision, matching "FM never overrides a high-confidence rules result": this function has no
    // opinion on that, it just refines when asked.
    //
    // NOT wired into RuleBasedExtractionService.extractLine yet (FM-2b, deferred) — extractLine is
    // fully synchronous; wiring an async call into it is a real pipeline change needing its own
    // design pass, and its actual behavior can't be verified in CI regardless (no Apple
    // Intelligence hardware exists on any CI runner).
    @available(iOS 26, *)
    static func refine(rawLine: String, rulesCandidate: ExtractedTask, languageCode: String) async -> RefinedFields? {
        guard isAvailable(forLanguageCode: languageCode) else { return nil }
        let session = LanguageModelSession(model: SystemLanguageModel(useCase: .contentTagging))
        let prompt = """
        Extract a task title, due date, and priority from this note line. The rules engine's best \
        guess is given as context — correct it only if you're confident it's wrong.

        Line: \(rawLine)
        Rules engine guess: title="\(rulesCandidate.title)", dueDate=\(rulesCandidate.dueDate ?? "none"), priority=\(rulesCandidate.priority?.rawValue ?? "none")
        """
        do {
            return try await session.respond(to: prompt, generating: RefinedFields.self).content
        } catch {
            return nil
        }
    }
    #endif
}
