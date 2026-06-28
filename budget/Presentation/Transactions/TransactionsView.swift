import SwiftUI
import SwiftData
import BudgetKit

enum TransactionFilter: String, CaseIterable {
    case all, expenses, incomes

    var label: String {
        switch self {
        case .all:      return NSLocalizedString("Tout", comment: "")
        case .expenses: return NSLocalizedString("Dépenses", comment: "")
        case .incomes:  return NSLocalizedString("Revenus", comment: "")
        }
    }
}

/// Couche de navigation : détient le mois sélectionné (`@State`) et déclenche la sync.
/// Le `@Query` scopé au mois vit dans `TransactionsContent`, recréé à chaque changement de mois.
struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSession.self) private var session

    @Binding var filter: TransactionFilter
    @State private var month = Calendar.current.startOfMonth(for: .now)

    var body: some View {
        TransactionsContent(month: $month, filter: $filter)
            .task(id: month) {
                await MonthSyncService.refreshMonth(month, session: session, context: modelContext)
            }
            .refreshable {
                await MonthSyncService.refreshMonth(month, session: session, context: modelContext, force: true)
            }
    }
}

/// Couche données : `@Query` filtré sur `effectiveMonth` du mois affiché → SQLite ne charge que ce mois.
private struct TransactionsContent: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSession.self) private var session

    @Binding var month: Date
    @Binding var filter: TransactionFilter

    @Query private var households: [Household]
    @Query private var expenses: [Expense]
    @Query private var incomeEntries: [IncomeEntry]
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var categoryFilter: Category?
    @State private var editTarget: TransactionItem?

    init(month: Binding<Date>, filter: Binding<TransactionFilter>) {
        _month = month
        _filter = filter
        _expenses = Query(filter: Expense.monthPredicate(month.wrappedValue))
        _incomeEntries = Query(filter: IncomeEntry.monthPredicate(month.wrappedValue))
    }

    private var household: Household? {
        households.first(where: \.isDefault) ?? households.first
    }

    // MARK: — Données filtrées
    // `@Query` a déjà borné au mois ; le filtre Swift résiduel ne fait que foyer + catégorie + type.

    /// Résultat dérivé calculé EN UNE PASSE par render. Avant : `monthItems` + 2 totaux faisaient
    /// chacun un `.filter { $0.household == ... }` → la relation `household` était faultée 3× par ligne
    /// par render. Ici on filtre foyer une seule fois.
    private struct MonthData {
        var groups: [(day: Date, items: [TransactionItem])] = []
        var expenseTotal: Decimal = 0
        var incomeTotal: Decimal = 0
    }

    private var monthData: MonthData {
        let exp = expenses.filter { $0.household == household }
        let inc = incomeEntries.filter { $0.household == household }

        var items: [TransactionItem] = []
        if filter != .incomes {
            items += exp
                .filter { categoryFilter == nil || $0.category == categoryFilter }
                .map { TransactionItem.expense($0) }
        }
        if filter != .expenses && categoryFilter == nil {
            items += inc.map { TransactionItem.income($0) }
        }
        items.sort { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }

        let calendar = Calendar.current
        let groups = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, items: $0.value) }

        return MonthData(
            groups: groups,
            expenseTotal: exp.filter { $0.status == .real }.reduce(0) { $0 + $1.amount },
            incomeTotal: inc.filter { $0.status == .real }.reduce(0) { $0 + $1.amount }
        )
    }

    // MARK: — Body

    var body: some View {
        let data = monthData
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                monthSelector(expenseTotal: data.expenseTotal, incomeTotal: data.incomeTotal)
                filterBar
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 10)

            if data.groups.isEmpty {
                emptyState
            } else {
                transactionList(groups: data.groups)
            }
        }
        .background(Color.budgetBg)
        .sheet(item: $editTarget) { item in
            switch item {
            case .expense(let expense): ExpenseFormView(expense: expense)
            case .income(let income):   IncomeFormView(income: income)
            }
        }
    }

    // MARK: — Sélecteur de mois

    private func monthSelector(expenseTotal: Decimal, incomeTotal: Decimal) -> some View {
        MonthSelector(month: $month) {
            HStack(spacing: 6) {
                Text(AmountFormatter.kpi(-expenseTotal))
                    .foregroundStyle(Color.budgetDanger)
                Text("·")
                    .foregroundStyle(Color.budgetTextFaint)
                Text(AmountFormatter.kpi(incomeTotal, signed: true))
                    .foregroundStyle(Color.budgetPrimary)
            }
            .font(.caption.weight(.medium))
        }
    }

    // MARK: — Filtres

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker("Filtre", selection: $filter) {
                ForEach(TransactionFilter.allCases, id: \.self) { f in
                    Text(f.label).tag(f)
                }
            }
            .pickerStyle(.segmented)

            Menu {
                Button("Toutes les catégories") { categoryFilter = nil }
                Divider()
                ForEach(categories) { cat in
                    Button("\(cat.emoji) \(cat.displayName)") { categoryFilter = cat }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(categoryFilter == nil ? Color.budgetText : .white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(categoryFilter == nil ? Color.budgetSurfaceMute : Color.budgetPrimary))
            }
            .disabled(filter == .incomes)
        }
    }

    // MARK: — Liste

    private func transactionList(groups: [(day: Date, items: [TransactionItem])]) -> some View {
        List {
            ForEach(groups, id: \.day) { group in
                Section {
                    ForEach(group.items) { item in
                        TransactionRow(item: item)
                            .listRowBackground(Color.budgetSurface)
                            .listRowSeparatorTint(Color.budgetBorder.opacity(0.6))
                            .contentShape(Rectangle())
                            .onTapGesture { editTarget = item }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    delete(item)
                                } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                                Button {
                                    duplicate(item)
                                } label: {
                                    Label("Dupliquer", systemImage: "plus.square.on.square")
                                }
                                .tint(Color.budgetPrimary)
                            }
                    }
                } header: {
                    Text(AppDateFormatter.daySection(group.day))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.budgetTextMute)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 90, for: .scrollContent)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("📭")
                .font(.system(size: 40))
            Text("Aucune transaction ce mois-ci.")
                .font(.subheadline)
                .foregroundStyle(Color.budgetTextMute)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: — Actions

    private func delete(_ item: TransactionItem) {
        switch item {
        case .expense(let e): PushService.deleteExpense(e, session: session, context: modelContext)
        case .income(let i):  PushService.deleteIncome(i, session: session, context: modelContext)
        }
    }

    private func duplicate(_ item: TransactionItem) {
        switch item {
        case .expense(let e):
            let copy = Expense(
                category: e.category,
                subcategory: e.subcategory,
                amount: e.amount,
                label: e.label,
                spentAt: e.spentAt,
                accountingMonth: e.accountingMonth,
                tags: e.tags,
                notes: e.notes
            )
            copy.household = e.household
            PushService.markForUpload(&copy.syncStatus, household: copy.household)
            modelContext.insert(copy)
        case .income(let i):
            let copy = IncomeEntry(
                incomeCategory: i.incomeCategory,
                amount: i.amount,
                label: i.label,
                receivedAt: i.receivedAt,
                accountingMonth: i.accountingMonth,
                notes: i.notes
            )
            copy.household = i.household
            PushService.markForUpload(&copy.syncStatus, household: copy.household)
            modelContext.insert(copy)
        }
        try? modelContext.save()
        PushService.afterLocalChange(session: session, context: modelContext)
    }
}

// MARK: — Ligne de transaction

private struct TransactionRow: View {
    let item: TransactionItem

    var body: some View {
        HStack(spacing: 12) {
            Text(item.emoji)
                .font(.system(size: 18))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.budgetSurfaceMute))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.budgetText)
                        .lineLimit(1)
                    if item.status == .planned {
                        Text("Prévu")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.budgetAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.budgetAccent.opacity(0.12)))
                    }
                }
                Text(item.categoryName)
                    .font(.caption)
                    .foregroundStyle(Color.budgetTextMute)
            }

            Spacer()

            Text(AmountFormatter.full(item.amount, signed: true))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(item.isIncome ? Color.budgetPrimary : Color.budgetDanger)
        }
        .padding(.vertical, 4)
        .opacity(item.status == .planned ? 0.7 : 1)
    }
}

#Preview {
    TransactionsView(filter: .constant(.all))
        .modelContainer(for: [
            Household.self, Category.self, Subcategory.self, IncomeCategory.self,
            BudgetExpenseLine.self, BudgetIncome.self, Expense.self,
            IncomeEntry.self, RecurringExpense.self,
        ], inMemory: true)
}
