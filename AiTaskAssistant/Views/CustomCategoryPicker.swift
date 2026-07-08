import SwiftUI
import SwiftData

extension Theme {
    // Overload (not a replacement — disambiguated by the required `custom:` label) so the three
    // call sites that need to resolve a possibly-custom category pass their live `@Query` results,
    // while every other existing call site is unaffected.
    static func categoryIcon(_ category: String?, custom: [CustomCategory]) -> String? {
        if let builtIn = categoryIcon(category) { return builtIn }
        guard let category else { return nil }
        return custom.first { $0.name == category }?.iconName
    }
}

// A broad, neutral set of SF Symbols not already used by a built-in category (work/personal/
// health/shopping/finance/other) — offered when creating a custom one.
enum CategoryIconCatalog {
    static let icons: [String] = [
        "star.fill", "book.fill", "airplane", "car.fill", "gift.fill", "gamecontroller.fill",
        "paintbrush.fill", "wrench.fill", "leaf.fill", "pawprint.fill", "graduationcap.fill",
        "fork.knife", "bed.double.fill", "figure.walk", "phone.fill", "envelope.fill",
        "camera.fill", "music.note", "film.fill", "cup.and.saucer.fill", "bicycle",
        "sun.max.fill", "moon.fill", "cloud.fill", "umbrella.fill", "creditcard.fill",
        "building.2.fill", "hammer.fill", "scissors", "paintpalette.fill", "theatermasks.fill",
    ]
}

// Shared by Settings' "Categories" section and the "Add category…" entry in the task editor's
// category menu — same sheet, same result either way.
struct AddCustomCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var selectedIcon = CategoryIconCatalog.icons[0]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 5)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TextField("Category name", text: $name)
                        .font(Theme.Typography.body(16))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(SwiftUI.Color.white, in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))

                    Text("Icon")
                        .font(Theme.Typography.fieldLabel)
                        .foregroundStyle(Theme.Color.mutedGrey)

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(CategoryIconCatalog.icons, id: \.self) { icon in
                            iconButton(icon)
                        }
                    }

                    Button {
                        save()
                    } label: {
                        Text("Add Category")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.lime)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .background(Theme.Color.paper)
            .navigationTitle("New Category")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func iconButton(_ icon: String) -> some View {
        let isSelected = icon == selectedIcon
        return Button {
            selectedIcon = icon
        } label: {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Theme.Color.ink)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Metrics.pillRadius, style: .continuous)
                        .fill(isSelected ? Theme.Color.lime : SwiftUI.Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Metrics.pillRadius, style: .continuous)
                        .strokeBorder(Theme.Color.hairline)
                )
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        modelContext.insert(CustomCategory(name: trimmed, iconName: selectedIcon))
        try? modelContext.save()
        dismiss()
    }
}
