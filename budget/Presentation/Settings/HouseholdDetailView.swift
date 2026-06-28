import SwiftUI
import SwiftData
import BudgetKit

struct HouseholdDetailView: View {
    let household: Household

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSession.self) private var session

    @State private var members: [Member] = []
    @State private var pendingInvitations: [PendingInvitation] = []
    @State private var lastInvitation: PendingInvitation?
    @State private var isLoading = false
    @State private var isInviting = false
    @State private var revokingId: Int?
    @State private var errorMessage: String?
    @State private var editedName = ""
    @State private var savingName = false
    @State private var currencyCode = Currency.default
    @State private var savingCurrency = false
    @State private var localeCode = AppLocale.default
    @State private var savingLocale = false

    struct Member: Identifiable {
        let id: Int
        let firstName: String
        let isMe: Bool
        let joinedAt: String
    }

    struct PendingInvitation: Identifiable, Equatable {
        let id: Int
        let token: String
        let url: String
        let expiresAt: String?
        let createdAt: String
    }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Nom", text: $editedName)
                        .submitLabel(.done)
                        .onSubmit { Task { await saveName() } }
                    if savingName { ProgressView() }
                }
                LabeledContent("Type", value: household.isAnonymous ? "Local" : "Cloud")
            } header: {
                Text("Foyer")
            }

            Section {
                Picker("Langue", selection: $localeCode) {
                    ForEach(AppLocale.supported, id: \.self) { code in
                        Text(AppLocale.label(for: code)).tag(code)
                    }
                }
                .disabled(savingLocale)
                .onChange(of: localeCode) { _, newValue in
                    Task { await saveLocale(newValue) }
                }
            } header: {
                Text("Langue")
            }

            Section {
                Picker("Devise", selection: $currencyCode) {
                    ForEach(Currency.supported, id: \.self) { code in
                        Text(Currency.label(for: code)).tag(code)
                    }
                }
                .disabled(savingCurrency)
                .onChange(of: currencyCode) { _, newValue in
                    Task { await saveCurrency(newValue) }
                }
            } header: {
                Text("Devise")
            }

            if !household.isAnonymous {
                Section {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Chargement...")
                                .foregroundStyle(Color.budgetTextMute)
                        }
                    } else if members.isEmpty {
                        Text("Aucun membre")
                            .foregroundStyle(Color.budgetTextMute)
                    } else {
                        ForEach(members) { member in
                            HStack {
                                Text(String((member.firstName.first ?? "?")).uppercased())
                                    .font(.system(size: 14, weight: .semibold, design: .serif))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(Color.budgetPrimary))
                                VStack(alignment: .leading) {
                                    Text(member.firstName)
                                        .font(.subheadline.weight(.semibold))
                                    Text("Membre depuis \(member.joinedAt)")
                                        .font(.caption)
                                        .foregroundStyle(Color.budgetTextMute)
                                }
                                if member.isMe {
                                    Spacer()
                                    Text("Vous")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.budgetPrimary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Membres")
                }

                Section {
                    Button {
                        Task { await invite() }
                    } label: {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.plus")
                            Text("Inviter quelqu'un")
                            Spacer()
                            if isInviting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isInviting)

                    if let invitation = lastInvitation {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Nouveau lien d'invitation")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.budgetTextMute)
                            Text(invitation.url)
                                .font(.footnote)
                                .foregroundStyle(Color.budgetText)
                                .textSelection(.enabled)
                            if let expires = invitation.expiresAt {
                                Text("Expire le \(expires)")
                                    .font(.caption2)
                                    .foregroundStyle(Color.budgetTextMute)
                            }
                            ShareLink(item: invitation.url) {
                                Label("Partager", systemImage: "square.and.arrow.up")
                                    .font(.footnote.weight(.semibold))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Invitations")
                }

                if !pendingInvitations.isEmpty {
                    Section {
                        ForEach(pendingInvitations) { inv in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(inv.url)
                                    .font(.footnote)
                                    .foregroundStyle(Color.budgetText)
                                    .textSelection(.enabled)
                                HStack(spacing: 8) {
                                    if let expires = inv.expiresAt {
                                        Text("Expire le \(expires)")
                                            .font(.caption2)
                                            .foregroundStyle(Color.budgetTextMute)
                                    }
                                    Spacer()
                                    if revokingId == inv.id {
                                        ProgressView()
                                    } else {
                                        Button(role: .destructive) {
                                            Task { await revoke(inv) }
                                        } label: {
                                            Text("Révoquer")
                                                .font(.caption.weight(.semibold))
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("En attente")
                    }
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
        .navigationTitle(household.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            editedName = household.name
            currencyCode = household.currencyCode
            localeCode = household.locale
            await loadDetail()
            await loadInvitations()
        }
    }

    private func saveName() async {
        let name = editedName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != household.name else {
            editedName = household.name  // reset trim/empty
            return
        }
        savingName = true
        errorMessage = nil
        if let serverId = household.serverId {
            do {
                try await session.renameCloudHousehold(serverId: serverId, name: name)
                household.name = name
                try? modelContext.save()
            } catch is URLError {
                PendingHouseholdOpStore.enqueueRename(serverId: serverId, name: name)
                household.name = name
                try? modelContext.save()
                errorMessage = NSLocalizedString("Hors ligne. Renommage enregistré, sera synchronisé plus tard.", comment: "")
            } catch {
                errorMessage = error.localizedDescription
                editedName = household.name
            }
        } else {
            household.name = name
            try? modelContext.save()
        }
        savingName = false
    }

    private func saveLocale(_ code: String) async {
        guard code != household.locale else { return }
        savingLocale = true
        errorMessage = nil
        let previous = household.locale
        do {
            if !household.isAnonymous, let serverId = household.serverId {
                try await session.setLocaleCloud(serverId: serverId, locale: code)
            }
            household.locale = code
            try? modelContext.save()
            // Toujours appliquer : l'utilisateur change la langue depuis l'UI, on bascule
            // l'app immédiatement (le gate `isDefault` empêchait le switch sur foyer local).
            AppLocale.setActive(code)
        } catch {
            errorMessage = error.localizedDescription
            localeCode = previous  // revert picker
        }
        savingLocale = false
    }

    private func saveCurrency(_ code: String) async {
        guard code != household.currencyCode else { return }
        savingCurrency = true
        errorMessage = nil
        let previous = household.currencyCode
        do {
            if !household.isAnonymous, let serverId = household.serverId {
                try await session.setCurrencyCloud(serverId: serverId, currency: code)
            }
            household.currencyCode = code
            try? modelContext.save()
            if household.isDefault { Currency.setActive(code) }
        } catch {
            errorMessage = error.localizedDescription
            currencyCode = previous  // revert picker
        }
        savingCurrency = false
    }

    private func loadDetail() async {
        guard let serverId = household.serverId, !household.isAnonymous, !household.isOrphan else { return }
        isLoading = true
        errorMessage = nil
        do {
            struct DetailResponse: Decodable {
                struct Inner: Decodable {
                    struct MemberDTO: Decodable {
                        let userId: Int
                        let firstName: String?
                        let isMe: Bool
                        let joinedAt: String

                        enum CodingKeys: String, CodingKey {
                            case isMe = "is_me"
                            case userId = "user_id"
                            case firstName = "first_name"
                            case joinedAt = "joined_at"
                        }
                    }
                    let id: Int
                    let name: String
                    let currency: String?
                    let locale: String?
                    let members: [MemberDTO]
                }
                let success: Bool
                let household: Inner
            }
            let response: DetailResponse = try await APIClient.shared.send(
                DetailResponse.self,
                method: "GET",
                path: "/budget/households/\(serverId)"
            )
            members = response.household.members.map {
                Member(
                    id: $0.userId,
                    firstName: $0.firstName ?? NSLocalizedString("Sans nom", comment: ""),
                    isMe: $0.isMe,
                    joinedAt: $0.joinedAt
                )
            }
            if let serverCurrency = response.household.currency {
                household.currencyCode = serverCurrency
                try? modelContext.save()
                if currencyCode != serverCurrency { currencyCode = serverCurrency }
                if household.isDefault { Currency.setActive(serverCurrency) }
            }
            if let serverLocale = response.household.locale {
                household.locale = serverLocale
                try? modelContext.save()
                if localeCode != serverLocale { localeCode = serverLocale }
                if household.isDefault { AppLocale.setActive(serverLocale) }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private struct InvitationDTO: Decodable {
        let id: Int
        let token: String
        let inviteUrl: String
        let expiresAt: String?
        let createdAt: String

        enum CodingKeys: String, CodingKey {
            case id, token
            case inviteUrl = "invite_url"
            case expiresAt = "expires_at"
            case createdAt = "created_at"
        }

        func asPending() -> PendingInvitation {
            PendingInvitation(
                id: id, token: token, url: inviteUrl,
                expiresAt: expiresAt, createdAt: createdAt
            )
        }
    }

    private func loadInvitations() async {
        guard household.serverId != nil, !household.isOrphan else { return }
        do {
            struct ListResponse: Decodable {
                let success: Bool
                let invitations: [InvitationDTO]
            }
            let response: ListResponse = try await APIClient.shared.send(
                ListResponse.self,
                method: "GET",
                path: "/budget/household/invitations"
            )
            pendingInvitations = response.invitations.map { $0.asPending() }
        } catch {
            // silent: section just stays empty
        }
    }

    private func invite() async {
        guard household.serverId != nil else { return }
        isInviting = true
        errorMessage = nil
        do {
            struct InviteResponse: Decodable {
                let success: Bool
                let invitation: InvitationDTO
            }
            let response: InviteResponse = try await APIClient.shared.send(
                InviteResponse.self,
                method: "POST",
                path: "/budget/household/invite"
            )
            let pending = response.invitation.asPending()
            lastInvitation = pending
            pendingInvitations.insert(pending, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
        isInviting = false
    }

    private func revoke(_ invitation: PendingInvitation) async {
        revokingId = invitation.id
        errorMessage = nil
        do {
            struct RevokeResponse: Decodable {
                let success: Bool
                let error: String?
            }
            let response: RevokeResponse = try await APIClient.shared.send(
                RevokeResponse.self,
                method: "POST",
                path: "/budget/household/invitations/\(invitation.id)/revoke"
            )
            guard response.success else {
                errorMessage = response.error ?? NSLocalizedString("Échec révocation.", comment: "")
                revokingId = nil
                return
            }
            pendingInvitations.removeAll { $0.id == invitation.id }
            if lastInvitation?.id == invitation.id {
                lastInvitation = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        revokingId = nil
    }
}

extension HouseholdDetailView.Member: Equatable {}
