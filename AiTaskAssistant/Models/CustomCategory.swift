import Foundation
import SwiftData

// Real-device feedback: the six built-in categories (TaskCategoryType) don't cover everyone's
// life — users want their own. A custom category is just a name plus an icon chosen from a
// curated catalog (never a hue, matching Theme's "categories are told apart by shape, not color"
// rule); its `name` is stored directly as `TaskItem.category`'s raw string, the same way a
// built-in category's raw case name is.
//
// Kept dependency-free (no SwiftUI/Theme import) so this file can be shared into the widget
// extension target's Sources phase too, the same way TaskItem/NoteLine/etc. already are — the
// widget process needs this type to exist for `SharedModelContainer`'s schema to resolve, even
// though the widgets themselves don't render custom category icons. The icon catalog, the
// Theme-aware icon resolver, and the creation UI live in Views/CustomCategoryPicker.swift
// (main-app target only), since Theme.swift itself isn't part of the widget target.
@Model
final class CustomCategory {
    var id: UUID
    var name: String
    var iconName: String
    var createdAt: Date

    init(name: String, iconName: String) {
        self.id = UUID()
        self.name = name
        self.iconName = iconName
        self.createdAt = .now
    }
}
