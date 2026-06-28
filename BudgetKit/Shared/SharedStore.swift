//
//  SharedStore.swift
//  budget
//
//  Container SwiftData partagé app ↔ widget extension via App Group.
//  Inclut la migration one-shot de l'ancien store (emplacement défaut) → App Group.
//

import Foundation
import SwiftData
import os

public enum SharedStore {

    /// Identifiant App Group — doit matcher l'entitlement des 2 cibles (app + widget).
    public static let appGroupID = "group.com.guilhemhosotte.budget"

    /// Nom de fichier du store SwiftData (défaut historique = "default.store").
    public static let storeName = "default.store"

    private static let log = Logger(subsystem: "com.guilhemhosotte.budget", category: "SharedStore")

    /// Suffixes des fichiers SQLite à déplacer ensemble (WAL/SHM = état de transaction non commit).
    private static let companionSuffixes = ["", "-wal", "-shm"]

    /// URL du store dans le container App Group (cible).
    public static var groupStoreURL: URL {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            fatalError("App Group \(appGroupID) introuvable — entitlement manquant ?")
        }
        let supportDir = container.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        return supportDir.appending(path: storeName)
    }

    /// URL historique du store (emplacement défaut SwiftData = Application Support de l'app).
    public static var legacyStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: storeName)
    }

    /// Crée le ModelContainer pointant sur le store App Group.
    /// Migre d'abord l'ancien store si présent. À appeler depuis l'app ET le widget.
    public static func makeContainer() -> ModelContainer {
        migrateLegacyStoreIfNeeded()

        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: groupStoreURL)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: BudgetMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    /// Copie one-shot ancien store → App Group.
    /// Idempotent : ne fait rien si la cible existe déjà ou si l'ancien est absent.
    /// NE SUPPRIME JAMAIS l'ancien fichier (rollback possible).
    private static func migrateLegacyStoreIfNeeded() {
        let fm = FileManager.default
        let target = groupStoreURL
        let source = legacyStoreURL

        // Cible déjà en place → migration déjà faite (ou nouveau user). Stop.
        guard !fm.fileExists(atPath: target.path) else { return }
        // Pas d'ancien store → nouveau user, rien à migrer.
        guard fm.fileExists(atPath: source.path) else { return }

        log.notice("Migration store défaut → App Group: démarrage")
        for suffix in companionSuffixes {
            let src = source.appendingToFileName(suffix)
            let dst = target.appendingToFileName(suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            do {
                try fm.copyItem(at: src, to: dst)
            } catch {
                // Échec partiel → nettoyer la cible pour ne pas ouvrir un store corrompu,
                // l'app retombe sur l'ancien store au prochain lancement.
                log.error("Migration échouée (\(suffix, privacy: .public)): \(error.localizedDescription, privacy: .public). Rollback cible.")
                cleanupPartialTarget()
                return
            }
        }
        log.notice("Migration store → App Group: OK")
    }

    private static func cleanupPartialTarget() {
        let fm = FileManager.default
        for suffix in companionSuffixes {
            try? fm.removeItem(at: groupStoreURL.appendingToFileName(suffix))
        }
    }
}

private extension URL {
    /// Ajoute un suffixe au nom de fichier (avant gestion d'extension) — "default.store" + "-wal".
    func appendingToFileName(_ suffix: String) -> URL {
        guard !suffix.isEmpty else { return self }
        let dir = deletingLastPathComponent()
        return dir.appending(path: lastPathComponent + suffix)
    }
}
