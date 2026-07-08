import SwiftUI

// swipe-design-concept.md — "Lime v4": a paper notebook with one deliberate accent, not a
// productivity dashboard. Every color has exactly one job (§3); categories are told apart by
// icon shape, never hue (§4); display type is Bricolage Grotesque, body type is Outfit (§5).
// The doc gives exact hex values for paper/ink/lime; "muted grey" and the detail screen's "sky-
// pale wash" are named but left unspecified — the values below are a reasonable choice within
// the same warm, quiet palette, not a literal spec.
enum Theme {
    enum Color {
        /// Background — every screen.
        static let paper = SwiftUI.Color(hex: 0xF7_F8_EF)
        /// Primary text, icons, borders on light buttons — everywhere.
        static let ink = SwiftUI.Color(hex: 0x17_17_0F)
        /// Secondary text — meta rows, field labels. Not specified exactly by the design doc;
        /// a warm grey consistent with paper/ink's warm-neutral undertone.
        static let mutedGrey = SwiftUI.Color(hex: 0x8A_8A_7E)
        /// Brand accent — state and action only (today's day-pill, open-task accent bar, checked
        /// checkboxes, primary CTA, typing caret). Never used for category or decoration.
        static let lime = SwiftUI.Color(hex: 0xDC_EB_74)
        static let limeDeep = SwiftUI.Color(hex: 0xC3_D6_3F)
        /// Decorative header wash — Detail screen header only. Not specified exactly by the
        /// design doc; a pale, quiet blue in the same understated register as the rest of Lime.
        static let skyPaleWash = SwiftUI.Color(hex: 0xE8_EF_F2)
        /// A card's line/border — soft grey, one step off paper.
        static let hairline = SwiftUI.Color(hex: 0xE1_E2_D6)
    }

    enum Typography {
        // Bricolage Grotesque (display) / Outfit (body), §5. `Font.custom` falls back silently to
        // the system font if a name doesn't resolve, so a font-registration slip degrades
        // gracefully rather than crashing. `.weight()` on a custom font adjusts along that font's
        // own variable-weight axis when present (both bundled fonts are variable, iOS 16+).
        //
        // NOT verified on-device/in-Xcode (this environment has no Mac toolchain) — "Bricolage
        // Grotesque" is the font's typographic family name (name ID 16) per its own source config
        // (`familyName: Bricolage Grotesque`), which is what `Font.custom` is documented to key
        // off. A Windows GDI+ probe of the raw file (a proxy check only, not authoritative for
        // iOS/CoreText) reported "Bricolage Grotesque 14pt" for the default named instance —
        // if the display font silently renders as system-default once built, that mismatch is the
        // first thing to check (try "Bricolage Grotesque 14pt" instead). "Outfit" matched cleanly
        // on both checks.
        static func display(_ size: CGFloat, weight: Font.Weight = .semibold, relativeTo textStyle: Font.TextStyle = .body) -> Font {
            .custom("Bricolage Grotesque", size: size, relativeTo: textStyle).weight(weight)
        }

        static func body(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo textStyle: Font.TextStyle = .body) -> Font {
            .custom("Outfit", size: size, relativeTo: textStyle).weight(weight)
        }

        /// §5: "Notebook text sits at 15px with generous line-height — deliberately smaller than
        /// a task-card title, because a raw note and a resolved task shouldn't look like the same
        /// kind of object."
        static let noteLine = body(15, relativeTo: .body)
        static let taskCardTitle = display(17, weight: .semibold, relativeTo: .body)
        static let screenTitle = display(22, weight: .bold, relativeTo: .title2)
        static let dayNumber = display(20, weight: .bold, relativeTo: .title3)
        static let statNumber = display(20, weight: .bold, relativeTo: .title3)
        static let meta = body(13, relativeTo: .footnote)
        static let fieldLabel = body(13, weight: .medium, relativeTo: .footnote)
    }

    enum Metrics {
        static let cardRadius: CGFloat = 16
        static let pillRadius: CGFloat = 14
        static let accentBarWidth: CGFloat = 4
        // Detail screen's gradient hero card and its field-row pills below — both far more
        // rounded than the Week card system above.
        static let heroCardRadius: CGFloat = 32
        static let fieldRowRadius: CGFloat = 24
    }

    /// §4: categories are told apart by icon SHAPE, not hue. The concept names three (Arbeit/
    /// Privat/Fitness); this app's data model (`TaskCategoryType`) has six, so the remaining three
    /// get an icon in the same spirit rather than being left inconsistent. "No category" -> no
    /// icon shown, everywhere this is used.
    static func categoryIcon(_ category: String?) -> String? {
        switch category {
        case "work": return "briefcase.fill"
        case "personal": return "house.fill"
        case "health": return "heart.fill"
        case "shopping": return "cart.fill"
        case "finance": return "dollarsign.circle.fill"
        case "other": return "tag.fill"
        default: return nil
        }
    }

    static func categoryLabel(_ category: String) -> String {
        switch category {
        case "work": return "Work"
        case "personal": return "Personal"
        case "health": return "Health"
        case "shopping": return "Shopping"
        case "finance": return "Finance"
        case "other": return "Other"
        default: return category.capitalized
        }
    }
}

private extension SwiftUI.Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Reusable primitives

/// §3: "Buttons never invert to a dark fill — every button, everywhere, is a light surface with
/// ink content." Applies to every button in the app except the lime-filled primary CTA below.
struct PaperButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.body(15, weight: .medium))
            .foregroundStyle(Theme.Color.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.pillRadius, style: .continuous)
                    .fill(SwiftUI.Color.white.opacity(configuration.isPressed ? 0.6 : 1))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Metrics.pillRadius, style: .continuous)
                            .strokeBorder(Theme.Color.hairline)
                    )
            )
    }
}

/// §3: the primary CTA — lime-filled with ink text, "so it reads as an accent, not a mode switch."
struct LimeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.body(15, weight: .semibold))
            .foregroundStyle(Theme.Color.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.pillRadius, style: .continuous)
                    .fill(configuration.isPressed ? Theme.Color.limeDeep : Theme.Color.lime)
            )
    }
}

extension ButtonStyle where Self == PaperButtonStyle {
    static var paper: PaperButtonStyle { PaperButtonStyle() }
}

extension ButtonStyle where Self == LimeButtonStyle {
    static var lime: LimeButtonStyle { LimeButtonStyle() }
}
