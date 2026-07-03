import Foundation
import SwiftData

enum EntityType: String, Codable, CaseIterable, Sendable {
    case person, place, thing
}

enum EntitySource: String, Codable, CaseIterable, Sendable {
    case auto, corrected, seeded
}

// Milestone 8 (swipe-final-architecture.md §7): per-user learned entities (proper nouns),
// language-agnostic — proper nouns don't belong to a language. Only `type == .place` is
// populated today: RuleBasedExtractionService only extracts `place` (see buildTask's three-tier
// place resolution) — person/thing extraction doesn't exist in the engine yet. The full schema is
// modeled now anyway so it doesn't need a second migration once that extraction lands.
//
// Confidence isn't wired back into extraction yet (that's stage 3's "resolution + confidence
// adjustment") — see EntityMemoryService for the recording rules this pass does implement.
@Model
final class EntityMemory {
    var id: UUID
    var entity: String
    var type: String          // EntityType.rawValue
    var categoryHint: String? // TaskCategoryType.rawValue, if the mention's task had one
    var frequency: Int
    var confidence: Double
    var lastSeen: Date
    var source: String        // EntitySource.rawValue

    init(
        id: UUID = UUID(),
        entity: String,
        type: EntityType,
        categoryHint: String? = nil,
        frequency: Int = 1,
        confidence: Double,
        lastSeen: Date = .now,
        source: EntitySource
    ) {
        self.id = id
        self.entity = entity
        self.type = type.rawValue
        self.categoryHint = categoryHint
        self.frequency = frequency
        self.confidence = confidence
        self.lastSeen = lastSeen
        self.source = source.rawValue
    }
}
