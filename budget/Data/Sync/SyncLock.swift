import Foundation

/// Sérialise toutes les opérations de sync (cold start, quickSync, refreshMonth, refreshRecurring)
/// pour qu'aucune ne tourne en parallèle. Au cold start, une rafale d'appels concurrents saturait
/// l'executor : les continuations `URLSession` reprenaient des secondes plus tard (timer `net` gonflé
/// à ~3-7s alors que le serveur répond en ~20ms). En file d'attente, chaque appel a l'executor pour lui.
///
/// `@MainActor` : tout le sync est déjà MainActor, donc les closures capturent `ModelContext`
/// (non-Sendable) sans souci. Les points d'entrée gardés ne s'appellent jamais entre eux → pas de
/// deadlock par réentrance.
@MainActor
enum SyncLock {
    private static var tail: Task<Void, Never> = Task {}

    /// Exécute `work` après la fin de l'opération sérialisée précédente. Propage le résultat / l'erreur.
    @discardableResult
    static func run<T>(_ work: @escaping () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task<T, Error> {
            await previous.value
            return try await work()
        }
        // La queue continue même si `work` jette (on ignore l'erreur côté chaînage).
        tail = Task { _ = try? await task.value }
        return try await task.value
    }
}
