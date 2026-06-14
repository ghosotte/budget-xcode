import SwiftUI
import SwiftData

struct BilanView: View {
    let month: Date

    @Query private var households: [Household]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var budgetExpenseLines: [BudgetExpenseLine]
    @Query private var budgetIncomes: [BudgetIncome]
    @Query private var expenses: [Expense]
    @Query private var incomeEntries: [IncomeEntry]

    @State private var expanded: Set<UUID> = []

    private var household: Household? {
        households.first(where: \.isDefault) ?? households.first
    }

    // MARK: — Totaux

    private var activeExpenseLines: [BudgetExpenseLine] {
        budgetExpenseLines.filter { $0.household == household && $0.isActive(for: month) }
    }

    private var monthRealExpenses: [Expense] {
        expenses.filter { $0.household == household && $0.effectiveMonth == month && $0.status == .real }
    }

    private var totalBudgetExpenses: Decimal {
        activeExpenseLines.reduce(0) { $0 + $1.amount }
    }

    private var totalRealExpenses: Decimal {
        monthRealExpenses.reduce(0) { $0 + $1.amount }
    }

    private var totalBudgetIncome: Decimal {
        budgetIncomes
            .filter { $0.household == household && $0.isActive(for: month) }
            .reduce(0) { $0 + $1.amount }
    }

    private var totalRealIncome: Decimal {
        incomeEntries
            .filter { $0.household == household && $0.effectiveMonth == month && $0.status == .real }
            .reduce(0) { $0 + $1.amount }
    }

    // MARK: — Lignes par catégorie

    private var rows: [BilanRowData] {
        categories.compactMap { category in
            let lines = activeExpenseLines.filter { $0.category == category }
            let catExpenses = monthRealExpenses.filter { $0.category == category }
            let budget = lines.reduce(Decimal(0)) { $0 + $1.amount }
            let real = catExpenses.reduce(Decimal(0)) { $0 + $1.amount }
            guard budget > 0 || real > 0 else { return nil }

            var subs: [BilanRowData.Sub] = category.subcategories
                .sorted { $0.sortOrder < $1.sortOrder }
                .compactMap { sub in
                    let subBudget = lines.filter { $0.subcategory == sub }.reduce(Decimal(0)) { $0 + $1.amount }
                    let subReal = catExpenses.filter { $0.subcategory == sub }.reduce(Decimal(0)) { $0 + $1.amount }
                    guard subBudget > 0 || subReal > 0 else { return nil }
                    return BilanRowData.Sub(id: sub.id, name: sub.name, budget: subBudget, real: subReal)
                }

            if !subs.isEmpty {
                let generalBudget = lines.filter { $0.subcategory == nil }.reduce(Decimal(0)) { $0 + $1.amount }
                let generalReal = catExpenses.filter { $0.subcategory == nil }.reduce(Decimal(0)) { $0 + $1.amount }
                if generalBudget > 0 || generalReal > 0 {
                    subs.insert(BilanRowData.Sub(id: category.id, name: "Général", budget: generalBudget, real: generalReal), at: 0)
                }
            }

            return BilanRowData(
                id: category.id,
                emoji: category.emoji,
                name: category.name,
                budget: budget,
                real: real,
                subs: subs
            )
        }
    }

    // MARK: — Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                totalsCard
                if rows.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 12) {
                        ForEach(rows) { row in
                            CategoryBilanCard(
                                row: row,
                                isExpanded: expanded.contains(row.id),
                                onToggle: { toggle(row.id) }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 110)
        }
        .background(Color.budgetBg)
    }

    private func toggle(_ id: UUID) {
        withAnimation(.snappy(duration: 0.2)) {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        }
    }

    // MARK: — Totaux

    private var totalsCard: some View {
        VStack(spacing: 12) {
            totalRow(
                label: "REVENUS",
                real: totalRealIncome,
                budget: totalBudgetIncome,
                color: Color.budgetPrimary
            )
            totalRow(
                label: "DÉPENSES",
                real: totalRealExpenses,
                budget: totalBudgetExpenses,
                color: Color.budgetDanger
            )
            Divider().overlay(Color.budgetBorder.opacity(0.6))
            HStack {
                Text("Solde réel")
                    .font(.caption)
                    .foregroundStyle(Color.budgetTextMute)
                Spacer()
                Text(AmountFormatter.kpi(totalRealIncome - totalRealExpenses, signed: true))
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(totalRealIncome - totalRealExpenses >= 0 ? Color.budgetPrimary : Color.budgetDanger)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private func totalRow(label: String, real: Decimal, budget: Decimal, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Color.budgetTextMute)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(AmountFormatter.kpi(real))
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(color)
                Text("prévu \(AmountFormatter.kpi(budget))")
                    .font(.caption2)
                    .foregroundStyle(Color.budgetTextFaint)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("📊")
                .font(.system(size: 40))
            Text("Aucun budget ni dépense pour \(AppDateFormatter.monthYear(month)).")
                .font(.subheadline)
                .foregroundStyle(Color.budgetTextMute)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.budgetSurface)
            .stroke(Color.budgetBorder, lineWidth: 1)
    }
}

// MARK: — Carte catégorie

private struct CategoryBilanCard: View {
    let row: BilanRowData
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: row.subs.isEmpty ? {} : onToggle) {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Text(row.emoji)
                            .font(.system(size: 18))
                        Text(row.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.budgetText)
                            .lineLimit(1)
                        Spacer()
                        Text(amountSummary(real: row.real, budget: row.budget))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(row.budget > 0 && row.real > row.budget ? Color.budgetDanger : Color.budgetText)
                        if !row.subs.isEmpty {
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.budgetTextFaint)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        }
                    }
                    ProgressBar(
                        ratio: ratio(row.real, of: row.budget),
                        color: row.budget > 0 && row.real > row.budget ? .budgetDanger : .budgetPrimary
                    )
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(row.subs) { sub in
                        HStack {
                            Text(sub.name)
                                .font(.caption)
                                .foregroundStyle(Color.budgetTextMute)
                            Spacer()
                            Text(amountSummary(real: sub.real, budget: sub.budget))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(sub.budget > 0 && sub.real > sub.budget ? Color.budgetDanger : Color.budgetText)
                        }
                    }
                }
                .padding(.top, 2)
                .padding(.leading, 26)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.budgetSurface)
                .stroke(Color.budgetBorder, lineWidth: 1)
        )
    }

    private func amountSummary(real: Decimal, budget: Decimal) -> String {
        budget > 0
            ? "\(AmountFormatter.kpi(real)) / \(AmountFormatter.kpi(budget))"
            : AmountFormatter.kpi(real)
    }

    private func ratio(_ value: Decimal, of total: Decimal) -> Double {
        guard total > 0 else { return value > 0 ? 1 : 0 }
        let r = (value as NSDecimalNumber).doubleValue / (total as NSDecimalNumber).doubleValue
        return min(max(r, 0), 1)
    }
}

struct BilanRowData: Identifiable {
    struct Sub: Identifiable {
        let id: UUID
        let name: String
        let budget: Decimal
        let real: Decimal
    }

    let id: UUID
    let emoji: String
    let name: String
    let budget: Decimal
    let real: Decimal
    let subs: [Sub]
}
