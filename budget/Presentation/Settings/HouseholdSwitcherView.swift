import SwiftUI
import SwiftData

struct HouseholdSwitcherView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSession.self) private var session

    @Query(sort: \Household.createdAt) private var households: [Household]

    @State private var working: UUID?
    @State private var errorMessage: String?

    private var claimed: [Household] {
        let userId = session.user?.id
        return households.filter { $0.ownerUserId != nil && $0.ownerUserId == userId && !$0.isOrphan }
    }

    private var anonymous: [Household] {
        households.filter { $0.isAnonymous }
    }

    var body: some View {
        NavigationStack {
            List {
                if session.isAuthenticated, !claimed.isEmpty {
                    Section("Foyers cloud") {
                        ForEach(claimed) { row(for: $0, isCloud: true) }
                    }
                }
                if !anonymous.isEmpty {
                    Section(session.isAuthenticated ? "Foyers locaux" : "Foyers") {
                        ForEach(anonymous) { row(for: $0, isCloud: false) }
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(Color.budgetDanger)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.budgetBg)
            .navigationTitle("Changer de foyer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func row(for household: Household, isCloud: Bool) -> some View {
        Button { tap(household) } label: {
            HStack(spacing: 12) {
                Text(String(household.name.prefix(1)).uppercased())
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(household.isDefault ? Color.budgetPrimary : Color.budgetTextFaint))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(household.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.budgetText)
                        if !isCloud {
                            Image(systemName: "iphone")
                                .font(.caption2)
                                .foregroundStyle(Color.budgetTextMute)
                        }
                    }
                    Text("\(household.members.count) membre\(household.members.count > 1 ? "s" : "")")
                        .font(.caption)
                        .foregroundStyle(Color.budgetTextMute)
                }
                Spacer()
                if working == household.id {
                    ProgressView()
                } else if household.isDefault {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.budgetPrimary)
                }
            }
        }
        .disabled(working != nil)
        .listRowBackground(Color.budgetSurface)
    }

    private func tap(_ household: Household) {
        guard !household.isDefault, working == nil else { return }
        errorMessage = nil

        if household.isAnonymous {
            activateLocal(household)
            dismiss()
            return
        }

        guard let serverId = household.serverId else { return }
        working = household.id
        Task {
            do {
                _ = try await session.switchHousehold(serverId: serverId)
                activateLocal(household)
                try await SyncService.syncAll(session: session, context: modelContext)
                working = nil
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                working = nil
            }
        }
    }

    private func activateLocal(_ household: Household) {
        for h in households {
            h.isDefault = (h == household)
        }
        try? modelContext.save()
        Currency.setActive(household.currencyCode)
        AppLocale.setActive(household.locale)
    }
}
