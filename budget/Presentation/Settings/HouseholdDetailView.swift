import SwiftUI
import SwiftData

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
                LabeledContent("Nom", value: household.name)
                if let serverId = household.serverId {
                    LabeledContent("ID serveur", value: String(serverId))
                }
                LabeledContent("Type", value: household.isAnonymous ? "Local" : "Cloud")
            } header: {
                Text("Foyer")
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
            await loadDetail()
            await loadInvitations()
        }
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
                    firstName: $0.firstName ?? "Sans nom",
                    isMe: $0.isMe,
                    joinedAt: $0.joinedAt
                )
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
                errorMessage = response.error ?? "Échec révocation."
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
