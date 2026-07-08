import SwiftUI
import RevenueCat

// Phase 5: full feature tour shown once before the app is used. Each page mirrors the real UI
// it's introducing rather than describing it in the abstract, matching the rest of the app's
// "show, don't tell" style.
//
// Real-device feedback folded in here:
// - Language is the first page and starts with NOTHING selected (Continue disabled until a
//   choice is made) — every later page's copy, including the illustrative examples and the Siri
//   walkthrough, is localized live against whatever gets picked, via `OnboardingCopy` below.
// - Notification permission is requested when tapping the shared Continue button on that page.
//   If granted, the flow goes straight to a shared final page. If denied, an extra "here's why
//   this helps" page is inserted first, then the same final page.
// - A paywall page (previously missing from onboarding entirely) sits before notifications, with
//   its own "Start Free Trial" action and a "Maybe Later" skip via the shared Continue button.
struct OnboardingFlowView: View {
    var onFinish: (SupportedLanguage) -> Void

    private enum Page: Int, CaseIterable {
        case language, welcome, notes, examples, speech, siri, widgets, paywall, notifications, notificationsValue, final
    }

    @State private var page: Page = .language
    @State private var selectedLanguage: SupportedLanguage?
    @State private var notificationsGranted: Bool?

    private var language: SupportedLanguage { selectedLanguage ?? .en }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                OnboardingLanguageView(embedded: true, selected: $selectedLanguage)
                    .tag(Page.language)
                WelcomePage(language: language).tag(Page.welcome)
                NotesDemoPage(language: language).tag(Page.notes)
                ExamplesPage(language: language).tag(Page.examples)
                SpeechDemoPage(language: language).tag(Page.speech)
                SiriPage(language: language).tag(Page.siri)
                WidgetsPage(language: language).tag(Page.widgets)
                OnboardingPaywallPage(language: language, onAdvance: { advance() }).tag(Page.paywall)
                NotificationsPage(language: language).tag(Page.notifications)
                NotificationsValuePage(language: language).tag(Page.notificationsValue)
                FinalPage(language: language).tag(Page.final)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            continueButton
        }
        .background(Theme.Color.paper)
    }

    private var isLastPage: Bool { page == .final }

    private var continueLabel: String {
        if isLastPage { return OnboardingCopy.getStarted(language) }
        if page == .paywall { return OnboardingCopy.maybeLater(language) }
        return OnboardingCopy.continueLabel(language)
    }

    private var continueButton: some View {
        Button {
            advance()
        } label: {
            Text(continueLabel)
                .font(Theme.Typography.body(16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.Color.lime)
        .foregroundStyle(Theme.Color.ink)
        .disabled(page == .language && selectedLanguage == nil)
        .padding(20)
    }

    private func advance() {
        if page == .notifications {
            Task {
                let granted = await NotificationService.shared.requestPermission()
                notificationsGranted = granted
                withAnimation { page = granted ? .final : .notificationsValue }
            }
            return
        }
        if isLastPage {
            onFinish(language)
        } else if let next = Page(rawValue: page.rawValue + 1) {
            withAnimation { page = next }
        }
    }
}

// Vertically centers its content within the page instead of pinning it to the top — a
// GeometryReader-driven minHeight lets a ScrollView still work on the smallest supported screens
// without a fixed-height VStack clipping content there.
private struct OnboardingPageLayout<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    Spacer(minLength: 0)
                    Image(systemName: icon)
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.Color.limeDeep)
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
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height)
                .padding(.vertical, 24)
            }
        }
    }
}

private struct WelcomePage: View {
    let language: SupportedLanguage
    var body: some View {
        let copy = OnboardingCopy.text(for: .welcome, in: language)
        OnboardingPageLayout(icon: "note.text", title: copy.title, subtitle: copy.subtitle) { EmptyView() }
    }
}

private struct NotesDemoPage: View {
    let language: SupportedLanguage
    var body: some View {
        let copy = OnboardingCopy.text(for: .notes, in: language)
        let example = OnboardingCopy.notesExample(language)
        OnboardingPageLayout(icon: "square.and.pencil", title: copy.title, subtitle: copy.subtitle) {
            exampleCard(input: example.input, result: example.result, resultIcon: "checkmark.circle.fill")
        }
    }
}

// A few more worked examples, explicitly including the shopping-list feature, since the single
// note-to-task example on the previous page didn't show the breadth of what gets detected or
// that shopping lines route somewhere different entirely.
private struct ExamplesPage: View {
    let language: SupportedLanguage
    var body: some View {
        let copy = OnboardingCopy.text(for: .examples, in: language)
        OnboardingPageLayout(icon: "sparkles", title: copy.title, subtitle: copy.subtitle) {
            VStack(spacing: 10) {
                ForEach(Array(OnboardingCopy.examples(language).enumerated()), id: \.offset) { _, example in
                    exampleCard(input: example.input, result: example.result, resultIcon: example.icon)
                }
            }
            .padding(.horizontal, 32)
        }
    }
}

