import SwiftUI
import SwiftData

// Extracted from WeekView (real-device feedback, 2026-07-04) so both Week and the new Tasklist
// module render tasks identically — a rounded card with a lime/grey open-vs-done accent bar,
// checkbox, and the same metadata line (category icon, date/time, place, priority, link, low-
// confidence flag).
struct TaskCardView: View {
    let task: TaskItem
    var onToggleCompletion: () -> Void
    var onTap: () -> Void

    @Query(sort: \CustomCategory.createdAt) private var customCategories: [CustomCategory]

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(task.isCompleted ? Theme.Color.hairline : Theme.Color.lime)
                .frame(width: Theme.Metrics.accentBarWidth)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(task.title)
                        .font(Theme.Typography.taskCardTitle)
                        .foregroundStyle(task.isCompleted ? Theme.Color.mutedGrey : Theme.Color.ink)
                        .strikethrough(task.isCompleted)
                    Spacer()
                    Button(action: onToggleCompletion) {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(task.isCompleted ? Theme.Color.limeDeep : Theme.Color.mutedGrey)
                    }
                    .buttonStyle(.plain)
                }
                metaLine
                if let details = task.details {
                    Text(details)
                        .font(Theme.Typography.meta)
                        .foregroundStyle(Theme.Color.mutedGrey)
                        .lineLimit(2)
                }
            }
            .padding(12)
        }
        .background(task.isCompleted ? Theme.Color.hairline.opacity(0.35) : SwiftUI.Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                .strokeBorder(Theme.Color.hairline)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    @ViewBuilder
    private var metaLine: some View {
        HStack(spacing: 8) {
            if let category = task.category, let icon = Theme.categoryIcon(category, custom: customCategories) {
                Image(systemName: icon)
            }
            if let date = task.dueDate, let endDate = task.dueEndDate {
                // Real-device feedback (2026-07-03): a range renders as "Jul 9 – Jul 11".
                Text("\(date.formatted(.dateTime.month(.abbreviated).day())) – \(endDate.formatted(.dateTime.month(.abbreviated).day()))")
            }
            if let time = task.dueTime, let endTime = task.dueEndTime {
                // Real-device feedback (2026-07-04): "Arzttermin 10 bis 12 Uhr" — a time range
                // renders as "10:00–12:00", mirroring the date-range rendering above.
                Text("\(time.formatted(.dateTime.hour().minute())) – \(endTime.formatted(.dateTime.hour().minute()))")
            } else if let time = task.dueTime {
                Text(time.formatted(.dateTime.hour().minute()))
            } else if let timeOfDay = task.timeOfDay {
                Label(timeOfDay, systemImage: "clock")
            }
            if let place = task.place {
                Label(place, systemImage: "mappin.and.ellipse")
            }
            if task.linkedGroupID != nil {
                Label("Step \((task.sequenceIndex ?? 0) + 1) of 2", systemImage: "link")
            }
            if let priority = task.priority {
                priorityBadge(priority)
            }
            if RuleBasedExtractionService.isLowConfidence(task.dateConfidence) {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.orange)
            }
        }
        .font(Theme.Typography.meta)
        .foregroundStyle(Theme.Color.mutedGrey)
    }

    private func priorityBadge(_ priority: String) -> some View {
        Text(priority)
            .font(Theme.Typography.meta.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.Color.hairline, in: Capsule())
            .foregroundStyle(Theme.Color.ink)
    }
}

// Shared by Week, Tasklist, and Shopping list — a plain icon + muted message, centered.
struct EmptyStateView: View {
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(Theme.Color.mutedGrey.opacity(0.6))
            Text(message)
                .font(Theme.Typography.body(14))
                .foregroundStyle(Theme.Color.mutedGrey)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}
