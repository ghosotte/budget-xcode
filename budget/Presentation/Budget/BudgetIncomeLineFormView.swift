import SwiftUI
import SwiftData

struct BudgetIncomeLineFormView: View {
    let month: Date
    private let line: BudgetIncome?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSession.self) private var session
    @Query private var households: [Household]
    @Query(sort: \IncomeCategory.sortOrder) private var incomeCategories: [IncomeCategory]
    @Query private var budgetIncomes: [BudgetIncome]

    @State private var amountText: String
    @State private var frequency: Frequency
    @State private var incomeCategory: IncomeCategory?
    @State private var scope = EditScope.fromThisMonth
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(month: Date, line: BudgetIncome? = nil) {
        self.month = month
        self.line = line
        _amountText = State(initialValue: line.map {
            NSDecimalNumber(decimal: $0.amount).stringValue.replacingOccurrences(of: ".", with: ",")
        } ?? "")
        _frequency = State(initialValue: line?.frequency ?? .monthly)
        _incomeCategory = State(initialValue: line?.incomeCategory)
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

    /// Catégories de revenu déjà budgétées ce mois (hors ligne en cours d'édition).
    /// Le back-end refuse plus d'une ligne par catégorie/période (409).
    private var takenCategoryIDs: Set<UUID> {
        Set(
            budgetIncomes
                .filter { $0.household == household && $0.isActive(for: month) && $0 != line }
                .compactMap { $0.incomeCategory?.id }
        )
    }

    private var availableCategories: [IncomeCategory] {
        incomeCategories.filter { !takenCategoryIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Revenu prévu") {
                    Picker("Catégorie", selection: $incomeCategory) {
                        Text("Aucune").tag(IncomeCategory?.none)
                        ForEach(availableCategories) { cat in
                            Text("\(cat.emoji) \(cat.name)").tag(Optional(cat))
                        }
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
            .navigationTitle(line == nil ? "Nouveau revenu prévu" : "Modifier le revenu prévu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(
                    title: line == nil ? "Ajouter le revenu prévu" : "Enregistrer",
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
        guard let incomeCategory else {
            errorMessage = "Choisis une catégorie de revenu."
            return
        }
        if takenCategoryIDs.contains(incomeCategory.id) {
            errorMessage = "Un revenu prévu existe déjà pour « \(incomeCategory.name) » ce mois-ci."
            return
        }

        if let line {
            line.incomeCategory = incomeCategory
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
            let new = BudgetIncome(
                incomeCategory: incomeCategory,
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
