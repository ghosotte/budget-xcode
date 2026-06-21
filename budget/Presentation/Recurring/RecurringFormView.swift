import SwiftUI
import SwiftData

struct RecurringFormView: View {
    private let template: RecurringExpense?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSession.self) private var session

    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var households: [Household]

    @State private var amountText: String
    @State private var label: String
    @State private var dayOfMonth: Int
    @State private var category: Category?
    @State private var subcategory: Subcategory?
    @State private var autoConfirm: Bool
    @State private var showDeleteConfirm = false

    init(template: RecurringExpense? = nil) {
        self.template = template
        _amountText = State(initialValue: template.map {
            NSDecimalNumber(decimal: $0.amount).stringValue.replacingOccurrences(of: ".", with: ",")
        } ?? "")
        _label = State(initialValue: template?.label ?? "")
        _dayOfMonth = State(initialValue: template?.dayOfMonth ?? 1)
        _category = State(initialValue: template?.category)
        _subcategory = State(initialValue: template?.subcategory)
        _autoConfirm = State(initialValue: template?.autoConfirm ?? false)
    }

    private var parsedAmount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US"))
    }

    private var isValid: Bool {
        (parsedAmount ?? 0) > 0 && !label.trimmingCharacters(in: .whitespaces).isEmpty
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
                    Picker("Catégorie", selection: $category) {
                        Text("Aucune").tag(Category?.none)
                        ForEach(categories) { cat in
                            Text("\(cat.emoji) \(cat.displayName)").tag(Optional(cat))
                        }
                    }
                    if !sortedSubcategories.isEmpty {
                        Picker("Sous-catégorie", selection: $subcategory) {
                            Text("Aucune").tag(Subcategory?.none)
                            ForEach(sortedSubcategories) { sub in
                                Text(sub.displayName).tag(Optional(sub))
                            }
                        }
                    }
                }

                Section {
                    Toggle("Confirmation automatique", isOn: $autoConfirm)
                        .tint(.budgetPrimary)
                } footer: {
                    Text("Activée : la dépense est créée comme réelle chaque mois. Désactivée : elle est créée comme prévue et tu la confirmes depuis l'accueil.")
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
        guard let amount = parsedAmount, amount > 0 else { return }
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)

        if let template {
            template.amount = amount
            template.label = trimmedLabel
            template.dayOfMonth = min(max(dayOfMonth, 1), 28)
            template.category = category
            template.subcategory = subcategory
            template.autoConfirm = autoConfirm
            PushService.markForUpload(&template.syncStatus, household: template.household)
        } else {
            let new = RecurringExpense(
                category: category,
                subcategory: subcategory,
                amount: amount,
                label: trimmedLabel,
                dayOfMonth: dayOfMonth,
                autoConfirm: autoConfirm
            )
            new.household = households.first(where: \.isDefault) ?? households.first
            PushService.markForUpload(&new.syncStatus, household: new.household)
            modelContext.insert(new)
        }
        try? modelContext.save()
        RecurringService.generateExpenses(context: modelContext)
        PushService.afterLocalChange(session: session, context: modelContext)
        dismiss()
    }

    private func deleteTemplate() {
        guard let template else { return }
        PushService.deleteRecurring(template, session: session, context: modelContext)
        dismiss()
    }
}
