import SwiftUI
import SwiftData

struct ExpenseFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSession.self) private var session

    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var households: [Household]

    private let expense: Expense?
    private let kindSelection: Binding<TransactionFormKind>?

    @State private var amountText: String
    @State private var label: String
    @State private var date: Date
    @State private var category: Category?
    @State private var subcategory: Subcategory?
    @State private var notes: String
    @State private var tagsText: String
    @State private var showCategoryPicker = false

    init(expense: Expense? = nil, kindSelection: Binding<TransactionFormKind>? = nil) {
        self.expense = expense
        self.kindSelection = kindSelection
        _amountText = State(initialValue: expense.map {
            NSDecimalNumber(decimal: $0.amount).stringValue.replacingOccurrences(of: ".", with: ",")
        } ?? "")
        _label = State(initialValue: expense?.label ?? "")
        _date = State(initialValue: expense?.spentAt ?? .now)
        _category = State(initialValue: expense?.category)
        _subcategory = State(initialValue: expense?.subcategory)
        _notes = State(initialValue: expense?.notes ?? "")
        _tagsText = State(initialValue: expense?.tags.joined(separator: ", ") ?? "")
    }

    private var parsedAmount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US"))
    }

    private var isValid: Bool {
        (parsedAmount ?? 0) > 0
    }

    private var categoryLabel: String {
        guard let category else { return NSLocalizedString("Aucune", comment: "") }
        if let subcategory {
            return "\(category.emoji) \(category.displayName) › \(subcategory.displayName)"
        }
        return "\(category.emoji) \(category.displayName)"
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
                    TextField("Libellé (ex : Courses Lidl)", text: $label)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Button {
                        showCategoryPicker = true
                    } label: {
                        HStack {
                            Text("Catégorie")
                                .foregroundStyle(Color.budgetText)
                            Spacer()
                            Text(categoryLabel)
                                .foregroundStyle(category == nil ? Color.budgetTextMute : Color.budgetText)
                                .multilineTextAlignment(.trailing)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.budgetTextFaint)
                        }
                    }
                }

                Section("Notes & tags") {
                    TextField("Notes", text: $notes, axis: .vertical)
                    TextField("Tags (séparés par des virgules)", text: $tagsText)
                }
            }
            .navigationTitle(expense == nil ? "Nouvelle dépense" : "Modifier la dépense")
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
                PrimaryActionButton(title: expense == nil ? "Ajouter la dépense" : "Enregistrer", enabled: isValid) { save() }
            }
            .onChange(of: category) {
                if subcategory?.category != category {
                    subcategory = nil
                }
            }
            .sheet(isPresented: $showCategoryPicker) {
                CategoryPickerView(category: $category, subcategory: $subcategory)
            }
        }
        .tint(.budgetPrimary)
    }

    private func save() {
        guard let amount = parsedAmount, amount > 0 else { return }
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        let finalLabel = trimmedLabel.isEmpty ? (category?.displayName ?? NSLocalizedString("Dépense", comment: "")) : trimmedLabel
        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let finalNotes = notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes

        if let expense {
            expense.category = category
            expense.subcategory = subcategory
            expense.amount = amount
            expense.label = finalLabel
            expense.spentAt = date
            expense.tags = tags
            expense.notes = finalNotes
            expense.updatedAt = .now
            PushService.markForUpload(&expense.syncStatus, household: expense.household)
        } else {
            let new = Expense(
                category: category,
                subcategory: subcategory,
                amount: amount,
                label: finalLabel,
                spentAt: date,
                tags: tags,
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
    ExpenseFormView()
        .modelContainer(for: [
            Household.self, Category.self, Subcategory.self, IncomeCategory.self,
            BudgetExpenseLine.self, BudgetIncome.self, Expense.self,
            IncomeEntry.self, RecurringExpense.self,
        ], inMemory: true)
}