private struct SpeechDemoPage: View {
    let language: SupportedLanguage
    var body: some View {
        let copy = OnboardingCopy.text(for: .speech, in: language)
        OnboardingPageLayout(icon: "mic.fill", title: copy.title, subtitle: copy.subtitle) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.Color.lime)
        }
    }
}

private struct SiriPage: View {
    let language: SupportedLanguage
    var body: some View {
        let copy = OnboardingCopy.text(for: .siri, in: language)
        OnboardingPageLayout(icon: "waveform", title: copy.title, subtitle: copy.subtitle) {
            VStack(alignment: .leading, spacing: 10) {
                let steps = OnboardingCopy.siriSteps(language)
                siriStep(icon: "waveform", text: steps[0])
                siriStep(icon: "arrow.turn.down.right", text: steps[1])
                siriStep(icon: "text.bubble.fill", text: steps[2])
            }
            .padding(16)
            .background(Theme.Color.hairline.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius))
            .padding(.horizontal, 32)
        }
    }

    private func siriStep(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Theme.Color.limeDeep)
                .frame(width: 20)
            Text(text)
                .font(Theme.Typography.noteLine)
                .foregroundStyle(Theme.Color.ink)
        }
    }
}

private struct WidgetsPage: View {
    let language: SupportedLanguage
    var body: some View {
        let copy = OnboardingCopy.text(for: .widgets, in: language)
        OnboardingPageLayout(icon: "square.grid.2x2.fill", title: copy.title, subtitle: copy.subtitle) { EmptyView() }
    }
}

// Real-device feedback: onboarding never actually showed the paywall — the only way to reach it
// was Settings or accidentally hitting the free-tier task cap. This is a lightweight page (not a
// reuse of PaywallView, which brings its own NavigationStack/toolbar "Close" button that doesn't
// fit a TabView page) with its own purchase action; skipping is just the shared Continue button
// relabeled "Maybe Later".
private struct OnboardingPaywallPage: View {
    let language: SupportedLanguage
    let onAdvance: () -> Void

    @ObservedObject private var subscriptions = SubscriptionService.shared
    @State private var selected: Package?
    @State private var isPurchasing = false
    @State private var errorMessage: String?

    var body: some View {
        let copy = OnboardingCopy.text(for: .paywall, in: language)
        OnboardingPageLayout(icon: "sparkle", title: copy.title, subtitle: copy.subtitle) {
            VStack(spacing: 14) {
                ForEach(subscriptions.offering?.availablePackages ?? [], id: \.identifier) { package in
                    packageRow(package)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.Typography.meta)
                        .foregroundStyle(.red)
                }
                Button {
                    purchase()
                } label: {
                    HStack {
                        if isPurchasing { ProgressView().tint(Theme.Color.ink) }
                        Text(OnboardingCopy.startFreeTrial(language))
                            .font(Theme.Typography.body(16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.lime)
                .disabled(selected == nil || isPurchasing)
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
        }
        .task {
            await subscriptions.fetchOfferings()
            selected = subscriptions.offering?.availablePackages.first { $0.packageType == .annual }
                ?? subscriptions.offering?.availablePackages.first
        }
    }

    private func packageRow(_ package: Package) -> some View {
        let isSelected = selected?.identifier == package.identifier
        return Button {
            selected = package
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(package.storeProduct.localizedTitle)
                        .font(Theme.Typography.body(15, weight: .semibold))
                        .foregroundStyle(Theme.Color.ink)
                    Text(package.storeProduct.localizedPriceString)
                        .font(Theme.Typography.meta)
                        .foregroundStyle(Theme.Color.mutedGrey)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.Color.limeDeep : Theme.Color.mutedGrey)
            }
            .padding(14)
            .background(SwiftUI.Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius)
                    .stroke(isSelected ? Theme.Color.limeDeep : Theme.Color.hairline, lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius))
        }
        .buttonStyle(.plain)
    }

