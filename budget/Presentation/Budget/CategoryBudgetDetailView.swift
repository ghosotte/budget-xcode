import SwiftUI
import SwiftData

struct CategoryBudgetDetailView: View {
    let category: Category
    let month: Date

    @Environment(\.dismiss) private var dismiss
    @Query private var households: [Household]
    @Query private var budgetExpenseLines: [BudgetExpenseLine]

    @State private var formTarget: ExpenseLineFormTarget?

    private var household: Household? {
        households.first(where: \.isDefault) ?? households.first
    }

    private var lines: [BudgetExpenseLine] {
        budgetExpenseLines
            .filter { $0.household == household && $0.category == category && $0.isActive(for: month) }
            .sorted {
                ($0.subcategory?.sortOrder ?? -1) < ($1.subcategory?.sortOrder ?? -1)
            }
    }

    private var total: Decimal {
        lines.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            Group {
                if lines.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            ForEach(lines) { line in
                                Button { formTarget = .edit(line) } label: {
                                    LineRow(line: line)
                                }
                                .listRowBackground(Color.budgetSurface)
                            }
                        } footer: {
                            Text("Total : \(AmountFormatter.kpi(total)) · \(AppDateFormatter.monthYear(month))")
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.budgetBg)
            .navigationTitle("\(category.emoji) \(category.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { formTarget = .new } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $formTarget) { target in
                BudgetExpenseLineFormView(category: category, month: month, line: target.line)
                    .presentationDetents([.medium, .large])
            }
        }
        .tint(.budgetPrimary)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text(category.emoji)
                .font(.system(size: 40))
            Text("Aucune ligne budgétaire pour \(AppDateFormatter.monthYear(month)).")
                .font(.subheadline)
                .foregroundStyle(Color.budgetTextMute)
                .multilineTextAlignment(.center)
            Button { formTarget = .new } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Ajouter une ligne")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(Capsule().fill(Color.budgetPrimary))
            }
        }
        .padding(40)
    }
}

enum ExpenseLineFormTarget: Identifiable {
    case new
    case edit(BudgetExpenseLine)

    var id: String {
        switch self {
        case .new:            return "new"
        case .edit(let line): return line.id.uuidString
        }
    }

    var line: BudgetExpenseLine? {
        if case .edit(let line) = self { return line }
        return nil
    }
}

private struct LineRow: View {
    let line: BudgetExpenseLine

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.subcategory?.name ?? "Budget global")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.budgetText)
                Text(line.frequency.label)
                    .font(.caption)
                    .foregroundStyle(Color.budgetTextMute)
            }
            Spacer()
            Text(AmountFormatter.kpi(line.amount))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.budgetText)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.budgetTextFaint)
        }
        .padding(.vertical, 4)
    }
}
