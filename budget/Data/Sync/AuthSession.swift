import Foundation
import Observation
import SwiftData

struct AuthUser: Codable, Equatable {
    let id: Int
    let email: String
    let firstName: String?

    enum CodingKeys: String, CodingKey {
        case id, email
        case firstName = "first_name"
    }
}

struct ServerHousehold: Codable, Equatable {
    let id: Int
    let name: String
}

@Observable
@MainActor
final class AuthSession {
    private static let userKey = "auth.user"
    private static let householdKey = "auth.household"

    private(set) var user: AuthUser?
    private(set) var currentHousehold: ServerHousehold?
    private(set) var serverHouseholds: [ServerHousehold] = []
    var justRegistered: Bool = false

    var isAuthenticated: Bool { user != nil && APIClient.shared.hasTokens }

    private static let tokenSchemaKey = "auth.tokenSchema"
    private static let currentTokenSchema = 2  // bump when backend invalidates tokens

    init() {
        migrateTokensIfNeeded()

        if let data = UserDefaults.standard.data(forKey: Self.userKey) {
            user = try? JSONDecoder().decode(AuthUser.self, from: data)
        }
        if let data = UserDefaults.standard.data(forKey: Self.householdKey) {
            currentHousehold = try? JSONDecoder().decode(ServerHousehold.self, from: data)
        }
        if !APIClient.shared.hasTokens {
            user = nil
            currentHousehold = nil
        }
    }

    private func migrateTokensIfNeeded() {
        // Fresh installation_id implies app was reinstalled (UserDefaults wiped).
        // Keychain may still hold a stale App Attest keyId bound server-side to the old
        // installation_id — purge it so ensureAttested generates a fresh one.
        let installation = APIConfig.ensureInstallationId()
        if installation.isFresh {
            APIClient.shared.clearTokens()
            AppAttestClient.shared.reset()
            UserDefaults.standard.removeObject(forKey: Self.userKey)
            UserDefaults.standard.removeObject(forKey: Self.householdKey)
        }

        let stored = UserDefaults.standard.integer(forKey: Self.tokenSchemaKey)
        if stored < Self.currentTokenSchema {
            APIClient.shared.clearTokens()
            AppAttestClient.shared.reset()
            UserDefaults.standard.removeObject(forKey: Self.userKey)
            UserDefaults.standard.removeObject(forKey: Self.householdKey)
            UserDefaults.standard.set(Self.currentTokenSchema, forKey: Self.tokenSchemaKey)
        }
    }

    private struct AuthResponse: Decodable {
        let success: Bool
        let error: String?
        let accessToken: String?
        let refreshToken: String?
        let user: AuthUser?
        let household: ServerHousehold?
        let isNewUser: Bool?

        enum CodingKeys: String, CodingKey {
            case success, error, user, household
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case isNewUser = "is_new_user"
        }
    }

    // MARK: — Actions

    func login(email: String, password: String) async throws {
        let response: AuthResponse = try await APIClient.shared.send(
            AuthResponse.self,
            method: "POST",
            path: "/budget/auth/login",
            body: ["email": email, "password": password],
            authenticated: false,
            assertion: false
        )
        try apply(response)
    }

    func register(email: String, password: String, firstName: String) async throws {
        let response: AuthResponse = try await APIClient.shared.send(
            AuthResponse.self,
            method: "POST",
            path: "/budget/auth/register",
            body: ["email": email, "password": password, "first_name": firstName],
            authenticated: false,
            assertion: false
        )
        try apply(response)
    }

    func loginWithGoogle(idToken: String) async throws {
        let response: AuthResponse = try await APIClient.shared.send(
            AuthResponse.self,
            method: "POST",
            path: "/budget/auth/google",
            body: ["id_token": idToken],
            authenticated: false,
            assertion: false
        )
        try apply(response)
    }

    func loginWithApple(identityToken: String, firstName: String?) async throws {
        var body = ["identity_token": identityToken]
        if let firstName, !firstName.isEmpty {
            body["first_name"] = firstName
        }
        let response: AuthResponse = try await APIClient.shared.send(
            AuthResponse.self,
            method: "POST",
            path: "/budget/auth/apple",
            body: body,
            authenticated: false,
            assertion: false
        )
        try apply(response)
    }

