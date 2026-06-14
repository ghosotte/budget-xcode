import SwiftUI
import SwiftData

struct ExpenseFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSession.self) private var session

    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var households: [Household]

    private let expense: Expense?

    @State private var amountText: String
    @State private var label: String
    @State private var date: Date
    @State private var category: Category?
    @State private var subcategory: Subcategory?
    @State private var status: ExpenseStatus
    @State private var notes: String
    @State private var tagsText: String

    init(expense: Expense? = nil) {
        self.expense = expense
        _amountText = State(initialValue: expense.map {
            NSDecimalNumber(decimal: $0.amount).stringValue.replacingOccurrences(of: ".", with: ",")
        } ?? "")
        _label = State(initialValue: expense?.label ?? "")
        _date = State(initialValue: expense?.spentAt ?? .now)
        _category = State(initialValue: expense?.category)
        _subcategory = State(initialValue: expense?.subcategory)
        _status = State(initialValue: expense?.status ?? .real)
        _notes = State(initialValue: expense?.notes ?? "")
        _tagsText = State(initialValue: expense?.tags.joined(separator: ", ") ?? "")
    }

    private var parsedAmount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US"))
    }

    private var isValid: Bool {
        (parsedAmount ?? 0) > 0
    }

    private var sortedSubcategories: [Subcategory] {
        category?.subcategories.sorted { $0.sortOrder < $1.sortOrder } ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Montant") {
                    HStack {
                        TextField("0,00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.title2.weight(.semibold))
                        Text("€")
                            .foregroundStyle(Color.budgetTextMute)
                    }
                }

                Section("Détails") {
                    TextField("Libellé (ex : Courses Lidl)", text: $label)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Catégorie", selection: $category) {
                        Text("Aucune").tag(Category?.none)
                        ForEach(categories) { cat in
                            Text("\(cat.emoji) \(cat.name)").tag(Optional(cat))
                        }
                    }
                    if !sortedSubcategories.isEmpty {
                        Picker("Sous-catégorie", selection: $subcategory) {
                            Text("Aucune").tag(Subcategory?.none)
                            ForEach(sortedSubcategories) { sub in
                                Text(sub.name).tag(Optional(sub))
                            }
                        }
                    }
                    Picker("Statut", selection: $status) {
                        ForEach(ExpenseStatus.allCases, id: \.self) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
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
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(!isValid)
                }
            }
            .onChange(of: category) {
                if subcategory?.category != category {
                    subcategory = nil
                }
            }
        }
        .tint(.budgetPrimary)
    }

    private func save() {
        guard let amount = parsedAmount, amount > 0 else { return }
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        let finalLabel = trimmedLabel.isEmpty ? (category?.name ?? "Dépense") : trimmedLabel
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
            expense.status = status
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
                status: status,
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
