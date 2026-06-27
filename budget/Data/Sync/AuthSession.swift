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
    var currency: String
    var locale: String

    init(id: Int, name: String, currency: String = Currency.default, locale: String = AppLocale.default) {
        self.id = id
        self.name = name
        self.currency = currency
        self.locale = locale
    }

    // Décodage tolérant : les blobs cachés d'anciennes versions n'ont ni `currency` ni `locale`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        currency = (try c.decodeIfPresent(String.self, forKey: .currency)) ?? Currency.default
        locale = (try c.decodeIfPresent(String.self, forKey: .locale)) ?? AppLocale.default
    }
}

@Observable
@MainActor
final class AuthSession {
    private static let userKey = "auth.user"
    private static let householdKey = "auth.household"

    private(set) var user: AuthUser?

    /// `currentHousehold` ne pilote pas Currency/AppLocale : le foyer **actif** est celui marqué
    /// `isDefault` localement (peut différer du foyer cloud courant). Les sites qui changent
    /// le foyer actif (cold start, switcher, post-login, édition foyer) appellent explicitement
    /// `Currency.setActive` / `AppLocale.setActive`. Voir `active-foyer-locale-model` (memory).
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

    /// No-op kept for callers — Currency/AppLocale sont pilotés exclusivement par les sites
    /// qui changent le foyer actif local (`isDefault`).
    func bootstrap() {}

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
        // Le contexte background de l'engine garde des objets en cache → le jeter après purge des données.
        SyncEngineProvider.reset()
        MonthSyncService.invalidate()

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
                let currency: String?
                let locale: String?
                let memberCount: Int?