    func logout(context: ModelContext) async {
        struct LogoutResponse: Decodable { let success: Bool }
        _ = try? await APIClient.shared.send(
            LogoutResponse.self,
            method: "POST",
            path: "/budget/auth/logout",
            assertion: false
        )
        let previousUserId = user?.id
        APIClient.shared.clearTokens()
        user = nil
        currentHousehold = nil
        UserDefaults.standard.removeObject(forKey: Self.userKey)
        UserDefaults.standard.removeObject(forKey: Self.householdKey)
        PendingDeleteStore.clear()
        PendingHouseholdOpStore.clear()

        if let userId = previousUserId {
            purgeOwnedHouseholds(userId: userId, context: context)
        }
        ensureAnonymousHousehold(context: context)
    }

    private func purgeOwnedHouseholds(userId: Int, context: ModelContext) {
        let households = (try? context.fetch(FetchDescriptor<Household>())) ?? []
        for household in households where household.ownerUserId == userId {
            // Delete children explicitly before parent so @Query observers update incrementally
            // and don't try to read attributes on detached cascade-deleted entities.
            for e in household.expenses { context.delete(e) }
            for i in household.incomeEntries { context.delete(i) }
            for l in household.budgetExpenseLines { context.delete(l) }
            for l in household.budgetIncomes { context.delete(l) }
            for r in household.recurringExpenses { context.delete(r) }
            for m in household.members { context.delete(m) }
            context.safeSave("AuthSession")
            context.delete(household)
            context.safeSave("AuthSession")
        }
    }

    private func ensureAnonymousHousehold(context: ModelContext) {
        let households = (try? context.fetch(FetchDescriptor<Household>())) ?? []
        if households.contains(where: \.isDefault) {
            return
        }
        if let first = households.first {
            first.isDefault = true
            context.safeSave("AuthSession")
            return
        }
        let household = Household(isAnonymous: true, name: SeedService.defaultHouseholdName, isDefault: true)
        household.members.append(HouseholdMember(displayName: "Moi", isMe: true))
        context.insert(household)
        try? context.save()
    }

    func appendServerHousehold(_ household: ServerHousehold) {
        guard !serverHouseholds.contains(where: { $0.id == household.id }) else { return }
        serverHouseholds.append(household)
    }

    func refreshHouseholds() async throws {
        struct HouseholdsResponse: Decodable {
            struct Item: Decodable {
                let id: Int
                let name: String
                let memberCount: Int?

                enum CodingKeys: String, CodingKey {
                    case id, name
                    case memberCount = "member_count"
                }
            }

            let success: Bool
            let currentHouseholdId: Int?
            let households: [Item]

            enum CodingKeys: String, CodingKey {
                case success, households
                case currentHouseholdId = "current_household_id"
            }
        }

        let response: HouseholdsResponse = try await APIClient.shared.send(
            HouseholdsResponse.self,
            method: "GET",
            path: "/budget/households"
        )
        guard response.success else { throw APIError.invalidResponse }
        serverHouseholds = response.households.map {
            ServerHousehold(id: $0.id, name: $0.name)
        }
        if let currentId = response.currentHouseholdId,
           let match = serverHouseholds.first(where: { $0.id == currentId }) {
            currentHousehold = match
            UserDefaults.standard.set(try? JSONEncoder().encode(match), forKey: Self.householdKey)
        }
    }

    func createCloudHousehold(name: String) async throws -> ServerHousehold {
        struct CreateResponse: Decodable {
            let success: Bool
            let error: String?
            let household: ServerHousehold?
        }
        let response: CreateResponse = try await APIClient.shared.send(
            CreateResponse.self,
            method: "POST",
            path: "/budget/households",
            body: ["name": name]
        )
        guard response.success, let household = response.household else {
            throw APIError.http(400, response.error ?? "Création foyer refusée.")
        }
        serverHouseholds.append(household)
        return household
    }

    func renameCloudHousehold(serverId: Int, name: String) async throws {
        struct RenameResponse: Decodable {
            let success: Bool
            let error: String?
            let household: ServerHousehold?
        }
        let response: RenameResponse = try await APIClient.shared.send(
            RenameResponse.self,
            method: "PATCH",
            path: "/budget/households/\(serverId)",
            body: ["name": name]
        )
        guard response.success else {
            throw APIError.http(400, response.error ?? "Renommage refusé.")
        }
        if let idx = serverHouseholds.firstIndex(where: { $0.id == serverId }),
           let updated = response.household {
            serverHouseholds[idx] = updated
            if currentHousehold?.id == serverId {
                currentHousehold = updated
                UserDefaults.standard.set(try? JSONEncoder().encode(updated), forKey: Self.householdKey)
            }
        }
    }

