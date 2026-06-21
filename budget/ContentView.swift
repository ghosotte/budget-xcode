import GoogleSignIn
import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case home, transactions, budget, history, settings
}

enum TransactionFormKind: String, Identifiable, CaseIterable {
    case expense, income
    var id: Self { self }

    /// `LocalizedStringKey` (et non `String(localized:)`) pour que la résolution passe par
    /// le bundle surchargé (`LocalizedBundle`) qui suit la langue du foyer. `String(localized:)`
    /// court-circuite cette surcharge et renverrait toujours le français source.
    var label: LocalizedStringKey {
        switch self {
        case .expense: return "Dépense"
        case .income:  return "Revenu"
        }
    }
}

/// Conteneur du formulaire d'ajout avec bascule Dépense / Revenu intégrée.
struct TransactionFormView: View {
    @State private var kind: TransactionFormKind

    init(initial: TransactionFormKind) {
        _kind = State(initialValue: initial)
    }

    var body: some View {
        switch kind {
        case .expense: ExpenseFormView(kindSelection: $kind)
        case .income:  IncomeFormView(kindSelection: $kind)
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(LanguageStore.self) private var language
    @AppStorage("appTheme") private var themeRaw = AppTheme.system.rawValue
    @State private var authSession = AuthSession()
    @State private var network = NetworkMonitor.shared
    @State private var selectedTab = AppTab.home
    @State private var formKind: TransactionFormKind?
    @State private var transactionsFilter = TransactionFilter.all

    /// Type par défaut à l'ouverture du FAB : revenu si l'onglet Transactions est
    /// filtré sur les revenus, sinon dépense.
    private var defaultFormKind: TransactionFormKind {
        selectedTab == .transactions && transactionsFilter == .incomes ? .income : .expense
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            DashboardView(
                onSeeAllExpenses: { selectedTab = .transactions },
                onAddExpense: { formKind = .expense }
            )
            .tabItem { Label("Accueil", systemImage: "house.fill") }
            .tag(AppTab.home)

            TransactionsView(filter: $transactionsFilter)
                .tabItem { Label("Transactions", systemImage: "list.bullet") }
                .tag(AppTab.transactions)

            BudgetTabView()
                .tabItem { Label("Budget", systemImage: "chart.bar.fill") }
                .tag(AppTab.budget)

            HistoryView()
                .tabItem { Label("Historique", systemImage: "clock.arrow.circlepath") }
                .tag(AppTab.history)

            SettingsView()
                .tabItem { Label("Réglages", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .tint(.budgetPrimary)
        .preferredColorScheme(AppTheme(rawValue: themeRaw)?.colorScheme)
        .overlay(alignment: .bottomTrailing) {
            if selectedTab == .home || selectedTab == .transactions {
                FABButton { formKind = defaultFormKind }
                    .padding(.trailing, 20)
                    .padding(.bottom, 90)
            }
        }
        .sheet(item: $formKind) { kind in
            TransactionFormView(initial: kind)
        }
        // Reconstruit tout le sous-arbre des onglets au changement de langue → les `Text`
        // sont ré-résolus via le bundle surchargé (le `.task` reste sur le `ZStack` stable).
        .id(language.code)
    }

    var body: some View {
        // Le `ZStack` garde une identité STABLE : c'est lui qui porte `.task` (cold-start)
        // et les autres modificateurs de cycle de vie, donc ils ne re-tournent pas quand la
        // langue change. Seul le `TabView` interne reçoit `.id(language.code)` : changer de
        // langue (foyer local OU cloud) reconstruit l'arbre des onglets et force la
        // ré-résolution des chaînes via le bundle surchargé. La sélection d'onglet est
        // préservée (binding sur `$selectedTab`, état hors du sous-arbre reconstruit).
        let _ = print("🌐LANG ContentView body render language.code=\(language.code)")
        ZStack {
            tabs
        }
        .environment(authSession)
        .onOpenURL { url in
            GIDSignIn.sharedInstance.handle(url)
        }
        .task {
            MetricsCollector.shared.subscribe()
            // Applique une seule fois les réglages (devise/langue) du foyer cloud courant.
            // `AuthSession.init` ne le fait plus (effet de bord rejoué à chaque reconstruction
            // de ContentView → écrasait le changement de langue).
            authSession.bootstrap()
            SeedService.seedIfNeeded(context: modelContext)
            RecurringService.generateExpenses(context: modelContext)
            // Le foyer ACTIF (local `isDefault`, persistant) pilote devise + langue, qu'on soit
            // hors ligne OU connecté : `bootstrap()` a posé celles du foyer cloud courant, mais le
            // foyer actif peut être un foyer local (anonyme) distinct. On applique donc toujours
            // celles du foyer actif local s'il existe → le choix de foyer survit au redémarrage.
            if let def = (try? modelContext.fetch(FetchDescriptor<Household>()))?.first(where: { $0.isDefault }) {
                Currency.setActive(def.currencyCode)
                AppLocale.setActive(def.locale)
            }
            if authSession.isAuthenticated {
                do {
                    try await SyncService.syncAll(session: authSession, context: modelContext)
                    try await SyncService.pullCategories(context: modelContext)
                    try modelContext.save()
                } catch {
                    SyncErrorReporter.report(error, context: "ContentView.task.coldStart", surfacing: true)
                }
            }
        }
        .onChange(of: network.lastReconnectAt) { _, newValue in
            guard newValue != nil, authSession.isAuthenticated else { return }
            Task {
                do {
                    try await SyncService.quickSync(session: authSession, context: modelContext)
                } catch {
                    SyncErrorReporter.report(error, context: "NetworkMonitor.reconnect")
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, authSession.isAuthenticated else { return }
            let lastSync = UserDefaults.standard.double(forKey: "lastSyncAt")
            guard Date.now.timeIntervalSince1970 - lastSync > 60 else { return }
            Task {
                do {
                    try await SyncService.quickSync(session: authSession, context: modelContext)
                } catch {
                    SyncErrorReporter.report(error, context: "ContentView.scenePhase.active")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: APIClient.sessionInvalidatedNotification)) { _ in
            Task {
                await authSession.logout(context: modelContext)
            }
        }
    }
}

// MARK: — FAB

private struct FABButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Circle().fill(Color.budgetPrimary))
                .shadow(color: Color.budgetPrimary.opacity(0.35), radius: 10, y: 4)
        }
        .accessibilityLabel("Ajouter une transaction")
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            Household.self, Category.self, Subcategory.self, IncomeCategory.self,
            BudgetExpenseLine.self, BudgetIncome.self, Expense.self,
            IncomeEntry.self, RecurringExpense.self,
        ], inMemory: true)
}