    private func purchase() {
        guard let package = selected else { return }
        isPurchasing = true
        errorMessage = nil
        Task {
            do {
                try await subscriptions.purchase(package: package)
                isPurchasing = false
                onAdvance()
            } catch {
                isPurchasing = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct NotificationsPage: View {
    let language: SupportedLanguage
    var body: some View {
        let copy = OnboardingCopy.text(for: .notifications, in: language)
        OnboardingPageLayout(icon: "bell.badge.fill", title: copy.title, subtitle: copy.subtitle) { EmptyView() }
    }
}

// Only reached if the user declines notifications on the previous page.
private struct NotificationsValuePage: View {
    let language: SupportedLanguage
    var body: some View {
        let copy = OnboardingCopy.text(for: .notificationsValue, in: language)
        OnboardingPageLayout(icon: "bell.slash", title: copy.title, subtitle: copy.subtitle) { EmptyView() }
    }
}

private struct FinalPage: View {
    let language: SupportedLanguage
    var body: some View {
        let copy = OnboardingCopy.text(for: .final, in: language)
        OnboardingPageLayout(icon: "checkmark.seal.fill", title: copy.title, subtitle: copy.subtitle) { EmptyView() }
    }
}

// Shared mini example card used by both the Notes demo and the Examples page.
private func exampleCard(input: String, result: String, resultIcon: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(input)
            .font(Theme.Typography.noteLine)
            .foregroundStyle(Theme.Color.ink)
        HStack(spacing: 6) {
            Image(systemName: resultIcon)
                .foregroundStyle(Theme.Color.limeDeep)
            Text(result)
                .font(Theme.Typography.meta)
                .foregroundStyle(Theme.Color.mutedGrey)
        }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.Color.hairline.opacity(0.3))
    .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius))
    .padding(.horizontal, 32)
}

// MARK: - Localized copy

// Onboarding is the one place in the app where the "current UI language" is chosen live, before
// it's saved anywhere — so its own instructional text (and, per real-device feedback, its
// illustrative examples and Siri walkthrough too) is translated directly here against the
// in-progress selection, rather than through the general string-catalog/environment-locale
// mechanism the rest of the app uses, which only takes effect on next launch/after this flow
// finishes.
//
// Known limitation: the shopping-list trigger phrase (`shoppingListPattern` in the language
// packs) is only implemented for English and German today — the other six languages' example
// below is phrased the same way for consistency, but won't actually route to the shopping list
// on-device yet in those languages. Flagged here rather than silently overclaiming.
private enum OnboardingCopy {
    fileprivate enum Page {
        case welcome, notes, examples, speech, siri, widgets, paywall, notifications, notificationsValue, final
    }

    private struct Copy { let title: String; let subtitle: String }
    private struct Example { let input: String; let result: String; let icon: String }

    static func text(for page: Page, in language: SupportedLanguage) -> (title: String, subtitle: String) {
        let table = copy[page] ?? [:]
        let entry = table[language.rawValue] ?? table["en"]!
        return (entry.title, entry.subtitle)
    }

    static func notesExample(_ language: SupportedLanguage) -> (input: String, result: String) {
        let entry = notesExamples[language.rawValue] ?? notesExamples["en"]!
        return (entry.input, entry.result)
    }

    static func examples(_ language: SupportedLanguage) -> [(input: String, result: String, icon: String)] {
        let list = examplesTable[language.rawValue] ?? examplesTable["en"]!
        return list.map { ($0.input, $0.result, $0.icon) }
    }

    static func siriSteps(_ language: SupportedLanguage) -> [String] {
        siriStepsTable[language.rawValue] ?? siriStepsTable["en"]!
    }

    static func continueLabel(_ language: SupportedLanguage) -> String {
        continueLabels[language.rawValue] ?? continueLabels["en"]!
    }

    static func getStarted(_ language: SupportedLanguage) -> String {
        getStartedLabels[language.rawValue] ?? getStartedLabels["en"]!
    }

    static func maybeLater(_ language: SupportedLanguage) -> String {
        maybeLaterLabels[language.rawValue] ?? maybeLaterLabels["en"]!
    }

    static func startFreeTrial(_ language: SupportedLanguage) -> String {
        startFreeTrialLabels[language.rawValue] ?? startFreeTrialLabels["en"]!
    }

    private static let continueLabels: [String: String] = [
        "en": "Continue", "de": "Weiter", "es": "Continuar", "fr": "Continuer",
        "it": "Continua", "nl": "Doorgaan", "pl": "Dalej", "pt": "Continuar",
    ]

    private static let getStartedLabels: [String: String] = [
        "en": "Get Started", "de": "Los geht's", "es": "Empezar", "fr": "Commencer",
        "it": "Inizia", "nl": "Aan de slag", "pl": "Zaczynajmy", "pt": "Começar",
    ]

    private static let maybeLaterLabels: [String: String] = [
        "en": "Maybe Later", "de": "Vielleicht später", "es": "Quizás más tarde", "fr": "Peut-être plus tard",
        "it": "Magari più tardi", "nl": "Misschien later", "pl": "Może później", "pt": "Talvez mais tarde",
    ]

    private static let startFreeTrialLabels: [String: String] = [
        "en": "Start Free Trial", "de": "Kostenlose Testphase starten", "es": "Iniciar prueba gratuita",
        "fr": "Démarrer l'essai gratuit", "it": "Inizia la prova gratuita", "nl": "Start gratis proefperiode",
        "pl": "Rozpocznij bezpłatny okres próbny", "pt": "Iniciar teste gratuito",
    ]

