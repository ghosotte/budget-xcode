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

    @State private var amountText: String
    @State private var frequency: Frequency
    @State private var incomeCategory: IncomeCategory?
    @State private var scope = EditScope.fromThisMonth
    @State private var showDeleteConfirm = false
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Revenu prévu") {
                    Picker("Catégorie", selection: $incomeCategory) {
                        Text("Aucune").tag(IncomeCategory?.none)
                        ForEach(incomeCategories) { cat in
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

                if line != nil {
                    Section {
                        Button("Supprimer la ligne", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    }
                }
            }
            .navigationTitle(line == nil ? "Nouveau revenu prévu" : "Modifier le revenu prévu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { Task { await save() } }
                        .disabled(!isValid || isWorking)
                }
            }
            .confirmationDialog(
                "Supprimer cette ligne à partir de \(AppDateFormatter.monthYear(month)) ?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) { Task { await deleteLine() } }
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

    private func deleteLine() async {
        guard let line else { return }

        if isRemote, line.serverId != nil {
            PushService.deleteBudgetIncomeLine(line, viewMonth: month, session: session, context: modelContext)
        } else {
            BudgetLineService.delete(line, month: month, context: modelContext)
        }
        dismiss()
    }
}
