import SwiftUI
import SwiftData

struct HouseholdsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSession.self) private var session

    @Query(sort: \Household.createdAt) private var households: [Household]

    @State private var showCreate = false
    @State private var newName = ""
    @State private var createAsCloud = true
    @State private var deleteTarget: Household?
    @State private var deleteConfirmText = ""
    @State private var promoteTarget: Household?
    @State private var promoteName = ""
    @State private var working: UUID?
    @State private var errorMessage: String?
    @State private var detailTarget: Household?
    @State private var showJoin = false
    @State private var joinToken = ""
    @State private var joining = false

    private var claimedHouseholds: [Household] {
        let userId = session.user?.id
        return households.filter { $0.ownerUserId != nil && $0.ownerUserId == userId }
    }

    private var anonymousHouseholds: [Household] {
        households.filter { $0.isAnonymous }
    }

    var body: some View {
        List {
            if session.isAuthenticated {
                Section {
                    ForEach(claimedHouseholds) { household in
                        row(for: household, isCloud: true)
                    }
                } header: {
                    Text("Foyers cloud")
                } footer: {
                    Text("Synchronisés avec votre compte. Le foyer actif détermine les données affichées dans l'app.")
                }
            }

            Section {
                ForEach(anonymousHouseholds) { household in
                    row(for: household, isCloud: false)
                }
            } header: {
                Text(session.isAuthenticated ? "Foyers locaux" : "Foyers")
            } footer: {
                if session.isAuthenticated {
                    Text("Données stockées uniquement sur cet appareil. Glissez à gauche pour les mettre dans le cloud.")
                } else {
                    Text("Le foyer actif est utilisé par tous les écrans. Connectez-vous pour synchroniser entre appareils.")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Color.budgetDanger)
                        .listRowBackground(Color.budgetSurface)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.budgetBg)
        .navigationTitle("Foyers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Menu {
                    Button {
                        newName = ""
                        createAsCloud = session.isAuthenticated
                        showCreate = true
                    } label: {
                        Label("Nouveau foyer", systemImage: "plus")
                    }
                    if session.isAuthenticated {
                        Button {
                            joinToken = ""
                            showJoin = true
                        } label: {
                            Label("Rejoindre via invitation", systemImage: "person.badge.plus")
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            createSheet
        }
        .alert("Supprimer ce foyer ?", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil; deleteConfirmText = "" } }
        )) {
            if let target = deleteTarget, target.serverId != nil {
                TextField("Tapez le nom du foyer", text: $deleteConfirmText)
                Button("Annuler", role: .cancel) {}
                Button("Supprimer", role: .destructive) { delete() }
                    .disabled(deleteConfirmText != deleteTarget?.name)
            } else {
                Button("Annuler", role: .cancel) {}
                Button("Supprimer", role: .destructive) { delete() }
            }
        } message: {
            if let target = deleteTarget {
                if target.serverId != nil {
                    Text("Suppression irréversible de « \(target.name) » et de toutes ses données dans le cloud. Tapez le nom du foyer pour confirmer.")
                } else {
                    Text("« \(target.name) » et ses données seront supprimés de cet appareil.")
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { promoteTarget != nil },
            set: { if !$0 { promoteTarget = nil } }
        )) {
            promoteSheet
        }
        .sheet(isPresented: $showJoin) {
            joinSheet
        }
        .navigationDestination(item: $detailTarget) { household in
            HouseholdDetailView(household: household)
        }
    }

    @ViewBuilder
    private var createSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom du foyer", text: $newName)
                }
                if session.isAuthenticated {
                    Section {
                        Toggle("Synchroniser dans le cloud", isOn: $createAsCloud)
                    } footer: {
                        Text(createAsCloud
                            ? "Le foyer sera créé sur votre compte et accessible depuis tous vos appareils."
                            : "Le foyer restera uniquement sur cet appareil.")
                    }
                }
            }
            .navigationTitle("Nouveau foyer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton { showCreate = false }
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(
                    title: "Créer",
                    enabled: !newName.trimmingCharacters(in: .whitespaces).isEmpty
                ) { Task { await create() } }
            }
        }
    }

    @ViewBuilder
    private var joinSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Lien ou code d'invitation", text: $joinToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Collez le lien d'invitation reçu, ou uniquement le code.")
                }
            }
            .navigationTitle("Rejoindre un foyer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton { showJoin = false }
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(
                    title: "Rejoindre",
                    enabled: !extractToken(from: joinToken).isEmpty,
                    working: joining
                ) { Task { await join() } }
            }
        }
    }

    @ViewBuilder
    private var promoteSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom du foyer", text: $promoteName)
                } footer: {
                    Text("Le foyer local et toutes ses données seront copiés dans votre compte cloud.")
                }
            }
            .navigationTitle("Mettre dans le cloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton { promoteTarget = nil }
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(
                    title: "Confirmer",
                    enabled: !promoteName.trimmingCharacters(in: .whitespaces).isEmpty
                ) { Task { await promote() } }
            }
        }
    }

    @ViewBuilder
    private func row(for household: Household, isCloud: Bool) -> some View {
        Button { tap(household) } label: {
            HStack(spacing: 12) {
                Text(String(household.name.prefix(1)).uppercased())
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(household.isDefault ? Color.budgetPrimary : Color.budgetTextFaint))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(household.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(household.isOrphan ? Color.budgetTextMute : Color.budgetText)
                        if !isCloud {
                            Image(systemName: "iphone")
                                .font(.caption2)
                                .foregroundStyle(Color.budgetTextMute)
                        }
                        if household.isOrphan {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.budgetDanger)
                        }
                    }
                    if household.isOrphan {
                        Text("Accès révoqué")
                            .font(.caption)
                            .foregroundStyle(Color.budgetDanger)
                    } else {
                        Text("\(household.members.count) membre\(household.members.count > 1 ? "s" : "")")
                            .font(.caption)
                            .foregroundStyle(Color.budgetTextMute)
                    }
                }

                Spacer()

                if working == household.id {
                    ProgressView()
                } else if household.isDefault {
                    Text("Actif")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.budgetPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.budgetPrimarySoft))
                }
            }
            .padding(.vertical, 2)
        }
        .disabled(working != nil)
        .listRowBackground(Color.budgetSurface)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if households.count > 1 {
                Button(role: .destructive) {
                    deleteTarget = household
                    deleteConfirmText = ""
                } label: {
                    Label("Supprimer", systemImage: "trash")
                }
            }
            if !household.isOrphan {
                Button {
                    detailTarget = household
                } label: {
                    Label("Éditer", systemImage: "pencil")
                }
                .tint(Color.budgetAccent)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !isCloud && session.isAuthenticated {
                Button {
                    promoteTarget = household
                    promoteName = household.name
                } label: {
                    Label("Cloud", systemImage: "icloud.and.arrow.up")
                }
                .tint(Color.budgetPrimary)
            }
        }
    }

    private func tap(_ household: Household) {
        guard !household.isDefault, working == nil else { return }
        errorMessage = nil

        if household.isOrphan {
            errorMessage = NSLocalizedString("Vous n'avez plus accès à ce foyer. Supprimez-le de cet appareil.", comment: "")
            return
        }

        if household.isAnonymous {
            activateLocal(household)
            return
        }

        guard let serverId = household.serverId else { return }
        working = household.id
        Task {
            do {
                _ = try await session.switchHousehold(serverId: serverId)
                activateLocal(household)
                try await SyncService.syncAll(session: session, context: modelContext)
            } catch {
                errorMessage = error.localizedDescription
            }
            working = nil
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

    private func create() async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        errorMessage = nil

        // Défauts dérivés du système ; le foyer pourra être édité ensuite.
        let currency = Currency.systemDefault()
        let locale = AppLocale.systemDefault()

        if createAsCloud && session.isAuthenticated {
            do {
                let server = try await session.createCloudHousehold(name: name, currency: currency, locale: locale)
                guard let userId = session.user?.id else { return }
                let household = Household(
                    serverId: server.id,
                    ownerUserId: userId,
                    isAnonymous: false,
                    name: server.name,
                    currencyCode: server.currency,
                    locale: server.locale
                )
                household.members.append(HouseholdMember(displayName: "Moi", isMe: true))
                modelContext.insert(household)
                try? modelContext.save()
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        } else {
            let household = Household(isAnonymous: true, name: name, currencyCode: currency, locale: locale)
            household.members.append(HouseholdMember(displayName: "Moi", isMe: true))
            modelContext.insert(household)
            try? modelContext.save()
        }

        showCreate = false
        newName = ""
    }

    private func delete() {
        guard let target = deleteTarget else { return }
        let wasActive = target.isDefault
        deleteTarget = nil
        deleteConfirmText = ""
        errorMessage = nil

        if let serverId = target.serverId, !target.isOrphan {
            working = target.id
            Task {
                func finalizeLocalDeletion() async {
                    modelContext.delete(target)
                    try? modelContext.save()
                    if wasActive, let next = households.first(where: { $0.persistentModelID != target.persistentModelID }) {
                        activateLocal(next)
                        if let nextServerId = next.serverId {
                            _ = try? await session.switchHousehold(serverId: nextServerId)
                            try? await SyncService.syncAll(session: session, context: modelContext)
                        }
                    }
                }
                do {
                    try await session.deleteCloudHousehold(serverId: serverId)
                    await finalizeLocalDeletion()
                } catch is URLError {
                    PendingHouseholdOpStore.enqueueDelete(serverId: serverId)
                    await finalizeLocalDeletion()
                    errorMessage = NSLocalizedString("Hors ligne. Suppression enregistrée, sera synchronisée plus tard.", comment: "")
                } catch {
                    errorMessage = error.localizedDescription
                }
                working = nil
            }
        } else {
            modelContext.delete(target)
            try? modelContext.save()
            if wasActive, let next = households.first {
                activateLocal(next)
            }
        }
    }

    private func extractToken(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let last = url.pathComponents.last, !last.isEmpty, last != "/" {
            return last
        }
        return trimmed
    }

    private func join() async {
        let token = extractToken(from: joinToken)
        guard !token.isEmpty else { return }
        joining = true
        errorMessage = nil
        do {
            let server = try await session.acceptInvitation(token: token)
            guard let userId = session.user?.id else { return }
            if !households.contains(where: { $0.serverId == server.id && $0.ownerUserId == userId }) {
                let household = Household(
                    serverId: server.id,
                    ownerUserId: userId,
                    isAnonymous: false,
                    name: server.name
                )
                household.members.append(HouseholdMember(displayName: "Moi", isMe: true))
                modelContext.insert(household)
            }
            if let local = households.first(where: { $0.serverId == server.id && $0.ownerUserId == userId }) {
                for h in households { h.isDefault = (h == local) }
            }
            try? modelContext.save()
            try await SyncService.syncAll(session: session, context: modelContext)
            showJoin = false
            joinToken = ""
        } catch {
            errorMessage = error.localizedDescription
        }
        joining = false
    }

    private func promote() async {
        guard let target = promoteTarget else { return }
        let name = promoteName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        promoteTarget = nil
        errorMessage = nil
        working = target.id

        do {
            let server = try await HouseholdMigrationService.promoteAnonymousToCloud(
                target, name: name, session: session, context: modelContext
            )
            if target.isDefault {
                _ = try await session.switchHousehold(serverId: server.id)
                try await SyncService.syncAll(session: session, context: modelContext)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        working = nil
    }
}
