import GoogleSignIn
import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case home, transactions, budget, history, settings
}

enum TransactionFormKind: Identifiable {
    case expense, income
    var id: Self { self }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appTheme") private var themeRaw = AppTheme.system.rawValue
    @State private var authSession = AuthSession()
    @State private var selectedTab = AppTab.home
    @State private var formKind: TransactionFormKind?

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Accueil", systemImage: "house.fill", value: AppTab.home) {
                DashboardView(
                    onSeeAllExpenses: { selectedTab = .transactions },
                    onAddExpense: { formKind = .expense }
                )
            }
            Tab("Dépenses", systemImage: "list.bullet", value: AppTab.transactions) {
                TransactionsView()
            }
            Tab("Budget", systemImage: "chart.bar.fill", value: AppTab.budget) {
                BudgetTabView()
            }
            Tab("Historique", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                HistoryView()
            }
            Tab("Réglages", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tint(.budgetPrimary)
        .preferredColorScheme(AppTheme(rawValue: themeRaw)?.colorScheme)
        .overlay(alignment: .bottomTrailing) {
            if selectedTab == .home || selectedTab == .transactions {
                FABMenuButton { kind in
                    formKind = kind
                }
                .padding(.trailing, 20)
                .padding(.bottom, 90)
            }
        }
        .sheet(item: $formKind) { kind in
            switch kind {
            case .expense: ExpenseFormView()
            case .income:  IncomeFormView()
            }
        }
        .environment(authSession)
        .onOpenURL { url in
            GIDSignIn.sharedInstance.handle(url)
        }
        .task {
            SeedService.seedIfNeeded(context: modelContext)
            RecurringService.generateExpenses(context: modelContext)
            NetworkMonitor.shared.setReconnectHandler { [authSession] in
                guard authSession.isAuthenticated else { return }
                try? await SyncService.quickSync(session: authSession, context: modelContext)
            }
            if authSession.isAuthenticated {
                try? await SyncService.syncAll(session: authSession, context: modelContext)
                try? await SyncService.pullCategories(context: modelContext)
                try? modelContext.save()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, authSession.isAuthenticated else { return }
            let lastSync = UserDefaults.standard.double(forKey: "lastSyncAt")
            guard Date.now.timeIntervalSince1970 - lastSync > 60 else { return }
            Task {
                try? await SyncService.quickSync(session: authSession, context: modelContext)
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

private struct FABMenuButton: View {
    let onSelect: (TransactionFormKind) -> Void

    var body: some View {
        Menu {
            Button { onSelect(.expense) } label: {
                Label("Dépense", systemImage: "arrow.up")
            }
            Button { onSelect(.income) } label: {
                Label("Revenu", systemImage: "arrow.down")
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                Text("Dépense")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            .background(Capsule().fill(Color.budgetPrimary))
            .shadow(color: Color.budgetPrimary.opacity(0.35), radius: 10, y: 4)
        } primaryAction: {
            onSelect(.expense)
        }
        .menuIndicator(.hidden)
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