    private static let notesExamples: [String: (input: String, result: String)] = [
        "en": ("call max tomorrow!!", "1 task created"),
        "de": ("max morgen anrufen!!", "1 Aufgabe erstellt"),
        "es": ("llamar a max mañana!!", "1 tarea creada"),
        "fr": ("appeler max demain!!", "1 tâche créée"),
        "it": ("chiamare max domani!!", "1 attività creata"),
        "nl": ("max morgen bellen!!", "1 taak aangemaakt"),
        "pl": ("zadzwonić do maxa jutro!!", "Utworzono 1 zadanie"),
        "pt": ("ligar para o max amanhã!!", "1 tarefa criada"),
    ]

    private static let examplesTable: [String: [Example]] = [
        "en": [
            Example(input: "add milk, eggs, and bread to shopping list", result: "Added to your shopping list", icon: "cart.fill"),
            Example(input: "dentist next tuesday 10am", result: "Task created · Tuesday · 10:00", icon: "calendar"),
            Example(input: "call mom !!", result: "Task created · High priority", icon: "flag.fill"),
        ],
        "de": [
            Example(input: "milch, eier und brot auf die einkaufsliste", result: "Zu deiner Einkaufsliste hinzugefügt", icon: "cart.fill"),
            Example(input: "zahnarzt nächsten dienstag 10 uhr", result: "Aufgabe erstellt · Dienstag · 10:00", icon: "calendar"),
            Example(input: "mama anrufen !!", result: "Aufgabe erstellt · Hohe Priorität", icon: "flag.fill"),
        ],
        "es": [
            Example(input: "añade leche, huevos y pan a la lista de la compra", result: "Añadido a tu lista de la compra", icon: "cart.fill"),
            Example(input: "dentista el próximo martes a las 10", result: "Tarea creada · Martes · 10:00", icon: "calendar"),
            Example(input: "llamar a mamá !!", result: "Tarea creada · Prioridad alta", icon: "flag.fill"),
        ],
        "fr": [
            Example(input: "ajoute du lait, des œufs et du pain à la liste de courses", result: "Ajouté à ta liste de courses", icon: "cart.fill"),
            Example(input: "dentiste mardi prochain à 10h", result: "Tâche créée · Mardi · 10:00", icon: "calendar"),
            Example(input: "appeler maman !!", result: "Tâche créée · Priorité haute", icon: "flag.fill"),
        ],
        "it": [
            Example(input: "aggiungi latte, uova e pane alla lista della spesa", result: "Aggiunto alla tua lista della spesa", icon: "cart.fill"),
            Example(input: "dentista martedì prossimo alle 10", result: "Attività creata · Martedì · 10:00", icon: "calendar"),
            Example(input: "chiamare la mamma !!", result: "Attività creata · Priorità alta", icon: "flag.fill"),
        ],
        "nl": [
            Example(input: "voeg melk, eieren en brood toe aan de boodschappenlijst", result: "Toegevoegd aan je boodschappenlijst", icon: "cart.fill"),
            Example(input: "tandarts volgende dinsdag om 10 uur", result: "Taak aangemaakt · Dinsdag · 10:00", icon: "calendar"),
            Example(input: "mama bellen !!", result: "Taak aangemaakt · Hoge prioriteit", icon: "flag.fill"),
        ],
        "pl": [
            Example(input: "dodaj mleko, jajka i chleb do listy zakupów", result: "Dodano do listy zakupów", icon: "cart.fill"),
            Example(input: "dentysta w przyszły wtorek o 10", result: "Utworzono zadanie · Wtorek · 10:00", icon: "calendar"),
            Example(input: "zadzwonić do mamy !!", result: "Utworzono zadanie · Wysoki priorytet", icon: "flag.fill"),
        ],
        "pt": [
            Example(input: "adiciona leite, ovos e pão à lista de compras", result: "Adicionado à tua lista de compras", icon: "cart.fill"),
            Example(input: "dentista na próxima terça-feira às 10h", result: "Tarefa criada · Terça-feira · 10:00", icon: "calendar"),
            Example(input: "ligar para a mãe !!", result: "Tarefa criada · Prioridade alta", icon: "flag.fill"),
        ],
    ]

