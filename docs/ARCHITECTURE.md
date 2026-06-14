# Architecture

## Couches

```
budget/
├── App entry
│   ├── budgetApp.swift       — @main, ModelContainer + VersionedSchema
│   └── ContentView.swift     — TabView root, cold-start sync, scenePhase
│
├── Domain/                   — SwiftData @Model entities + helpers
│   ├── Household.swift, HouseholdMember.swift
│   ├── Categories.swift      — Category, Subcategory, IncomeCategory
│   ├── Transactions.swift    — Expense, IncomeEntry, RecurringExpense
│   ├── BudgetLines.swift     — BudgetExpenseLine, BudgetIncome
│   ├── Enums.swift           — SyncStatus, ExpenseStatus, Frequency
│   ├── MonthMath.swift       — UTC-stable month/day formatters for server I/O
│   └── SchemaV1.swift        — VersionedSchema declaration + MigrationPlan
│
├── Data/
│   ├── SeedService.swift            — bootstrap categories from bundled JSON
│   ├── RecurringService.swift       — generate monthly recurring expenses
│   ├── BudgetLineService.swift      — local CRUD with split-on-edit-scope semantics
│   └── Sync/
│       ├── APIClient.swift              — URLSession wrapper, token refresh, scrubbing
│       ├── APIConfig.swift              — base URL, installation_id, app code
│       ├── AppAttestClient.swift        — App Attest key generation + assertion
│       ├── KeychainStore.swift          — token storage
│       ├── AuthSession.swift            — login/logout, household switch, migration
│       ├── SyncService.swift            — pullCategories, pullTransactions(month), pullBudgetLines(month), pullRecurring, reconcileServerHouseholds, syncAll, quickSync
│       ├── MonthSyncService.swift       — per-view month refresh with throttle
│       ├── HistoryService.swift         — /budget/history/overview aggregated fetch
│       ├── HouseholdMigrationService.swift — anonymous → cloud migration logic
│       ├── PushService.swift            — push pending mutations + tombstones
│       ├── NetworkMonitor.swift         — NWPathMonitor, lastReconnectAt observable
│       ├── MetricsCollector.swift       — MetricKit subscriber
│       └── AppLogger.swift              — Logger + SyncErrorReporter + SyncErrorStore
│
└── Presentation/             — SwiftUI views grouped by feature
    ├── Dashboard/, Transactions/, Budget/, History/, Recurring/, Settings/, Common/
```

## Local-first sync model

### Mutations

```
User action
   │
   ▼
View saves SwiftData entity locally     (instant UI)
   │
   ├─► markForUpload (if foyer cloud)
   │
   ▼
PushService.afterLocalChange
   │
   ▼
APIClient.send  ──► server OK  ──► syncStatus = .synced
       │
       └── offline ──► entity stays .pendingUpload
                        ↓
                  NetworkMonitor detects reconnect
                        ↓
                  ContentView triggers quickSync → pushPending
```

### Reads

- **On display** of a view: `MonthSyncService.refreshMonth(...)` (throttle 30s/foyer/mois)
- **Aggregates** (HistoryView): `HistoryService.fetchOverview` — single backend call
- **Foyers / categories / recurring**: pulled at cold start + login only

### Sync entry points

| Trigger | Method | Scope |
|---|---|---|
| Cold start (`ContentView.task`) | `syncAll` + `pullCategories` | foyers, categories, push |
| Login (`postLoginSync`) | idem | idem |
| Network reconnect | `quickSync` | refreshMe + push |
| Foreground (≥60s since last) | `quickSync` | idem |
| Mutation (FormView save) | `afterLocalChange` → `pushPending` | push only |
| View appear (Dashboard, Tx, Budget, History) | `MonthSyncService.refreshMonth` | per-month transactions + budget lines |
| RecurringListView | `MonthSyncService.refreshRecurring` | recurring only |

## Foyers / Households

- **Anonymous (local)**: `isAnonymous=true`, no `serverId`, no `ownerUserId`. Survives logout. Never syncs.
- **Claimed (cloud)**: `serverId` + `ownerUserId` set. Pushes/pulls active. Purged at logout.
- **Orphan**: claimed but `isOrphan=true` (server revoked access). Read-only.

`isDefault=true` on exactly one foyer at a time → drives UI selection across all views.

## Offline queue

Two stores (UserDefaults, JSON-encoded):

- `PendingDeleteStore` — tombstones for deletions (expense, income, recurring, budgetExpenseLine, budgetIncomeLine)
- `PendingHouseholdOpStore` — rename/delete cloud foyer ops

Replayed by `PushService.pushPending` in this order: tombstones → household ops → expenses → incomes → recurring → budget lines.

Retry policy: 4xx → drop op, 5xx → keep + stop replay this round, URLError → keep + stop.

(Phase 1.3 of long-term plan migrates queue to SwiftData `PendingOp` entity with metadata.)

## Authentication & security

- App Attest `keyId` in Keychain. Re-attests on `DCError.invalidInput` or fresh `installation_id` (post-reinstall).
- Backend binds tokens to installation. App Attest assertion canonical hash: `SHA256(METHOD + "\n" + path + "\n" + rawQuery + "\n" + SHA256(body))`.
- Logout purges owned foyers + ensures anonymous foyer exists.
- 401 after refresh retry → `invalidateSession` → `AppAttestClient.reset()` + `clearTokens()` + Notification → ContentView calls `logout`.

## Observability

- `os_log` via `AppLogger.{sync, auth, data, ui, attest}` — categories visible in Console.app filter `subsystem:com.guilhemhosotte.budget`
- `MetricsCollector` subscribes at boot — `MXMetricPayload` + `MXDiagnosticPayload` flushed to logs (visible in Xcode Organizer post-deploy)
- `SyncErrorStore` shared singleton observed by `SyncErrorBanner` in dashboard for user-facing surface
