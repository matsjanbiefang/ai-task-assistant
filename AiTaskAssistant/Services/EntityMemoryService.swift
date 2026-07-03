import Foundation
import SwiftData

// Milestone 8 (swipe-final-architecture.md §7): recording rules for EntityMemory. Stateless —
// no internal state to hold, just SwiftData operations against whichever ModelContext is passed
// in (same pattern NoteView already uses for its own modelContext).
enum EntityMemoryService {
    private static let initialConfidence = 0.3
    private static let confidenceStep = 0.15

    // Stage 3 input (feed, not yet consumed — see EntityMemory.swift): call on every AUTO
    // extraction that produced an entity-like value. Unknown entity -> stored at low confidence.
    // Repeat mention -> frequency grows and confidence climbs toward 1.0, capped there.
    static func recordMention(_ entity: String, type: EntityType, categoryHint: String?, context: ModelContext) {
        let trimmed = entity.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let existing = find(trimmed, context: context) {
            existing.frequency += 1
            existing.confidence = min(1.0, initialConfidence + Double(existing.frequency - 1) * confidenceStep)
            existing.lastSeen = .now
            if existing.categoryHint == nil {
                existing.categoryHint = categoryHint
            }
        } else {
            context.insert(EntityMemory(entity: trimmed, type: type, categoryHint: categoryHint, confidence: initialConfidence, source: .auto))
        }
    }

    // Stage 6: user correction is ground truth — immediate overwrite at confidence 1.0 regardless
    // of frequency ("corrections are ground truth; frequency is only a proxy", §7).
    static func recordCorrection(_ entity: String, type: EntityType, categoryHint: String?, context: ModelContext) {
        let trimmed = entity.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let existing = find(trimmed, context: context) {
            existing.frequency += 1
            existing.confidence = 1.0
            existing.lastSeen = .now
            existing.source = EntitySource.corrected.rawValue
            if let categoryHint {
                existing.categoryHint = categoryHint
            }
        } else {
            context.insert(EntityMemory(entity: trimmed, type: type, categoryHint: categoryHint, confidence: 1.0, source: .corrected))
        }
    }

    // Case-insensitive match done in Swift rather than via a #Predicate string-lowercasing call —
    // avoids relying on SwiftData's iOS-17 #Predicate string-operation support, and entity counts
    // for a personal task app are small enough that fetching all rows isn't a real concern.
    private static func find(_ entity: String, context: ModelContext) -> EntityMemory? {
        let all = (try? context.fetch(FetchDescriptor<EntityMemory>())) ?? []
        return all.first { $0.entity.caseInsensitiveCompare(entity) == .orderedSame }
    }
}
