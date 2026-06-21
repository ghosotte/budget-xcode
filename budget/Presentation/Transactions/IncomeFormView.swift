import SwiftUI
import SwiftData

struct IncomeFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSession.self) private var session

    @Query(sort: \IncomeCategory.sortOrder) private var incomeCategories: [IncomeCategory]
    @Query private var households: [Household]

    private let income: IncomeEntry?
    private let kindSelection: Binding<TransactionFormKind>?

    @State private var amountText: String
    @State private var label: String
    @State private var date: Date
    @State private var incomeCategory: IncomeCategory?
    @State private var status: ExpenseStatus
    @State private var notes: String
    @State private var showCategoryPicker = false

    init(income: IncomeEntry? = nil, kindSelection: Binding<TransactionFormKind>? = nil) {
        self.income = income
        self.kindSelection = kindSelection
        _amountText = State(initialValue: income.map {
            NSDecimalNumber(decimal: $0.amount).stringValue.replacingOccurrences(of: ".", with: ",")
        } ?? "")
        _label = State(initialValue: income?.label ?? "")
        _date = State(initialValue: income?.receivedAt ?? .now)
        _incomeCategory = State(initialValue: income?.incomeCategory)
        _status = State(initialValue: income?.status ?? .real)
        _notes = State(initialValue: income?.notes ?? "")
    }

    private var parsedAmount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US"))
    }

    private var isValid: Bool {
        (parsedAmount ?? 0) > 0
    }

    private var categoryLabel: String {
        guard let incomeCategory else { return NSLocalizedString("Aucune", comment: "") }
        return "\(incomeCategory.emoji) \(incomeCategory.displayName)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Montant") {
                    HStack {
                        TextField("0,00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.title2.weight(.semibold))
                        Text(AmountFormatter.currencySymbol)
                            .foregroundStyle(Color.budgetTextMute)
                    }
                }

                Section("Détails") {
                    TextField("Libellé (ex : Salaire)", text: $label)
                    DatePicker("Date de réception", selection: $date, displayedComponents: .date)
                    Button {
                        showCategoryPicker = true
                    } label: {
                        HStack {
                            Text("Catégorie")
                                .foregroundStyle(Color.budgetText)
                            Spacer()
                            Text(categoryLabel)
                                .foregroundStyle(incomeCategory == nil ? Color.budgetTextMute : Color.budgetText)
                                .multilineTextAlignment(.trailing)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.budgetTextFaint)
                        }
                    }
                    Picker("Statut", selection: $status) {
                        ForEach(ExpenseStatus.allCases, id: \.self) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle(income == nil ? "Nouveau revenu" : "Modifier le revenu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton { dismiss() }
                }
                if let kindSelection {
                    ToolbarItem(placement: .principal) {
                        Picker("Type", selection: kindSelection) {
                            ForEach(TransactionFormKind.allCases) { k in
                                Text(k.label).tag(k)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(title: income == nil ? "Ajouter le revenu" : "Enregistrer", enabled: isValid) { save() }
            }
            .sheet(isPresented: $showCategoryPicker) {
                IncomeCategoryPickerView(incomeCategory: $incomeCategory)
            }
        }
        .tint(.budgetPrimary)
    }

    private func save() {
        guard let amount = parsedAmount, amount > 0 else { return }
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        let finalLabel = trimmedLabel.isEmpty ? (incomeCategory?.displayName ?? NSLocalizedString("Revenu", comment: "")) : trimmedLabel
        let finalNotes = notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes

        if let income {
            income.incomeCategory = incomeCategory
            income.amount = amount
            income.label = finalLabel
            income.receivedAt = date
            income.status = status
            income.notes = finalNotes
            income.updatedAt = .now
            PushService.markForUpload(&income.syncStatus, household: income.household)
        } else {
            let new = IncomeEntry(
                incomeCategory: incomeCategory,
                amount: amount,
                label: finalLabel,
                receivedAt: date,
                status: status,
                notes: finalNotes
            )
            new.household = households.first(where: \.isDefault) ?? households.first
            PushService.markForUpload(&new.syncStatus, household: new.household)
            modelContext.insert(new)
        }
        try? modelContext.save()
        PushService.afterLocalChange(session: session, context: modelContext)
        dismiss()
    }
}

#Preview {
    IncomeFormView()
        .modelContainer(for: [
            Household.self, Category.self, Subcategory.self, IncomeCategory.self,
            BudgetExpenseLine.self, BudgetIncome.self, Expense.self,
            IncomeEntry.self, RecurringExpense.self,
        ], inMemory: true)
}