    private static let siriStepsTable: [String: [String]] = [
        "en": ["“Hey Siri, add a note to TaskMind”", "TaskMind opens, ready to listen", "“Ready. What's on your mind?”"],
        "de": ["„Hey Siri, füge eine Notiz zu TaskMind hinzu“", "TaskMind öffnet sich, bereit zum Zuhören", "„Bereit. Was hast du im Kopf?“"],
        "es": ["«Oye Siri, añade una nota a TaskMind»", "TaskMind se abre, listo para escuchar", "«Listo. ¿Qué tienes en mente?»"],
        "fr": ["« Dis Siri, ajoute une note à TaskMind »", "TaskMind s'ouvre, prêt à écouter", "« Prêt. À quoi penses-tu ? »"],
        "it": ["«Hey Siri, aggiungi una nota a TaskMind»", "TaskMind si apre, pronto ad ascoltare", "«Pronto. A cosa stai pensando?»"],
        "nl": ["\"Hey Siri, voeg een notitie toe aan TaskMind\"", "TaskMind opent, klaar om te luisteren", "\"Klaar. Wat heb je in gedachten?\""],
        "pl": ["„Hej Siri, dodaj notatkę do TaskMind”", "TaskMind się otwiera, gotowy do słuchania", "„Gotowe. Co masz na myśli?”"],
        "pt": ["«Hey Siri, adiciona uma nota ao TaskMind»", "O TaskMind abre, pronto para ouvir", "«Pronto. Em que estás a pensar?»"],
    ]

