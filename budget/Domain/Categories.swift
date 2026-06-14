import Foundation
import SwiftData

@Model
final class Category {
    var id: UUID
    var serverId: Int?
    var name: String = ""
    var emoji: String = ""
    var sortOrder: Int = 0
    var isActive: Bool = true
    var isSystem: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \Subcategory.category)
    var subcategories: [Subcategory] = []

    init(
        id: UUID = UUID(),
        serverId: Int? = nil,
        name: String,
        emoji: String,
        sortOrder: Int = 0,
        isActive: Bool = true,
        isSystem: Bool = false
    ) {
        self.id = id
        self.serverId = serverId
        self.name = name
        self.emoji = emoji
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.isSystem = isSystem
    }
}

@Model
final class Subcategory {
    var id: UUID
    var serverId: Int?
    var category: Category?
    var name: String = ""
    var emoji: String = ""
    var sortOrder: Int = 0
    var isSystem: Bool = false

    init(
        id: UUID = UUID(),
        serverId: Int? = nil,
        name: String,
        emoji: String = "",
        sortOrder: Int = 0,
        isSystem: Bool = false
    ) {
        self.id = id
        self.serverId = serverId
        self.name = name
        self.emoji = emoji
        self.sortOrder = sortOrder
        self.isSystem = isSystem
    }
}

@Model
final class IncomeCategory {
    var id: UUID
    var serverId: Int?
    var name: String = ""
    var emoji: String = ""
    var sortOrder: Int = 0
    var isSystem: Bool = false

    init(
        id: UUID = UUID(),
        serverId: Int? = nil,
        name: String,
        emoji: String,
        sortOrder: Int = 0,
        isSystem: Bool = false
    ) {
        self.id = id
        self.serverId = serverId
        self.name = name
        self.emoji = emoji
        self.sortOrder = sortOrder
        self.isSystem = isSystem
    }
}
