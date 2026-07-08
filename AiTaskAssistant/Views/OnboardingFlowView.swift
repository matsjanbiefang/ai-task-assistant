import SwiftUI

// Phase 5: full feature tour shown once before the app is used. Each page mirrors the real UI
// it's introducing rather than describing it in the abstract, matching the rest of the app's
// "show, don't tell" style.
//
// Real-device feedback folded in here:
// - Language selection moved to the FIRST page (was last) — the rest of the tour's copy is
//   localized live against whatever is picked, via `OnboardingCopy.text(for:in:)` below.
// - Every page's content is now vertically centered instead of pinned to the top, leaving the
//   lower half of the screen visibly empty.
// - Notification permission is requested when tapping the shared Continue/Get Started button on
//   the notifications page itself, not from a separate in-page button.
// - Two new pages: worked examples (including the shopping-list feature) and a more detailed
//   explanation of how the Siri shortcut behaves.
struct OnboardingFlowView: View {
    var onFinish: (SupportedLanguage) -> Void

    private enum Page: Int, CaseIterable {
        case language, welcome, notes, examples, speech, siri, widgets, notifications
    }

    @State private var page: Page = .language
    @State private var selectedLanguage = SupportedLanguage.deviceDefault.isSupportedByLanguagePack
        ? SupportedLanguage.deviceDefault : .en

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                OnboardingLanguageView(embedded: true, selected: $selectedLanguage)
                    .tag(Page.language)
                WelcomePage(language: selectedLanguage).tag(Page.welcome)
                NotesDemoPage(language: selectedLanguage).tag(Page.notes)
                ExamplesPage(language: selectedLanguage).tag(Page.examples)
                SpeechDemoPage(language: selectedLanguage).tag(Page.speech)
                SiriPage(language: selectedLanguage).tag(Page.siri)
                WidgetsPage(language: selectedLanguage).tag(Page.widgets)
                NotificationsPage(language: selectedLanguage).tag(Page.notifications)
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
            if page == .notifications {
                Task { _ = await NotificationService.shared.requestPermission() }
            }
            if isLastPage {
                onFinish(selectedLanguage)
            } else if let next = Page(rawValue: page.rawValue + 1) {
                withAnimation { page = next }
            }
        } label: {
            Text(isLastPage ? OnboardingCopy.getStarted(selectedLanguage) : OnboardingCopy.continueLabel(selectedLanguage))
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
        OnboardingPageLayout(icon: "square.and.pencil", title: copy.title, subtitle: copy.subtitle) {
            exampleCard(input: "call max tomorrow!!", result: "1 task created", resultIcon: "checkmark.circle.fill")
        }
    }
}

// New page: a few more worked examples, explicitly including the shopping-list feature, since
// the single note-to-task example on the previous page didn't show the breadth of what gets
// detected or that shopping lines route somewhere different entirely.
private struct ExamplesPage: View {
    let language: SupportedLanguage
    var body: some View {
        let copy = OnboardingCopy.text(for: .examples, in: language)
        OnboardingPageLayout(icon: "sparkles", title: copy.title, subtitle: copy.subtitle) {
            VStack(spacing: 10) {
                exampleCard(input: "milk, eggs, bread", result: "Added to your shopping list", resultIcon: "cart.fill")
                exampleCard(input: "dentist next tuesday 10am", result: "Task created · Tuesday · 10:00", resultIcon: "calendar")
                exampleCard(input: "call mom !!", result: "Task created · High priority", resultIcon: "flag.fill")
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
                siriStep(icon: "waveform", text: "“Hey Siri, add a note to TaskMind”")
                siriStep(icon: "arrow.turn.down.right", text: "TaskMind opens, ready to listen")
                siriStep(icon: "text.bubble.fill", text: "“Ready. What's on your mind?”")
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

private struct NotificationsPage: View {
    let language: SupportedLanguage
    var body: some View {
        let copy = OnboardingCopy.text(for: .notifications, in: language)
        OnboardingPageLayout(icon: "bell.badge.fill", title: copy.title, subtitle: copy.subtitle) { EmptyView() }
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
// it's saved anywhere — so its own instructional text is translated directly here against the
// in-progress selection, rather than through the general string-catalog/environment-locale
// mechanism the rest of the app uses (see AppLanguage.swift) which only takes effect on next
// launch/after this flow finishes. The illustrative example inputs on the Notes/Examples/Siri
// pages are intentionally left in English in every language for now — translating realistic,
// natural-sounding sample notes per language is future work, not a quick lookup.
private enum OnboardingCopy {
    // fileprivate (not private) — unlike top-level `private`, a *nested* `private` type is scoped
    // strictly to its enclosing declaration's own body, not the whole file, so the sibling page
    // structs below (SiriPage, ExamplesPage, etc.) couldn't otherwise reference this type at all.
    fileprivate enum Page {
        case welcome, notes, examples, speech, siri, widgets, notifications
    }

    private struct Copy { let title: String; let subtitle: String }

    static func text(for page: Page, in language: SupportedLanguage) -> (title: String, subtitle: String) {
        let table = copy[page] ?? [:]
        let copy = table[language.rawValue] ?? table["en"]!
        return (copy.title, copy.subtitle)
    }

    static func continueLabel(_ language: SupportedLanguage) -> String {
        continueLabels[language.rawValue] ?? continueLabels["en"]!
    }

    static func getStarted(_ language: SupportedLanguage) -> String {
        getStartedLabels[language.rawValue] ?? getStartedLabels["en"]!
    }

    private static let continueLabels: [String: String] = [
        "en": "Continue", "de": "Weiter", "es": "Continuar", "fr": "Continuer",
        "it": "Continua", "nl": "Doorgaan", "pl": "Dalej", "pt": "Continuar",
    ]

    private static let getStartedLabels: [String: String] = [
        "en": "Get Started", "de": "Los geht's", "es": "Empezar", "fr": "Commencer",
        "it": "Inizia", "nl": "Aan de slag", "pl": "Zaczynajmy", "pt": "Começar",
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
    ]
}

#Preview {
    OnboardingFlowView(onFinish: { _ in })
}
