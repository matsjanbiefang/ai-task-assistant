import Testing
import SwiftData
@testable import AiTaskAssistant

// Milestone 8: proves the three recording rules from swipe-final-architecture.md §7 directly
// against an in-memory ModelContainer — no UI/app needed. @MainActor because ModelContext isn't
// Sendable, matching how SwiftData is used everywhere else in the app.
@MainActor
struct EntityMemoryServiceTests {
    private func makeContext() -> ModelContext {
        let container = try! ModelContainer(
            for: EntityMemory.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func allEntities(_ context: ModelContext) -> [EntityMemory] {
        (try? context.fetch(FetchDescriptor<EntityMemory>())) ?? []
    }

    @Test
    func firstMentionStoresAtLowConfidence() {
        let context = makeContext()
        EntityMemoryService.recordMention("Hospital", type: .place, categoryHint: "health", context: context)
        let all = allEntities(context)
        #expect(all.count == 1)
        #expect(all[0].entity == "Hospital")
        #expect(all[0].frequency == 1)
        #expect(all[0].confidence == 0.3)
        #expect(all[0].source == EntitySource.auto.rawValue)
        #expect(all[0].categoryHint == "health")
    }

    @Test
    func repeatMentionsGrowFrequencyAndConfidence() {
        let context = makeContext()
        for _ in 0..<3 {
            EntityMemoryService.recordMention("Hospital", type: .place, categoryHint: nil, context: context)
        }
        let all = allEntities(context)
        #expect(all.count == 1)
        #expect(all[0].frequency == 3)
        #expect(all[0].confidence == 0.6) // 0.3 + (3-1) * 0.15
    }

    @Test
    func confidenceCapsAtOne() {
        let context = makeContext()
        for _ in 0..<10 {
            EntityMemoryService.recordMention("Hospital", type: .place, categoryHint: nil, context: context)
        }
        #expect(allEntities(context)[0].confidence == 1.0)
    }

    @Test
    func mentionMatchIsCaseInsensitive() {
        let context = makeContext()
        EntityMemoryService.recordMention("Hospital", type: .place, categoryHint: nil, context: context)
        EntityMemoryService.recordMention("hospital", type: .place, categoryHint: nil, context: context)
        let all = allEntities(context)
        #expect(all.count == 1)
        #expect(all[0].frequency == 2)
    }

    @Test
    func correctionOnNewEntityIsFullConfidence() {
        let context = makeContext()
        EntityMemoryService.recordCorrection("Greenwood Avenue", type: .place, categoryHint: nil, context: context)
        let all = allEntities(context)
        #expect(all.count == 1)
        #expect(all[0].confidence == 1.0)
        #expect(all[0].source == EntitySource.corrected.rawValue)
    }

    @Test
    func correctionOverridesLowConfidenceAutoEntry() {
        let context = makeContext()
        EntityMemoryService.recordMention("Hospital", type: .place, categoryHint: nil, context: context)
        #expect(allEntities(context)[0].confidence == 0.3)

        EntityMemoryService.recordCorrection("Hospital", type: .place, categoryHint: "health", context: context)
        let all = allEntities(context)
        #expect(all.count == 1)
        #expect(all[0].confidence == 1.0)
        #expect(all[0].source == EntitySource.corrected.rawValue)
        #expect(all[0].categoryHint == "health")
    }
}
