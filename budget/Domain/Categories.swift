import Foundation
import SwiftData

@Model
final class Category {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var serverId: Int?
    var name: String = ""
    var nameEn: String?
    var emoji: String = ""
    var sortOrder: Int = 0
    var isActive: Bool = true
    var isSystem: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \Subcategory.category)
    var subcategories: [Subcategory] = []

    /// Nom affiché selon la langue du foyer courant. Repli FR si pas de traduction.
    var displayName: String {
        AppLocale.activeCode == "en" ? (nameEn ?? name) : name
    }

    init(
        id: UUID = UUID(),
        serverId: Int? = nil,
        name: String,
        nameEn: String? = nil,
        emoji: String,
        sortOrder: Int = 0,
        isActive: Bool = true,
        isSystem: Bool = false
    ) {
        self.id = id
        self.serverId = serverId
        self.name = name
        self.nameEn = nameEn
        self.emoji = emoji
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.isSystem = isSystem
    }
}

@Model
final class Subcategory {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var serverId: Int?
    var category: Category?
    var name: String = ""
    var nameEn: String?
    var emoji: String = ""
    var sortOrder: Int = 0
    var isSystem: Bool = false

    var displayName: String {
        AppLocale.activeCode == "en" ? (nameEn ?? name) : name
    }

    init(
        id: UUID = UUID(),
        serverId: Int? = nil,
        name: String,
        nameEn: String? = nil,
        emoji: String = "",
        sortOrder: Int = 0,
        isSystem: Bool = false
    ) {
        self.id = id
        self.serverId = serverId
        self.name = name
        self.nameEn = nameEn
        self.emoji = emoji
        self.sortOrder = sortOrder
        self.isSystem = isSystem
    }
}

@Model
final class IncomeCategory {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var serverId: Int?
    var name: String = ""
    var nameEn: String?
    var emoji: String = ""
    var sortOrder: Int = 0
    var isSystem: Bool = false

    var displayName: String {
        AppLocale.activeCode == "en" ? (nameEn ?? name) : name
    }

    init(
        id: UUID = UUID(),
        serverId: Int? = nil,
        name: String,
        nameEn: String? = nil,
        emoji: String,
        sortOrder: Int = 0,
        isSystem: Bool = false
    ) {
        self.id = id
        self.serverId = serverId
        self.name = name
        self.nameEn = nameEn
        self.emoji = emoji
        self.sortOrder = sortOrder
        self.isSystem = isSystem
    }
}