                enum CodingKeys: String, CodingKey {
                    case id, name, currency, locale
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
            ServerHousehold(id: $0.id, name: $0.name, currency: $0.currency ?? Currency.default, locale: $0.locale ?? AppLocale.default)
        }
        // Préserve le foyer actif déjà sélectionné (le switch est lié au token) s'il existe
        // toujours côté serveur : on rafraîchit ses métadonnées (nom/devise/langue) sans changer
        // de foyer. `current_household_id` de GET /households peut renvoyer le foyer PAR DÉFAUT du
        // compte plutôt que le foyer actif du token → l'utiliser uniquement en repli (aucun foyer
        // local valide), sinon le démarrage réinitialisait le foyer actif sur le foyer par défaut.
        if let existing = currentHousehold,
           let refreshed = serverHouseholds.first(where: { $0.id == existing.id }) {
            currentHousehold = refreshed
            UserDefaults.standard.set(try? JSONEncoder().encode(refreshed), forKey: Self.householdKey)
        } else if let currentId = response.currentHouseholdId,
                  let match = serverHouseholds.first(where: { $0.id == currentId }) {
            currentHousehold = match
            UserDefaults.standard.set(try? JSONEncoder().encode(match), forKey: Self.householdKey)
        }
    }

    func createCloudHousehold(
        name: String,
        currency: String = Currency.systemDefault(),
        locale: String = AppLocale.systemDefault()
    ) async throws -> ServerHousehold {
        struct CreateResponse: Decodable {
            let success: Bool
            let error: String?
            let household: ServerHousehold?
        }
        let response: CreateResponse = try await APIClient.shared.send(
            CreateResponse.self,
            method: "POST",
            path: "/budget/households",
            body: ["name": name, "currency": currency, "locale": locale]
        )
        guard response.success, let household = response.household else {
            throw APIError.http(400, response.error ?? NSLocalizedString("Création foyer refusée.", comment: ""))
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
            throw APIError.http(400, response.error ?? NSLocalizedString("Renommage refusé.", comment: ""))
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

    /// PATCH la devise d'un foyer cloud. Met à jour le cache local + la devise active si c'est le foyer courant.
    func setCurrencyCloud(serverId: Int, currency: String) async throws {
        struct CurrencyResponse: Decodable {
            let success: Bool
            let error: String?
            let household: ServerHousehold?
        }
        let response: CurrencyResponse = try await APIClient.shared.send(
            CurrencyResponse.self,
            method: "PATCH",
            path: "/budget/households/\(serverId)/currency",
            body: ["currency": currency]
        )
        guard response.success, let updated = response.household else {
            throw APIError.http(400, response.error ?? NSLocalizedString("Changement de devise refusé.", comment: ""))
        }
        // Endpoint /currency renvoie un foyer partiel (sans locale) : ne muter que la devise.
        if let idx = serverHouseholds.firstIndex(where: { $0.id == serverId }) {
            serverHouseholds[idx].currency = updated.currency
        }
        if var current = currentHousehold, current.id == serverId {
            current.currency = updated.currency
            currentHousehold = current
            UserDefaults.standard.set(try? JSONEncoder().encode(current), forKey: Self.householdKey)
        }
    }

    /// PATCH la langue d'un foyer cloud. Met à jour le cache local.
    func setLocaleCloud(serverId: Int, locale: String) async throws {
        struct LocaleResponse: Decodable {
            let success: Bool
            let error: String?
            let household: ServerHousehold?
        }
        let response: LocaleResponse = try await APIClient.shared.send(
            LocaleResponse.self,
            method: "PATCH",
            path: "/budget/households/\(serverId)/locale",
            body: ["locale": locale]
        )
        guard response.success, let updated = response.household else {
            throw APIError.http(400, response.error ?? NSLocalizedString("Changement de langue refusé.", comment: ""))
        }
        // Endpoint /locale renvoie un foyer partiel (sans devise) : ne muter que la langue.
        if let idx = serverHouseholds.firstIndex(where: { $0.id == serverId }) {
            serverHouseholds[idx].locale = updated.locale
        }
        if var current = currentHousehold, current.id == serverId {
            current.locale = updated.locale
            currentHousehold = current
            UserDefaults.standard.set(try? JSONEncoder().encode(current), forKey: Self.householdKey)
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
            throw APIError.http(400, response.error ?? NSLocalizedString("Suppression refusée.", comment: ""))
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
            throw APIError.http(400, response.error ?? NSLocalizedString("Invitation refusée.", comment: ""))
        }
        APIClient.shared.storeTokens(access: access, refresh: refresh)
        currentHousehold = household
        UserDefaults.standard.set(try? JSONEncoder().encode(household), forKey: Self.householdKey)
        if !serverHouseholds.contains(where: { $0.id == household.id }) {
            serverHouseholds.append(household)
        }
        SyncEngineProvider.reset()
        MonthSyncService.invalidate()
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
            throw APIError.http(400, response.error ?? NSLocalizedString("Switch foyer refusé.", comment: ""))
        }
        APIClient.shared.storeTokens(access: access, refresh: refresh)
        currentHousehold = household
        UserDefaults.standard.set(try? JSONEncoder().encode(household), forKey: Self.householdKey)
        // Foyer actif changé → jeter le contexte background en cache + les throttles du mois.
        SyncEngineProvider.reset()
        MonthSyncService.invalidate()
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
        // La SÉLECTION du foyer est pilotée par le client (foyer actif local), jamais par `/me`.
        // `/me` ne sert qu'à confirmer la session : son `current_household` est PARTIEL (id + nom,
        // sans `currency`/`locale`), donc `ServerHousehold` y applique ses défauts (locale "fr").
        // L'adopter écrasait la langue réelle du foyer → le `didSet` repassait en français avant que
        // `refreshHouseholds` ne rétablisse l'anglais (flash fr→en). On garde donc le foyer courant
        // existant ; on n'adopte celui de `/me` qu'à défaut (aucun foyer encore sélectionné).
        persist(user: me, household: currentHousehold ?? response.currentHousehold)
    }

    // MARK: — Privé

    private func apply(_ response: AuthResponse) throws {
        guard response.success,
              let access = response.accessToken,
              let refresh = response.refreshToken,
              let user = response.user else {
            throw APIError.http(401, response.error ?? NSLocalizedString("Authentification refusée.", comment: ""))
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
