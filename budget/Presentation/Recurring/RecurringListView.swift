import SwiftUI
import SwiftData

struct RecurringListView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            RecurringListContent()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer") { dismiss() }
                    }
                }
        }
        .tint(.budgetPrimary)
    }
}

struct RecurringListContent: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSession.self) private var session

    @Query private var households: [Household]
    @Query(sort: \RecurringExpense.dayOfMonth) private var templates: [RecurringExpense]

    @State private var formTarget: RecurringFormTarget?

    private var household: Household? {
        households.first(where: \.isDefault) ?? households.first
    }

    private var activeTemplates: [RecurringExpense] {
        templates.filter { $0.household == household && $0.isActive }
    }

    private var inactiveTemplates: [RecurringExpense] {
        templates.filter { $0.household == household && !$0.isActive }
    }

    var body: some View {
        Group {
            if activeTemplates.isEmpty && inactiveTemplates.isEmpty {
                emptyState
            } else {
                List {
                    if !activeTemplates.isEmpty {
                        Section("Actifs") {
                            ForEach(activeTemplates) { template in
                                row(template)
                            }
                        }
                    }
                    if !inactiveTemplates.isEmpty {
                        Section("Inactifs") {
                            ForEach(inactiveTemplates) { template in
                                row(template)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.budgetBg)
        .navigationTitle("Dépenses récurrentes")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await MonthSyncService.refreshRecurring(session: session, context: modelContext)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { formTarget = .new } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $formTarget) { target in
            RecurringFormView(template: target.template)
        }
    }

    private func row(_ template: RecurringExpense) -> some View {
        Button { formTarget = .edit(template) } label: {
            HStack(spacing: 12) {
                Text(template.category?.emoji ?? "🔁")
                    .font(.system(size: 18))
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.budgetSurfaceMute))

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.budgetText)
                        .lineLimit(1)
                    Text("Le \(template.dayOfMonth) du mois\(template.autoConfirm ? " · auto" : "")")
                        .font(.caption)
                        .foregroundStyle(Color.budgetTextMute)
                }

                Spacer()

                Text(AmountFormatter.full(template.amount))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.budgetText)

                Toggle("", isOn: Binding(
                    get: { template.isActive },
                    set: { newValue in
                        template.isActive = newValue
                        PushService.markForUpload(&template.syncStatus, household: template.household)
                        try? modelContext.save()
                        PushService.afterLocalChange(session: session, context: modelContext)
                    }
                ))
                .labelsHidden()
                .tint(.budgetPrimary)
            }
        }
        .listRowBackground(Color.budgetSurface)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                PushService.deleteRecurring(template, session: session, context: modelContext)
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("🔁")
                .font(.system(size: 40))
            Text("Aucune dépense récurrente.\nLoyer, abonnements, assurances…")
                .font(.subheadline)
                .foregroundStyle(Color.budgetTextMute)
                .multilineTextAlignment(.center)
            Button { formTarget = .new } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Ajouter la première")
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

enum RecurringFormTarget: Identifiable {
    case new
    case edit(RecurringExpense)

    var id: String {
        switch self {
        case .new:                return "new"
        case .edit(let template): return template.id.uuidString
        }
    }

    var template: RecurringExpense? {
        if case .edit(let template) = self { return template }
        return nil
    }
}
