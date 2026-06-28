//
//  AppIntent.swift
//  BudgetWidget
//
//  Configuration du widget : sélection du foyer (obligatoire, pas de fallback).
//

import WidgetKit
import AppIntents
import SwiftData
import BudgetKit

/// Foyer sélectionnable dans la config du widget. Lu depuis le store SwiftData partagé (App Group).
struct FoyerEntity: AppEntity {
    let id: UUID
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Foyer" }
    static var defaultQuery = FoyerQuery()

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct FoyerQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [FoyerEntity] {
        try await allFoyers().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [FoyerEntity] {
        try await allFoyers()
    }

    @MainActor
    private func allFoyers() throws -> [FoyerEntity] {
        let context = ModelContext(SharedStore.makeContainer())
        let households = try context.fetch(
            FetchDescriptor<Household>(sortBy: [SortDescriptor(\.createdAt)])
        )
        return households.map { FoyerEntity(id: $0.id, name: $0.name) }
    }
}

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Foyer" }
    static var description: IntentDescription { "Choisir le foyer affiché par le widget." }

    @Parameter(title: "Foyer")
    var foyer: FoyerEntity?
}
