import SwiftUI
import SwiftData

// swipe-design-concept.md §6 "Shopping list": "a second, simpler notebook — same capture-line
// pattern, same checkbox language, no dates or categories. Reuses the product's core idea (type
// it, it becomes a structured item) rather than being a bolted-on separate feature."
struct ShoppingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ShoppingItem.order) private var items: [ShoppingItem]
    @State private var composeText = ""
    @FocusState private var composeFocused: Bool

    private var openItems: [ShoppingItem] { items.filter { !$0.isCompleted } }
    private var checkedItems: [ShoppingItem] { items.filter(\.isCompleted) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(openItems) { item in row(for: item) }
                        if !checkedItems.isEmpty {
                            // Real-device feedback: no manual "Clear" button anymore — checked
                            // items are simply removed automatically the next time the app
                            // launches (see `purgeCheckedShoppingItems` in ContentView), so they
                            // stick around long enough to see what you've checked off this
                            // session without needing to be tidied up by hand.
                            Text("Checked")
                                .font(Theme.Typography.fieldLabel)
                                .foregroundStyle(Theme.Color.mutedGrey)
                                .padding(.top, 20)
                                .padding(.bottom, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(checkedItems) { item in row(for: item) }
                        }
                        if items.isEmpty {
                            emptyState
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
                Rectangle()
                    .fill(Theme.Color.hairline)
                    .frame(height: 1)
                composeRow
            }
            .background(Theme.Color.paper)
            .navigationTitle("Shopping list")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { composeFocused = true }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "cart")
                .font(.system(size: 28))
                .foregroundStyle(Theme.Color.mutedGrey.opacity(0.6))
            Text("Nothing on your list yet")
                .font(Theme.Typography.body(14))
                .foregroundStyle(Theme.Color.mutedGrey)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func row(for item: ShoppingItem) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                item.isCompleted.toggle()
                try? modelContext.save()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(item.isCompleted ? Theme.Color.limeDeep : Theme.Color.mutedGrey)
                Text(item.text)
                    .font(Theme.Typography.body(16))
                    .foregroundStyle(item.isCompleted ? Theme.Color.mutedGrey : Theme.Color.ink)
                    .strikethrough(item.isCompleted)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 8)
        .contextMenu {
            Button(role: .destructive) {
                modelContext.delete(item)
                try? modelContext.save()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var composeRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 20))
                .foregroundStyle(Theme.Color.mutedGrey.opacity(0.5))
            TextField("Add an item…", text: $composeText)
                .font(Theme.Typography.body(16))
                .focused($composeFocused)
                .submitLabel(.done)
                .onSubmit { commitCompose() }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.Color.paper)
    }

    private func commitCompose() {
        let trimmed = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        ShoppingItem.add([trimmed], context: modelContext)
        composeText = ""
        composeFocused = true
    }
}

#Preview {
    ShoppingListView()
        .modelContainer(for: [ShoppingItem.self], inMemory: true)
}
