import Foundation
import SwiftData

@Model
public final class Category {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var serverId: Int?
    public var name: String = ""
    public var nameEn: String?
    public var emoji: String = ""
    public var sortOrder: Int = 0
    public var isActive: Bool = true
    public var isSystem: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \Subcategory.category)
    public var subcategories: [Subcategory] = []

    /// Nom affiché selon la langue du foyer courant. Repli FR si pas de traduction.
    public var displayName: String {
        AppLocale.activeCode == "en" ? (nameEn ?? name) : name
    }

    public init(
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
public final class Subcategory {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var serverId: Int?
    public var category: Category?
    public var name: String = ""
    public var nameEn: String?
    public var emoji: String = ""
    public var sortOrder: Int = 0
    public var isSystem: Bool = false

    public var displayName: String {
        AppLocale.activeCode == "en" ? (nameEn ?? name) : name
    }

    public init(
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
public final class IncomeCategory {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var serverId: Int?
    public var name: String = ""
    public var nameEn: String?
    public var emoji: String = ""
    public var sortOrder: Int = 0
    public var isSystem: Bool = false

    public var displayName: String {
        AppLocale.activeCode == "en" ? (nameEn ?? name) : name
    }

    public init(
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
