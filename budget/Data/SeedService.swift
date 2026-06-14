import Foundation
import SwiftData

enum SeedService {

    static let defaultHouseholdName = "Maison"
    private static let bootstrapResourceName = "BudgetBootstrapCategories"

    private struct BootstrapCatalog: Decodable {
        let expenses: BootstrapSection
        let incomes: BootstrapSection
    }

    private struct BootstrapSection: Decodable {
        let categories: [BootstrapCategory]
    }

    private struct BootstrapCategory: Decodable {
        let id: Int
        let name: String
        let emoji: String
        let sortOrder: Int
        let isSystem: Bool?
        let isActive: Bool?
        let subcategories: [BootstrapCategory]?

        enum CodingKeys: String, CodingKey {
            case id, name, emoji, subcategories
            case sortOrder = "sort_order"
            case isSystem = "is_system"
            case isActive = "is_active"
        }
    }

    static func seedIfNeeded(context: ModelContext) {
        seedCategoriesIfNeeded(context: context)
        seedIncomeCategoriesIfNeeded(context: context)
        seedDefaultHouseholdIfNeeded(context: context)
        try? context.save()
    }

    private static func seedDefaultHouseholdIfNeeded(context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Household>())) ?? 0
        guard count == 0 else { return }
        let household = Household(isAnonymous: true, name: defaultHouseholdName, isDefault: true)
        let me = HouseholdMember(displayName: "Moi", isMe: true)
        household.members.append(me)
        context.insert(household)
    }

    private static func seedCategoriesIfNeeded(context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Category>())) ?? 0
        guard count == 0 else { return }
        guard let catalog = loadBootstrapCatalog() else { return }

        for item in catalog.expenses.categories {
            let category = Category(
                serverId: item.id,
                name: item.name,
                emoji: item.emoji,
                sortOrder: item.sortOrder,
                isActive: item.isActive ?? true,
                isSystem: item.isSystem ?? true
            )
            for subItem in item.subcategories ?? [] {
                let sub = Subcategory(
                    serverId: subItem.id,
                    name: subItem.name,
                    emoji: subItem.emoji,
                    sortOrder: subItem.sortOrder,
                    isSystem: subItem.isSystem ?? true
                )
                category.subcategories.append(sub)
            }
            context.insert(category)
        }
    }

    private static func seedIncomeCategoriesIfNeeded(context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<IncomeCategory>())) ?? 0
        guard count == 0 else { return }
        guard let catalog = loadBootstrapCatalog() else { return }

        for item in catalog.incomes.categories {
            context.insert(IncomeCategory(
                serverId: item.id,
                name: item.name,
                emoji: item.emoji,
                sortOrder: item.sortOrder,
                isSystem: item.isSystem ?? true
            ))
        }
    }

    private static func loadBootstrapCatalog() -> BootstrapCatalog? {
        guard let url = Bundle.main.url(forResource: bootstrapResourceName, withExtension: "json") else {
            assertionFailure("Missing \(bootstrapResourceName).json in app bundle.")
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(BootstrapCatalog.self, from: data)
        } catch {
            assertionFailure("Invalid \(bootstrapResourceName).json: \(error)")
            return nil
        }
    }
}
