import SwiftUI

// Phase 5: full feature tour shown once before the language picker (previously the only
// onboarding step). Each page mirrors the real UI it's introducing rather than describing it in
// the abstract, matching the rest of the app's "show, don't tell" style.
struct OnboardingFlowView: View {
    var onFinish: (SupportedLanguage) -> Void

    private enum Page: Int, CaseIterable {
        case welcome, notes, speech, siri, widgets, notifications, language
    }

    @State private var page: Page = .welcome
    @State private var selectedLanguage = SupportedLanguage.deviceDefault.isSupportedByLanguagePack
        ? SupportedLanguage.deviceDefault : .en
    @State private var notificationsRequested = false

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                WelcomePage().tag(Page.welcome)
                NotesDemoPage().tag(Page.notes)
                SpeechDemoPage().tag(Page.speech)
                SiriPage().tag(Page.siri)
                WidgetsPage().tag(Page.widgets)
                NotificationsPage(requested: $notificationsRequested).tag(Page.notifications)
                OnboardingLanguageView(embedded: true, selected: $selectedLanguage).tag(Page.language)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            continueButton
        }
        .background(Theme.Color.paper)
    }

    private var isLastPage: Bool { page == Page.allCases.last }

    private var continueButton: some View {
        Button {
            if isLastPage {
                onFinish(selectedLanguage)
            } else if let next = Page(rawValue: page.rawValue + 1) {
                withAnimation { page = next }
            }
        } label: {
            Text(isLastPage ? "Get Started" : "Continue")
                .font(Theme.Typography.body(16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.Color.lime)
        .foregroundStyle(Theme.Color.ink)
        .padding(20)
    }
}

private struct OnboardingPageLayout<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: icon)
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.Color.limeDeep)
                    .padding(.top, 40)
                Text(title)
                    .font(Theme.Typography.screenTitle)
                    .foregroundStyle(Theme.Color.ink)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(Theme.Typography.body(15))
                    .foregroundStyle(Theme.Color.mutedGrey)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                content()
                    .padding(.top, 12)
                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct WelcomePage: View {
    var body: some View {
        OnboardingPageLayout(
            icon: "note.text",
            title: "Welcome to TaskMind",
            subtitle: "Write or say what's on your mind — TaskMind turns messy notes into organized tasks automatically."
        ) { EmptyView() }
    }
}

private struct NotesDemoPage: View {
    var body: some View {
        OnboardingPageLayout(
            icon: "square.and.pencil",
            title: "Just start typing",
            subtitle: "Type a note the way you normally would. As soon as you finish a line, TaskMind quietly turns it into a task — dates, priority, and category included."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("call max tomorrow!!")
                    .font(Theme.Typography.noteLine)
                    .foregroundStyle(Theme.Color.ink)
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Color.limeDeep)
                    Text("1 task created")
                        .font(Theme.Typography.meta)
                        .foregroundStyle(Theme.Color.mutedGrey)
                }
            }
            .padding(16)
            .background(Theme.Color.hairline.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius))
            .padding(.horizontal, 32)
        }
    }
}

private struct SpeechDemoPage: View {
    var body: some View {
        OnboardingPageLayout(
            icon: "mic.fill",
            title: "Or just say it",
            subtitle: "Tap the microphone in the notes bar and talk — your words are transcribed on-device and parsed the same way as typed text."
        ) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.Color.lime)
        }
    }
}

private struct SiriPage: View {
    var body: some View {
        OnboardingPageLayout(
            icon: "waveform",
            title: "Add tasks with Siri",
            subtitle: "Say \"Add a task to TaskMind\" from anywhere on your phone — no need to open the app first. Works in all of TaskMind's supported languages."
        ) { EmptyView() }
    }
}

private struct WidgetsPage: View {
    var body: some View {
        OnboardingPageLayout(
            icon: "square.grid.2x2.fill",
            title: "Widgets for your Home and Lock Screen",
            subtitle: "See today's tasks, your progress, or jump straight into adding one — right from your Home Screen or Lock Screen. Long-press your Home Screen and tap + to add one."
        ) { EmptyView() }
    }
}

private struct NotificationsPage: View {
    @Binding var requested: Bool

    var body: some View {
        OnboardingPageLayout(
            icon: "bell.badge.fill",
            title: "Never miss a due date",
            subtitle: "TaskMind can remind you before a task is due. You can change this anytime in Settings."
        ) {
            Button {
                requested = true
                Task { _ = await NotificationService.shared.requestPermission() }
            } label: {
                Text(requested ? "Notifications requested" : "Enable Notifications")
                    .font(Theme.Typography.body(15, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .tint(Theme.Color.ink)
            .disabled(requested)
        }
    }
}

#Preview {
    OnboardingFlowView(onFinish: { _ in })
}
