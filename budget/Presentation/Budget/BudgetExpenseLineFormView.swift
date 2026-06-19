import SwiftUI
import SwiftData

struct BudgetExpenseLineFormView: View {
    let category: Category
    let month: Date
    private let line: BudgetExpenseLine?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSession.self) private var session
    @Query private var households: [Household]
    @Query private var budgetExpenseLines: [BudgetExpenseLine]

    @State private var amountText: String
    @State private var frequency: Frequency
    @State private var subcategory: Subcategory?
    @State private var scope = EditScope.fromThisMonth
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(category: Category, month: Date, line: BudgetExpenseLine? = nil) {
        self.category = category
        self.month = month
        self.line = line
        _amountText = State(initialValue: line.map {
            NSDecimalNumber(decimal: $0.amount).stringValue.replacingOccurrences(of: ".", with: ",")
        } ?? "")
        _frequency = State(initialValue: line?.frequency ?? .monthly)
        _subcategory = State(initialValue: line?.subcategory)
    }

    private var household: Household? {
        households.first(where: \.isDefault) ?? households.first
    }

    private var parsedAmount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US"))
    }

    private var isValid: Bool {
        (parsedAmount ?? 0) > 0
    }

    private var needsScope: Bool {
        guard let line else { return false }
        return BudgetLineService.needsScopeChoice(line, month: month)
    }

    private var takenTargets: Set<UUID?> {
        Set(
            budgetExpenseLines
                .filter { $0.household == household && $0.category == category && $0.isActive(for: month) }
                .map { $0.subcategory?.id }
        )
    }

    private var availableSubcategories: [Subcategory] {
        category.subcategories
            .sorted { $0.sortOrder < $1.sortOrder }
            .filter { !takenTargets.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Ligne budgétaire") {
                    if line == nil {
                        Picker("Cible", selection: $subcategory) {
                            if !takenTargets.contains(nil) {
                                Text("Globale (toute la catégorie)").tag(Subcategory?.none)
                            }
                            ForEach(availableSubcategories) { sub in
                                Text(sub.name).tag(Optional(sub))
                            }
                        }
                    } else {
                        LabeledContent("Cible", value: line?.subcategory?.name ?? "Budget global")
                    }
                    HStack {
                        TextField("0,00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.title3.weight(.semibold))
                        Text("€ / mois")
                            .foregroundStyle(Color.budgetTextMute)
                    }
                    Picker("Fréquence", selection: $frequency) {
                        ForEach(Frequency.allCases, id: \.self) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if needsScope {
                    Section("Appliquer la modification") {
                        Picker("Portée", selection: $scope) {
                            ForEach(EditScope.allCases, id: \.self) { s in
                                Text(s.label).tag(s)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Color.budgetDanger)
                    }
                }

            }
            .navigationTitle(line == nil ? "Nouvelle ligne" : "Modifier la ligne")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(
                    title: line == nil ? "Ajouter la ligne" : "Enregistrer",
                    enabled: isValid,
                    working: isWorking
                ) { Task { await save() } }
            }
        }
        .tint(.budgetPrimary)
    }

    private var isRemote: Bool {
        PushService.isRemoteBudget(household, session: session)
    }

    private func save() async {
        guard let amount = parsedAmount, amount > 0 else { return }

        if let line {
            BudgetLineService.update(
                line,
                amount: amount,
                frequency: frequency,
                scope: needsScope ? scope : .fromThisMonth,
                month: month,
                context: modelContext
            )
            if isRemote {
                PushService.markForUpload(&line.syncStatus, household: line.household)
            }
        } else {
            let m = Calendar.current.startOfMonth(for: month)
            let new = BudgetExpenseLine(
                category: category,
                subcategory: subcategory,
                month: m,
                endMonth: frequency == .punctual ? m : nil,
                frequency: frequency,
                amount: amount
            )
            new.household = household
            if isRemote {
                PushService.markForUpload(&new.syncStatus, household: household)
            }
            modelContext.insert(new)
            try? modelContext.save()
        }
        PushService.afterLocalChange(session: session, context: modelContext)
        dismiss()
    }
}
