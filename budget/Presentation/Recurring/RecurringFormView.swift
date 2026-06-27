import SwiftUI
import SwiftData

struct RecurringFormView: View {
    private let template: RecurringExpense?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSession.self) private var session

    @Query private var households: [Household]

    @State private var amountText: String
    @State private var label: String
    @State private var dayOfMonth: Int
    @State private var category: Category?
    @State private var subcategory: Subcategory?
    @State private var showDeleteConfirm = false
    @State private var showCategoryPicker = false

    init(template: RecurringExpense? = nil) {
        self.template = template
        _amountText = State(initialValue: template.map {
            NSDecimalNumber(decimal: $0.amount).stringValue.replacingOccurrences(of: ".", with: ",")
        } ?? "")
        _label = State(initialValue: template?.label ?? "")
        _dayOfMonth = State(initialValue: template?.dayOfMonth ?? 1)
        _category = State(initialValue: template?.category)
        _subcategory = State(initialValue: template?.subcategory)
    }

    private var parsedAmount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US"))
    }

    private var household: Household? {
        households.first(where: \.isDefault) ?? households.first
    }

    private var targetHousehold: Household? {
        template?.household ?? household
    }

    private var canManageRecurring: Bool {
        PushService.isRemoteHousehold(targetHousehold, session: session)
    }

    private var isValid: Bool {
        canManageRecurring
            && (parsedAmount ?? 0) > 0
            && !label.trimmingCharacters(in: .whitespaces).isEmpty
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
                        Text("\(AmountFormatter.currencySymbol) / mois")
                            .foregroundStyle(Color.budgetTextMute)
                    }
                }

                Section("Détails") {
                    TextField("Libellé (ex : Loyer)", text: $label)
                    Picker("Jour du mois", selection: $dayOfMonth) {
                        ForEach(1...28, id: \.self) { day in
                            Text("Le \(day)").tag(day)
                        }
                    }
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

                if template != nil {
                    Section {
                        Button("Supprimer le récurrent", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    }
                }
            }
            .navigationTitle(template == nil ? "Nouveau récurrent" : "Modifier le récurrent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(title: template == nil ? "Ajouter le récurrent" : "Enregistrer", enabled: isValid) { save() }
            }
            .onChange(of: category) {
                if subcategory?.category != category {
                    subcategory = nil
                }
            }
            .sheet(isPresented: $showCategoryPicker) {
                CategoryPickerView(category: $category, subcategory: $subcategory)
            }
            .confirmationDialog(
                "Supprimer ce récurrent ? Les dépenses déjà générées sont conservées.",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) { deleteTemplate() }
            }
        }
        .tint(.budgetPrimary)
    }

    private func save() {
        guard canManageRecurring else { return }
        guard let amount = parsedAmount, amount > 0 else { return }
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)

        if let template {
            template.amount = amount
            template.label = trimmedLabel
            template.dayOfMonth = min(max(dayOfMonth, 1), 28)
            template.category = category
            template.subcategory = subcategory
            PushService.markForUpload(&template.syncStatus, household: template.household)
        } else {
            let new = RecurringExpense(
                category: category,
                subcategory: subcategory,
                amount: amount,
                label: trimmedLabel,
                dayOfMonth: dayOfMonth
            )
            new.household = household
            PushService.markForUpload(&new.syncStatus, household: new.household)
            modelContext.insert(new)
        }
        try? modelContext.save()
        PushService.afterLocalChange(session: session, context: modelContext)
        dismiss()
    }

    private func deleteTemplate() {
        guard canManageRecurring else { return }
        guard let template else { return }
        PushService.deleteRecurring(template, session: session, context: modelContext)
        dismiss()
    }
}