    private static let copy: [Page: [String: Copy]] = [
        .welcome: [
            "en": Copy(title: "Welcome to TaskMind", subtitle: "Write or say what's on your mind — TaskMind turns messy notes into organized tasks automatically."),
            "de": Copy(title: "Willkommen bei TaskMind", subtitle: "Schreib oder sag, was dir durch den Kopf geht — TaskMind macht daraus automatisch organisierte Aufgaben."),
            "es": Copy(title: "Bienvenido a TaskMind", subtitle: "Escribe o di lo que tengas en mente — TaskMind convierte notas desordenadas en tareas organizadas automáticamente."),
            "fr": Copy(title: "Bienvenue sur TaskMind", subtitle: "Écris ou dis ce qui te passe par la tête — TaskMind transforme des notes en vrac en tâches organisées automatiquement."),
            "it": Copy(title: "Benvenuto su TaskMind", subtitle: "Scrivi o di' quello che hai in mente — TaskMind trasforma note disordinate in attività organizzate automaticamente."),
            "nl": Copy(title: "Welkom bij TaskMind", subtitle: "Schrijf of zeg wat je te binnen schiet — TaskMind zet rommelige notities automatisch om in georganiseerde taken."),
            "pl": Copy(title: "Witaj w TaskMind", subtitle: "Napisz lub powiedz, co masz na myśli — TaskMind automatycznie zamienia chaotyczne notatki w uporządkowane zadania."),
            "pt": Copy(title: "Bem-vindo ao TaskMind", subtitle: "Escreve ou diz o que tens em mente — o TaskMind transforma notas soltas em tarefas organizadas automaticamente."),
        ],
        .notes: [
            "en": Copy(title: "Just start typing", subtitle: "Type a note the way you normally would. As soon as you finish a line, TaskMind quietly turns it into a task — dates, priority, and category included."),
            "de": Copy(title: "Einfach loslegen", subtitle: "Schreib eine Notiz, wie du es sonst auch tust. Sobald du eine Zeile abschließt, macht TaskMind still und leise eine Aufgabe daraus — inklusive Datum, Priorität und Kategorie."),
            "es": Copy(title: "Simplemente empieza a escribir", subtitle: "Escribe una nota como sueles hacerlo. En cuanto termines una línea, TaskMind la convierte discretamente en una tarea — con fecha, prioridad y categoría incluidas."),
            "fr": Copy(title: "Commence simplement à écrire", subtitle: "Écris une note comme tu le fais d'habitude. Dès que tu termines une ligne, TaskMind la transforme discrètement en tâche — avec date, priorité et catégorie incluses."),
            "it": Copy(title: "Inizia semplicemente a scrivere", subtitle: "Scrivi una nota come faresti normalmente. Non appena finisci una riga, TaskMind la trasforma silenziosamente in un'attività — con data, priorità e categoria incluse."),
            "nl": Copy(title: "Begin gewoon met typen", subtitle: "Typ een notitie zoals je normaal zou doen. Zodra je een regel afmaakt, maakt TaskMind er stilletjes een taak van — inclusief datum, prioriteit en categorie."),
            "pl": Copy(title: "Po prostu zacznij pisać", subtitle: "Napisz notatkę tak, jak zwykle. Gdy tylko skończysz linijkę, TaskMind po cichu zamienia ją w zadanie — wraz z datą, priorytetem i kategorią."),
            "pt": Copy(title: "Começa simplesmente a escrever", subtitle: "Escreve uma nota como costumas fazer. Assim que terminares uma linha, o TaskMind transforma-a discretamente numa tarefa — com data, prioridade e categoria incluídas."),
        ],
        .examples: [
            "en": Copy(title: "See it work", subtitle: "A few more examples of what a single line can become."),
            "de": Copy(title: "So funktioniert's", subtitle: "Ein paar weitere Beispiele, was aus einer einzigen Zeile werden kann."),
            "es": Copy(title: "Míralo en acción", subtitle: "Algunos ejemplos más de lo que puede llegar a ser una sola línea."),
            "fr": Copy(title: "Vois-le en action", subtitle: "Quelques exemples de plus de ce qu'une seule ligne peut devenir."),
            "it": Copy(title: "Guardalo in azione", subtitle: "Altri esempi di cosa può diventare una singola riga."),
            "nl": Copy(title: "Zie het in actie", subtitle: "Nog een paar voorbeelden van wat één regel kan worden."),
            "pl": Copy(title: "Zobacz, jak to działa", subtitle: "Kilka kolejnych przykładów tego, czym może stać się jedna linijka."),
            "pt": Copy(title: "Vê como funciona", subtitle: "Mais alguns exemplos do que uma única linha pode se tornar."),
        ],
        .speech: [
            "en": Copy(title: "Or just say it", subtitle: "Tap the microphone in the notes bar and talk — your words are transcribed on-device and parsed the same way as typed text."),
            "de": Copy(title: "Oder sag es einfach", subtitle: "Tippe auf das Mikrofon in der Notizleiste und sprich — deine Worte werden auf dem Gerät transkribiert und genauso verarbeitet wie getippter Text."),
            "es": Copy(title: "O simplemente dilo", subtitle: "Toca el micrófono en la barra de notas y habla — tus palabras se transcriben en el dispositivo y se procesan igual que el texto escrito."),
            "fr": Copy(title: "Ou dis-le simplement", subtitle: "Appuie sur le micro dans la barre de notes et parle — tes mots sont transcrits sur l'appareil et traités comme du texte tapé."),
            "it": Copy(title: "O dillo semplicemente", subtitle: "Tocca il microfono nella barra delle note e parla — le tue parole vengono trascritte sul dispositivo e analizzate come il testo digitato."),
            "nl": Copy(title: "Of zeg het gewoon", subtitle: "Tik op de microfoon in de notitiebalk en praat — je woorden worden op het toestel getranscribeerd en op dezelfde manier verwerkt als getypte tekst."),
            "pl": Copy(title: "Albo po prostu powiedz", subtitle: "Stuknij mikrofon na pasku notatek i mów — twoje słowa są transkrybowane na urządzeniu i przetwarzane tak samo jak wpisany tekst."),
            "pt": Copy(title: "Ou di-lo simplesmente", subtitle: "Toca no microfone na barra de notas e fala — as tuas palavras são transcritas no dispositivo e processadas da mesma forma que o texto escrito."),
        ],
        .siri: [
            "en": Copy(title: "Add notes with Siri", subtitle: "Say “Hey Siri, add a note to TaskMind” from anywhere — even locked. Siri opens TaskMind straight into dictation, so you can start talking right away. Works in every language TaskMind supports."),
            "de": Copy(title: "Notizen mit Siri hinzufügen", subtitle: "Sag „Hey Siri, füge eine Notiz zu TaskMind hinzu“ — egal wo, auch gesperrt. Siri öffnet TaskMind direkt in der Diktierfunktion, sodass du sofort loslegen kannst. Funktioniert in jeder Sprache, die TaskMind unterstützt."),
            "es": Copy(title: "Añade notas con Siri", subtitle: "Di «Oye Siri, añade una nota a TaskMind» desde cualquier lugar, incluso con el móvil bloqueado. Siri abre TaskMind directamente en el dictado, para que puedas empezar a hablar de inmediato. Funciona en todos los idiomas que admite TaskMind."),
            "fr": Copy(title: "Ajoute des notes avec Siri", subtitle: "Dis « Dis Siri, ajoute une note à TaskMind » où que tu sois, même verrouillé. Siri ouvre TaskMind directement en dictée, pour que tu puisses parler tout de suite. Fonctionne dans toutes les langues prises en charge par TaskMind."),
            "it": Copy(title: "Aggiungi note con Siri", subtitle: "Di' «Hey Siri, aggiungi una nota a TaskMind» da qualsiasi luogo, anche a schermo bloccato. Siri apre TaskMind direttamente in modalità dettatura, così puoi iniziare a parlare subito. Funziona in tutte le lingue supportate da TaskMind."),
            "nl": Copy(title: "Notities toevoegen met Siri", subtitle: "Zeg \"Hey Siri, voeg een notitie toe aan TaskMind\" waar je ook bent, zelfs vergrendeld. Siri opent TaskMind direct in dicteermodus, zodat je meteen kunt beginnen met praten. Werkt in elke taal die TaskMind ondersteunt."),
            "pl": Copy(title: "Dodawaj notatki za pomocą Siri", subtitle: "Powiedz „Hej Siri, dodaj notatkę do TaskMind” z dowolnego miejsca, nawet gdy telefon jest zablokowany. Siri otwiera TaskMind od razu w trybie dyktowania, dzięki czemu możesz od razu zacząć mówić. Działa w każdym języku obsługiwanym przez TaskMind."),
            "pt": Copy(title: "Adiciona notas com a Siri", subtitle: "Diz «Hey Siri, adiciona uma nota ao TaskMind» de qualquer lugar, mesmo com o ecrã bloqueado. A Siri abre o TaskMind diretamente no modo de ditado, para que possas começar a falar de imediato. Funciona em todos os idiomas suportados pelo TaskMind."),
        ],
        .widgets: [
            "en": Copy(title: "Widgets for your Home and Lock Screen", subtitle: "See today's tasks, your progress, or jump straight into adding one — right from your Home Screen or Lock Screen. Long-press your Home Screen and tap + to add one."),
            "de": Copy(title: "Widgets für Home- und Sperrbildschirm", subtitle: "Sieh die heutigen Aufgaben, deinen Fortschritt oder springe direkt zum Hinzufügen — direkt vom Home- oder Sperrbildschirm aus. Halte deinen Homescreen gedrückt und tippe auf +, um eins hinzuzufügen."),
            "es": Copy(title: "Widgets para tu pantalla de inicio y bloqueo", subtitle: "Consulta las tareas de hoy, tu progreso o añade una directamente — desde tu pantalla de inicio o de bloqueo. Mantén pulsada la pantalla de inicio y toca + para añadir uno."),
            "fr": Copy(title: "Widgets pour l'écran d'accueil et de verrouillage", subtitle: "Consulte les tâches du jour, ta progression, ou ajoutes-en une directement — depuis ton écran d'accueil ou de verrouillage. Appuie longuement sur ton écran d'accueil et touche + pour en ajouter un."),
            "it": Copy(title: "Widget per Home e schermata di blocco", subtitle: "Guarda le attività di oggi, i tuoi progressi, o passa direttamente all'aggiunta — dalla Home o dalla schermata di blocco. Tieni premuta la schermata Home e tocca + per aggiungerne uno."),
            "nl": Copy(title: "Widgets voor je beginscherm en vergrendelscherm", subtitle: "Bekijk de taken van vandaag, je voortgang, of spring direct naar het toevoegen ervan — rechtstreeks vanaf je beginscherm of vergrendelscherm. Houd je beginscherm ingedrukt en tik op + om er een toe te voegen."),
            "pl": Copy(title: "Widżety na ekran główny i ekran blokady", subtitle: "Zobacz dzisiejsze zadania, swoje postępy lub od razu dodaj nowe — prosto z ekranu głównego lub ekranu blokady. Przytrzymaj ekran główny i stuknij +, aby dodać widżet."),
            "pt": Copy(title: "Widgets para o ecrã principal e de bloqueio", subtitle: "Vê as tarefas de hoje, o teu progresso, ou passa diretamente a adicionar uma — a partir do ecrã principal ou de bloqueio. Mantém premido o ecrã principal e toca em + para adicionar um."),
        ],
        .paywall: [
            "en": Copy(title: "Unlock TaskMind Pro", subtitle: "Unlimited tasks and every widget, with a 1-week free trial."),
            "de": Copy(title: "TaskMind Pro freischalten", subtitle: "Unbegrenzte Aufgaben und alle Widgets, mit einer 1-wöchigen kostenlosen Testphase."),
            "es": Copy(title: "Desbloquea TaskMind Pro", subtitle: "Tareas ilimitadas y todos los widgets, con una prueba gratuita de 1 semana."),
            "fr": Copy(title: "Débloque TaskMind Pro", subtitle: "Tâches illimitées et tous les widgets, avec un essai gratuit d'une semaine."),
            "it": Copy(title: "Sblocca TaskMind Pro", subtitle: "Attività illimitate e tutti i widget, con una prova gratuita di 1 settimana."),
            "nl": Copy(title: "Ontgrendel TaskMind Pro", subtitle: "Onbeperkte taken en alle widgets, met een gratis proefperiode van 1 week."),
            "pl": Copy(title: "Odblokuj TaskMind Pro", subtitle: "Nieograniczona liczba zadań i wszystkie widżety, z 1-tygodniowym darmowym okresem próbnym."),
            "pt": Copy(title: "Desbloqueia o TaskMind Pro", subtitle: "Tarefas ilimitadas e todos os widgets, com um teste gratuito de 1 semana."),
        ],
        .notifications: [
            "en": Copy(title: "Never miss a due date", subtitle: "TaskMind can remind you before a task is due. You can change this anytime in Settings."),
            "de": Copy(title: "Verpasse nie wieder einen Termin", subtitle: "TaskMind kann dich erinnern, bevor eine Aufgabe fällig ist. Du kannst das jederzeit in den Einstellungen ändern."),
            "es": Copy(title: "No te pierdas ninguna fecha límite", subtitle: "TaskMind puede recordarte antes de que venza una tarea. Puedes cambiar esto en cualquier momento en Ajustes."),
            "fr": Copy(title: "Ne rate plus jamais une échéance", subtitle: "TaskMind peut te rappeler avant qu'une tâche arrive à échéance. Tu peux modifier cela à tout moment dans les réglages."),
            "it": Copy(title: "Non perdere mai una scadenza", subtitle: "TaskMind può ricordarti prima che un'attività scada. Puoi modificarlo in qualsiasi momento nelle Impostazioni."),
            "nl": Copy(title: "Mis nooit meer een deadline", subtitle: "TaskMind kan je herinneren voordat een taak vervalt. Je kunt dit op elk moment wijzigen in Instellingen."),
            "pl": Copy(title: "Nigdy nie przegap terminu", subtitle: "TaskMind może przypomnieć Ci, zanim zadanie stanie się wymagalne. Możesz to zmienić w dowolnym momencie w Ustawieniach."),
            "pt": Copy(title: "Nunca percas um prazo", subtitle: "O TaskMind pode lembrar-te antes de uma tarefa vencer. Podes alterar isto a qualquer momento nas Definições."),
        ],
        .notificationsValue: [
            "en": Copy(title: "You can always turn this on later", subtitle: "Reminders help you catch a task before it's due. If you change your mind, enable notifications anytime in Settings."),
            "de": Copy(title: "Du kannst das jederzeit später aktivieren", subtitle: "Erinnerungen helfen dir, eine Aufgabe rechtzeitig zu erledigen. Du kannst Benachrichtigungen jederzeit in den Einstellungen aktivieren."),
            "es": Copy(title: "Siempre puedes activarlo más tarde", subtitle: "Los recordatorios te ayudan a no perderte una tarea antes de su vencimiento. Si cambias de opinión, activa las notificaciones cuando quieras en Ajustes."),
            "fr": Copy(title: "Tu peux toujours l'activer plus tard", subtitle: "Les rappels t'aident à ne pas manquer une tâche avant son échéance. Si tu changes d'avis, active les notifications à tout moment dans les réglages."),
            "it": Copy(title: "Puoi sempre attivarlo più tardi", subtitle: "I promemoria ti aiutano a non perdere un'attività prima della scadenza. Se cambi idea, attiva le notifiche in qualsiasi momento nelle Impostazioni."),
            "nl": Copy(title: "Je kunt dit later altijd inschakelen", subtitle: "Herinneringen helpen je een taak op tijd af te ronden. Als je van gedachten verandert, kun je meldingen op elk moment inschakelen in Instellingen."),
            "pl": Copy(title: "Zawsze możesz włączyć to później", subtitle: "Przypomnienia pomagają nie przegapić zadania przed terminem. Jeśli zmienisz zdanie, możesz włączyć powiadomienia w dowolnym momencie w Ustawieniach."),
            "pt": Copy(title: "Podes sempre ativar isto mais tarde", subtitle: "Os lembretes ajudam-te a não perder uma tarefa antes do prazo. Se mudares de ideias, ativa as notificações a qualquer momento nas Definições."),
        ],
        .final: [
            "en": Copy(title: "You're all set", subtitle: "Start capturing tasks the way you think — just write, and TaskMind handles the rest."),
            "de": Copy(title: "Alles bereit", subtitle: "Beginne, Aufgaben so festzuhalten, wie du denkst — schreib einfach, und TaskMind erledigt den Rest."),
            "es": Copy(title: "Todo listo", subtitle: "Empieza a capturar tareas tal como piensas — solo escribe, y TaskMind se encarga del resto."),
            "fr": Copy(title: "Tout est prêt", subtitle: "Commence à capturer des tâches comme tu le penses — écris simplement, et TaskMind s'occupe du reste."),
            "it": Copy(title: "Tutto pronto", subtitle: "Inizia a catturare le attività nel modo in cui pensi — scrivi semplicemente, e TaskMind farà il resto."),
            "nl": Copy(title: "Alles is klaar", subtitle: "Begin met het vastleggen van taken zoals jij denkt — schrijf gewoon, en TaskMind doet de rest."),
            "pl": Copy(title: "Wszystko gotowe", subtitle: "Zacznij zapisywać zadania tak, jak myślisz — po prostu pisz, a TaskMind zajmie się resztą."),
            "pt": Copy(title: "Está tudo pronto", subtitle: "Começa a capturar tarefas da forma como pensas — escreve simplesmente, e o TaskMind trata do resto."),
        ],
    ]
}

#Preview {
    OnboardingFlowView(onFinish: { _ in })
}
