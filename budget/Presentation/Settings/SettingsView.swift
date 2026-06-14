import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage("appTheme") private var themeRaw = AppTheme.system.rawValue
    @AppStorage("currencySymbol") private var currencySymbol = "€"
    @AppStorage("lastSyncAt") private var lastSyncAt: Double = 0

    @Environment(AuthSession.self) private var session
    @Environment(\.modelContext) private var modelContext

    @Query private var households: [Household]

    private static let currencies = ["€", "$", "£", "CHF"]

    private var activeHouseholdName: String {
        (households.first(where: \.isDefault) ?? households.first)?.name ?? SeedService.defaultHouseholdName
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                accountSection

                Section("Foyer") {
                    NavigationLink {
                        HouseholdsView()
                    } label: {
                        LabeledContent("Foyers", value: activeHouseholdName)
                    }
                    .listRowBackground(Color.budgetSurface)
                    NavigationLink {
                        RecurringListContent()
                    } label: {
                        Text("Dépenses récurrentes")
                    }
                    .listRowBackground(Color.budgetSurface)
                }

                Section("Apparence") {
                    Picker("Thème", selection: $themeRaw) {
                        ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                            Text(theme.label).tag(theme.rawValue)
                        }
                    }
                    .listRowBackground(Color.budgetSurface)
                }

                Section("Devise") {
                    Picker("Symbole", selection: $currencySymbol) {
                        ForEach(Self.currencies, id: \.self) { symbol in
                            Text(symbol).tag(symbol)
                        }
                    }
                    .listRowBackground(Color.budgetSurface)
                }

                Section {
                } footer: {
                    Text(appVersion)
                        .frame(maxWidth: .infinity)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.budgetBg)
            .navigationTitle("Réglages")
        }
        .tint(.budgetPrimary)
    }

    @ViewBuilder
    private var accountSection: some View {
        if session.isAuthenticated {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.budgetPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.user?.firstName ?? session.user?.email ?? "Connecté")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.budgetText)
                        Text(session.user?.email ?? "")
                            .font(.caption)
                            .foregroundStyle(Color.budgetTextMute)
                    }
                }
                .padding(.vertical, 2)
                .listRowBackground(Color.budgetSurface)

                Button("Se déconnecter", role: .destructive) {
                    Task { await session.logout(context: modelContext) }
                }
                .listRowBackground(Color.budgetSurface)
            } header: {
                Text("Compte")
            } footer: {
                if lastSyncAt > 0 {
                    Text("Dernière synchronisation : \(Date(timeIntervalSince1970: lastSyncAt).formatted(date: .abbreviated, time: .shortened))")
                }
            }
        } else {
            Section {
                NavigationLink {
                    LoginView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.budgetTextFaint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Se connecter")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.budgetText)
                            Text("Synchronisation et partage de foyer")
                                .font(.caption)
                                .foregroundStyle(Color.budgetTextMute)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowBackground(Color.budgetSurface)
            } header: {
                Text("Compte")
            } footer: {
                Text("Sans compte, toutes les données restent sur cet appareil.")
            }
        }
    }

}