    func deleteCloudHousehold(serverId: Int) async throws {
        struct DeleteResponse: Decodable {
            let success: Bool
            let error: String?
            let fullyDeleted: Bool?

            enum CodingKeys: String, CodingKey {
                case success, error
                case fullyDeleted = "fully_deleted"
            }
        }
        let response: DeleteResponse = try await APIClient.shared.send(
            DeleteResponse.self,
            method: "DELETE",
            path: "/budget/households/\(serverId)",
            assertion: true
        )
        guard response.success else {
            throw APIError.http(400, response.error ?? "Suppression refusée.")
        }
        serverHouseholds.removeAll { $0.id == serverId }
        if currentHousehold?.id == serverId {
            currentHousehold = nil
            UserDefaults.standard.removeObject(forKey: Self.householdKey)
        }
    }

    func acceptInvitation(token: String) async throws -> ServerHousehold {
        struct AcceptResponse: Decodable {
            let success: Bool
            let error: String?
            let accessToken: String?
            let refreshToken: String?
            let household: ServerHousehold?

            enum CodingKeys: String, CodingKey {
                case success, error, household
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
            }
        }
        let response: AcceptResponse = try await APIClient.shared.send(
            AcceptResponse.self,
            method: "POST",
            path: "/budget/household/invite/accept",
            body: ["token": token],
            assertion: true
        )
        guard response.success,
              let access = response.accessToken,
              let refresh = response.refreshToken,
              let household = response.household else {
            throw APIError.http(400, response.error ?? "Invitation refusée.")
        }
        APIClient.shared.storeTokens(access: access, refresh: refresh)
        currentHousehold = household
        UserDefaults.standard.set(try? JSONEncoder().encode(household), forKey: Self.householdKey)
        if !serverHouseholds.contains(where: { $0.id == household.id }) {
            serverHouseholds.append(household)
        }
        return household
    }

    func switchHousehold(serverId: Int) async throws -> ServerHousehold {
        struct SwitchResponse: Decodable {
            let success: Bool
            let error: String?
            let accessToken: String?
            let refreshToken: String?
            let household: ServerHousehold?

            enum CodingKeys: String, CodingKey {
                case success, error, household
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
            }
        }

        let response: SwitchResponse = try await APIClient.shared.send(
            SwitchResponse.self,
            method: "POST",
            path: "/budget/auth/switch-household",
            body: ["household_id": serverId],
            assertion: true
        )
        guard response.success,
              let access = response.accessToken,
              let refresh = response.refreshToken,
              let household = response.household else {
            throw APIError.http(400, response.error ?? "Switch foyer refusé.")
        }
        APIClient.shared.storeTokens(access: access, refresh: refresh)
        currentHousehold = household
        UserDefaults.standard.set(try? JSONEncoder().encode(household), forKey: Self.householdKey)
        return household
    }

    func refreshMe() async throws {
        struct MeResponse: Decodable {
            let success: Bool
            let user: AuthUser?
            let currentHousehold: ServerHousehold?

            enum CodingKeys: String, CodingKey {
                case success, user
                case currentHousehold = "current_household"
            }
        }

        let response: MeResponse = try await APIClient.shared.send(
            MeResponse.self,
            method: "GET",
            path: "/budget/auth/me"
        )
        guard response.success, let me = response.user else { throw APIError.notAuthenticated }
        persist(user: me, household: response.currentHousehold)
    }

    // MARK: — Privé

    private func apply(_ response: AuthResponse) throws {
        guard response.success,
              let access = response.accessToken,
              let refresh = response.refreshToken,
              let user = response.user else {
            throw APIError.http(401, response.error ?? "Authentification refusée.")
        }
        APIClient.shared.storeTokens(access: access, refresh: refresh)
        persist(user: user, household: response.household)
        justRegistered = response.isNewUser ?? false
    }

    private func persist(user: AuthUser, household: ServerHousehold?) {
        self.user = user
        self.currentHousehold = household
        UserDefaults.standard.set(try? JSONEncoder().encode(user), forKey: Self.userKey)
        if let household {
            UserDefaults.standard.set(try? JSONEncoder().encode(household), forKey: Self.householdKey)
        }
    }
}
