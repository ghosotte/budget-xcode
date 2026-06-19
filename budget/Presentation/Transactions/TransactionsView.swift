import SwiftUI
import SwiftData

enum TransactionFilter: String, CaseIterable {
    case all, expenses, incomes

    var label: String {
        switch self {
        case .all:      return "Tout"
        case .expenses: return "Dépenses"
        case .incomes:  return "Revenus"
        }
    }
}

struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSession.self) private var session

    @Query private var households: [Household]
    @Query private var expenses: [Expense]
    @Query private var incomeEntries: [IncomeEntry]
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var month = Calendar.current.startOfMonth(for: .now)
    @Binding var filter: TransactionFilter
    @State private var categoryFilter: Category?
    @State private var editTarget: TransactionItem?

    private var household: Household? {
        households.first(where: \.isDefault) ?? households.first
    }

    // MARK: — Données filtrées

    private var monthItems: [TransactionItem] {
        var items: [TransactionItem] = []
        if filter != .incomes {
            items += expenses
                .filter {
                    $0.household == household && $0.effectiveMonth == month
                        && (categoryFilter == nil || $0.category == categoryFilter)
                }
                .map { TransactionItem.expense($0) }
        }
        if filter != .expenses && categoryFilter == nil {
            items += incomeEntries
                .filter { $0.household == household && $0.effectiveMonth == month }
                .map { TransactionItem.income($0) }
        }
        return items.sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
    }

    private var dayGroups: [(day: Date, items: [TransactionItem])] {
        let calendar = Calendar.current
        return Dictionary(grouping: monthItems) { calendar.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, items: $0.value) }
    }

    private var monthExpensesTotal: Decimal {
        expenses
            .filter { $0.household == household && $0.effectiveMonth == month && $0.status == .real }
            .reduce(0) { $0 + $1.amount }
    }

    private var monthIncomeTotal: Decimal {
        incomeEntries
            .filter { $0.household == household && $0.effectiveMonth == month && $0.status == .real }
            .reduce(0) { $0 + $1.amount }
    }

    // MARK: — Body

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                monthSelector
                filterBar
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 10)

            if dayGroups.isEmpty {
                emptyState
            } else {
                transactionList
            }
        }
        .background(Color.budgetBg)
        .sheet(item: $editTarget) { item in
            switch item {
            case .expense(let expense): ExpenseFormView(expense: expense)
            case .income(let income):   IncomeFormView(income: income)
            }
        }
        .task(id: month) {
            await MonthSyncService.refreshMonth(month, session: session, context: modelContext)
        }
    }

    // MARK: — Sélecteur de mois

    private var monthSelector: some View {
        MonthSelector(month: $month) {
            HStack(spacing: 6) {
                Text(AmountFormatter.kpi(-monthExpensesTotal))
                    .foregroundStyle(Color.budgetDanger)
                Text("·")
                    .foregroundStyle(Color.budgetTextFaint)
                Text(AmountFormatter.kpi(monthIncomeTotal, signed: true))
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
                    Button("\(cat.emoji) \(cat.name)") { categoryFilter = cat }
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

    private var transactionList: some View {
        List {
            ForEach(dayGroups, id: \.day) { group in
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
                status: e.status,
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
                status: i.status,
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
