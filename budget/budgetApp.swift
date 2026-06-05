//
//  budgetApp.swift
//  budget
//
//  Created by Guilhem Hosotte on 05/06/2026.
//

import SwiftUI
import CoreData

@main
struct budgetApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
