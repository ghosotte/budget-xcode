# Application Budget iOS — Spécification Technique

## Vue d'ensemble

Application native iOS de gestion budgétaire personnelle / familiale. Architecture **local-first** : toutes les données vivent en base locale (SwiftData/SQLite). Connexion serveur optionnelle pour partager un foyer avec d'autres utilisateurs.

---

## Fonctionnalités

### MVP (offline complet)

| Fonctionnalité | Détail |
|---|---|
| Multi-foyers | Créer et switcher entre plusieurs foyers locaux |
| Catégories | Lecture seule depuis le serveur (one-shot si DB locale vide), fallback sur liste embarquée |
| Budget mensuel | Définir des lignes budgétaires par catégorie/sous-catégorie, fréquence mensuelle ou ponctuelle |
| Transactions | Vue unifiée dépenses + revenus — ajouter / modifier / supprimer / dupliquer |
| Bilan | Comparaison budget prévu vs réel par mois |
| Historique | Statistiques mensuelles (max / moy / min), navigation par mois |
| Dashboard | Vue d'accueil : solde du mois, dépenses récentes, prochains récurrents |

### Hors scope (non porté depuis le web)

- Édition de catégories / sous-catégories personnalisées
- Import bancaire / CSV
- Analyse IA / profil financier
- Crédits et épargne

---

## Architecture locale (offline-first)

```
┌─────────────────────────────────────────┐
│              iOS App                    │
│                                         │
│  ┌──────────┐   ┌───────────────────┐   │
│  │  SwiftUI │──▶│   ViewModel layer │   │
│  └──────────┘   └─────────┬─────────┘   │
│                           │             │
│                 ┌─────────▼─────────┐   │
│                 │  SwiftData (local) │   │
│                 └─────────┬─────────┘   │
│                           │             │
│                 ┌─────────▼─────────┐   │
│                 │   SyncService     │   │ (optionnel)
│                 └─────────┬─────────┘   │
└───────────────────────────┼─────────────┘
                            │ HTTPS/JSON
                 ┌──────────▼──────────┐
                 │   API theApp server  │
                 └─────────────────────┘
```

---

## Modèle de données local (SwiftData)

### `Household` — Foyer

```swift
@Model class Household {
    var id: UUID                      // local UUID (server: Int si sync)
    var serverId: Int?                // nil = local-only
    var name: String
    var createdAt: Date
    var isDefault: Bool               // foyer affiché par défaut
    // relations
    var members: [HouseholdMember]
    var expenses: [Expense]
    var incomeEntries: [IncomeEntry]
    var budgetExpenseLines: [BudgetExpenseLine]
    var budgetIncomes: [BudgetIncome]
    var recurringExpenses: [RecurringExpense]
}
```

### `HouseholdMember` — Membre du foyer

```swift
@Model class HouseholdMember {
    var id: UUID
    var household: Household
    var displayName: String           // prénom ou "Moi"
    var isMe: Bool                    // vrai pour le compte local principal
    var joinedAt: Date
    // si connecté au serveur
    var serverUserId: Int?
}
```

### `Category` — Catégorie de dépense

```swift
@Model class Category {
    var id: UUID
    var serverId: Int?                // id serveur (pour sync)
    var name: String
    var emoji: String
    var sortOrder: Int
    var isActive: Bool
    var isSystem: Bool                // true = vient du serveur, non éditable
    var subcategories: [Subcategory]
}
```

**Seed embarqué** : liste de catégories de base codée en dur dans l'app pour usage offline pur. One-shot fetch depuis le serveur si disponible et DB vide.

### `Subcategory` — Sous-catégorie

```swift
@Model class Subcategory {
    var id: UUID
    var serverId: Int?
    var category: Category
    var name: String
    var emoji: String
    var sortOrder: Int
    var isSystem: Bool
}
```

### `IncomeCategory` — Catégorie de revenu

```swift
@Model class IncomeCategory {
    var id: UUID
    var serverId: Int?
    var name: String
    var emoji: String
    var sortOrder: Int
    var isSystem: Bool
}
```

**Exemples** : Salaire, Freelance, Location, Aides, Autres.

### `BudgetExpenseLine` — Ligne budgétaire de dépense

```swift
@Model class BudgetExpenseLine {
    var id: UUID
    var serverId: Int?
    var household: Household
    var category: Category
    var subcategory: Subcategory?
    var month: Date                   // premier jour du mois (ex: 2025-03-01)
    var endMonth: Date?               // dernier mois inclus, nil = indéfini
    var groupId: UUID                 // relie les versions d'une même ligne logique
    var frequency: Frequency          // .monthly | .punctual
    var amount: Decimal
    var syncStatus: SyncStatus        // .local | .synced | .pendingUpload | .pendingDelete
}

enum Frequency: String { case monthly, punctual }
enum SyncStatus: String { case local, synced, pendingUpload, pendingDelete }
```

**Logique de plage** : une ligne est active pour un mois M si `month <= M` et (`endMonth == nil` ou `endMonth >= M`).

**Scoped update** (modification depuis un mois donné) :

- `this_month_only` → ferme la ligne existante (`endMonth = M-1`), crée nouvelle ligne pour M seulement (`endMonth = M`), crée continuité de M+1 avec l'ancien montant.
- `from_this_month` → ferme la ligne existante (`endMonth = M-1`), crée nouvelle ligne à partir de M.

### `BudgetIncome` — Ligne budgétaire de revenu

```swift
@Model class BudgetIncome {
    var id: UUID
    var serverId: Int?
    var household: Household
    var incomeCategory: IncomeCategory?
    var month: Date
    var endMonth: Date?
    var groupId: UUID
    var frequency: Frequency
    var amount: Decimal
    var syncStatus: SyncStatus
}
```

Même logique de plage et scoped update que `BudgetExpenseLine`.

### `Expense` — Dépense réelle

```swift
@Model class Expense {
    var id: UUID
    var serverId: Int?
    var household: Household
    var category: Category?
    var subcategory: Subcategory?
    var amount: Decimal               // toujours positif
    var label: String
    var spentAt: Date                 // date réelle de la dépense
    var accountingMonth: Date?        // override mois comptable (nil = dérivé de spentAt)
    var status: ExpenseStatus         // .real | .planned
    var recurringTemplate: RecurringExpense?
    var tags: [String]
    var notes: String?
    var createdAt: Date
    var updatedAt: Date?
    var syncStatus: SyncStatus
}

enum ExpenseStatus: String { case real, planned }
```

**Mois comptable effectif** : `accountingMonth ?? Calendar.startOfMonth(spentAt)`

### `IncomeEntry` — Revenu réel

```swift
@Model class IncomeEntry {
    var id: UUID
    var serverId: Int?
    var household: Household
    var incomeCategory: IncomeCategory?
    var amount: Decimal
    var label: String
    var receivedAt: Date
    var accountingMonth: Date?
    var status: ExpenseStatus         // .real | .planned
    var notes: String?
    var createdAt: Date
    var updatedAt: Date?
    var syncStatus: SyncStatus
}
```

### `RecurringExpense` — Dépense récurrente (template)

```swift
@Model class RecurringExpense {
    var id: UUID
    var serverId: Int?
    var household: Household
    var category: Category?
    var subcategory: Subcategory?
    var amount: Decimal
    var label: String
    var dayOfMonth: Int               // 1–28
    var isActive: Bool
    var autoConfirm: Bool             // auto-créer en "real" (vs "planned")
    var createdAt: Date
    var syncStatus: SyncStatus
}
```

**Génération mensuelle** : au 1er lancement du mois, pour chaque `RecurringExpense` actif, créer une `Expense` avec `status = autoConfirm ? .real : .planned` si elle n'existe pas déjà pour ce mois.

---

## Compte local et connexion serveur

### Mode offline (défaut)

- Pas de compte requis.
- Identité locale = appareil.
- `HouseholdMember` créé automatiquement avec `isMe = true`.

### Mode connecté (optionnel)

L'utilisateur peut se connecter pour :
1. **Récupérer** un foyer partagé existant depuis le serveur.
2. **Partager** son foyer local avec d'autres (upload initial puis sync).

#### Flux d'authentification

```
POST /budget/auth/register   { email, password, first_name }
POST /budget/auth/login      { email, password }
POST /budget/auth/google     { id_token }
POST /budget/auth/apple      { identity_token, first_name? }
POST /budget/auth/refresh    { refresh_token }
POST /budget/auth/logout
GET  /budget/auth/me
```

**Tokens** : access token (durée courte, stocké dans Keychain) + refresh token (rotation, stocké dans Keychain).

#### Sync des catégories (one-shot)

```
GET /budget/categories           → [Category + Subcategory[]]
GET /budget/income-categories    → [IncomeCategory[]]
```

Déclenché une fois si la DB locale est vide. Résultat stocké avec `isSystem = true`.

---

## Endpoints API nécessaires (à implémenter côté serveur)

> Routes sous `api.theapp.fr`, authentification par Bearer token.

### Catégories (lecture seule)

| Méthode | Route | Description |
|---|---|---|
| GET | `/budget/categories` | Toutes les catégories + sous-catégories système |
| GET | `/budget/income-categories` | Toutes les catégories de revenu |

### Foyer

| Méthode | Route | Description |
|---|---|---|
| GET | `/budget/households` | Foyers du user connecté |
| POST | `/budget/households` | Créer un foyer |
| GET | `/budget/households/{id}` | Détail + membres |

### Budget mensuel

| Méthode | Route | Description |
|---|---|---|
| GET | `/budget/households/{id}/budget?year=&month=` | Lignes budgétaires actives pour le mois |
| POST | `/budget/households/{id}/budget/expense-lines` | Créer ligne dépense |
| PUT | `/budget/households/{id}/budget/expense-lines/{lineId}` | Modifier (avec edit_scope) |
| DELETE | `/budget/households/{id}/budget/expense-lines/{lineId}?year=&month=` | Supprimer |
| POST | `/budget/households/{id}/budget/income-lines` | Créer ligne revenu |
| PUT | `/budget/households/{id}/budget/income-lines/{lineId}` | Modifier |
| DELETE | `/budget/households/{id}/budget/income-lines/{lineId}?year=&month=` | Supprimer |

### Dépenses

| Méthode | Route | Description |
|---|---|---|
| GET | `/budget/households/{id}/expenses?year=&month=` | Dépenses du mois |
| POST | `/budget/households/{id}/expenses` | Créer |
| PUT | `/budget/households/{id}/expenses/{expId}` | Modifier |
| DELETE | `/budget/households/{id}/expenses/{expId}` | Supprimer |

### Revenus

| Méthode | Route | Description |
|---|---|---|
| GET | `/budget/households/{id}/income-entries?year=&month=` | Revenus du mois |
| POST | `/budget/households/{id}/income-entries` | Créer |
| PUT | `/budget/households/{id}/income-entries/{entryId}` | Modifier |
| DELETE | `/budget/households/{id}/income-entries/{entryId}` | Supprimer |

### Récurrents

| Méthode | Route | Description |
|---|---|---|
| GET | `/budget/households/{id}/recurring` | Templates actifs |
| POST | `/budget/households/{id}/recurring` | Créer |
| PUT | `/budget/households/{id}/recurring/{recId}` | Modifier |
| DELETE | `/budget/households/{id}/recurring/{recId}` | Supprimer |
| PATCH | `/budget/households/{id}/recurring/{recId}/toggle` | Activer/désactiver |

### Dashboard & Bilan

| Méthode | Route | Description |
|---|---|---|
| GET | `/budget/households/{id}/dashboard?year=&month=` | KPIs du mois (totaux, dernières dépenses) |
| GET | `/budget/households/{id}/bilan?year=&month=` | Budget vs réel par catégorie |
| GET | `/budget/households/{id}/history?months=12` | Historique mensuel (totaux) |

---

## Format JSON de référence

### Expense (création)

```json
{
  "amount": "45.90",
  "label": "Courses Lidl",
  "spent_at": "2025-03-15",
  "status": "real",
  "category_id": 3,
  "subcategory_id": 12,
  "tags": ["courses"],
  "notes": null,
  "accounting_month": null
}
```

### BudgetExpenseLine (création)

```json
{
  "category_id": 3,
  "subcategory_id": null,
  "year": 2025,
  "month": 3,
  "frequency": "monthly",
  "amount": "300.00"
}
```

### BudgetExpenseLine (modification scoped)

```json
{
  "category_id": 3,
  "subcategory_id": null,
  "year": 2025,
  "month": 3,
  "frequency": "monthly",
  "amount": "350.00",
  "edit_scope": "from_this_month"
}
```

`edit_scope` : `from_this_month` | `this_month_only`

### Bilan (réponse)

```json
{
  "year": 2025,
  "month": 3,
  "total_budget_expenses": 1200.00,
  "total_real_expenses": 1143.50,
  "total_budget_income": 2500.00,
  "total_real_income": 2500.00,
  "categories": [
    {
      "category_id": 3,
      "category_name": "Alimentation",
      "category_emoji": "🍎",
      "budget_amount": 400.00,
      "real_amount": 387.20,
      "subcategories": [
        {
          "subcategory_id": 12,
          "subcategory_name": "Courses",
          "budget_amount": 300.00,
          "real_amount": 290.00
        }
      ]
    }
  ]
}
```

---

## Stratégie de synchronisation (si connecté)

### Priorités

1. **Catégories** : serveur → local, one-shot, pas de conflit possible.
2. **Foyer partagé** : serveur est source de vérité. Pull au lancement, push immédiat sur chaque modification.
3. **Foyer local** : upload complet au moment du partage (migration locale → serveur).

### SyncStatus

```
.local          → jamais envoyé au serveur (foyer local-only)
.synced         → en phase avec le serveur
.pendingUpload  → créé/modifié localement, pas encore envoyé
.pendingDelete  → supprimé localement, DELETE serveur en attente
```

### Résolution de conflits (simplifiée)

- Pas de sync bidirectionnelle en temps réel pour le MVP.
- Pull full du mois courant au lancement de l'app.
- En cas de conflit (même entité modifiée des deux côtés) → serveur gagne, UI notifie l'utilisateur.

---

## Écrans principaux

### Dashboard (accueil)
- Mois courant : revenus réels vs budget, dépenses réelles vs budget
- Solde estimé (revenus - dépenses)
- 5 dernières transactions
- Prochains récurrents du mois (non confirmés)
- Navigation rapide vers Transactions / Budget

### Transactions (vue unifiée)
- Liste du mois : dépenses **et** revenus mélangés, triés par date décroissante
- Dépenses en rouge (montant négatif), revenus en vert (montant positif)
- Groupement par jour (header de section = date)
- Filtre : Tout / Dépenses / Revenus + filtre par catégorie
- Swipe → supprimer / dupliquer
- Tap → éditer (formulaire adapté selon le type)
- FAB avec menu → **Nouvelle dépense** | **Nouveau revenu**

#### Modèle discriminé (ViewModel)

```swift
enum TransactionItem: Identifiable {
    case expense(Expense)
    case income(IncomeEntry)

    var id: UUID          { /* uuid de l'entité sous-jacente */ }
    var date: Date        { /* spentAt ou receivedAt */ }
    var label: String     { /* label */ }
    var amount: Decimal   { /* positif pour revenu, négatif pour dépense */ }
    var emoji: String     { /* emoji catégorie */ }
    var categoryName: String { /* nom catégorie */ }
    var isIncome: Bool    { if case .income = self { return true }; return false }
}
```

Fusion locale dans le ViewModel, **pas d'endpoint unifié** — 2 requêtes parallèles au sync :

```swift
async let exp = fetchExpenses(householdId, year, month)
async let inc = fetchIncomeEntries(householdId, year, month)
let (expenses, incomes) = try await (exp, inc)
```

#### Formulaire Nouvelle dépense
- Montant, libellé, date, catégorie, sous-catégorie, statut (réel/prévu), notes, tags

#### Formulaire Nouveau revenu
- Montant, libellé, date réception, catégorie revenu, statut (réel/prévu), notes

### Budget
- Grille par catégorie pour le mois sélectionné
- Tap catégorie → voir/éditer les lignes (global + sous-catégories)
- Ajout de ligne avec choix fréquence mensuelle/ponctuelle
- Modification avec choix scope (ce mois / à partir de ce mois)

### Bilan
- Vue mois sélectionnable
- Barre budget vs réel par catégorie
- Total revenus / dépenses / solde
- Détail par catégorie dépliable → sous-catégories

### Historique
- Graphe 6/12 mois (bar chart) : total dépenses par mois
- Stats : max, min, moyenne sur la période
- Filtre par catégorie
- Tap mois → drill-down vers Bilan du mois

### Récurrents
- Liste des templates actifs/inactifs
- Toggle actif/inactif
- Tap → éditer, swipe → supprimer
- FAB → nouveau

### Foyers
- Liste des foyers (local + serveur si connecté)
- Créer nouveau foyer
- Switcher de foyer actif
- Si connecté : inviter un membre, voir membres

### Paramètres
- Compte (connexion / déconnexion serveur)
- Foyers
- Thème (dark/light)
- Devise (€ par défaut)

---

## Stack technique recommandée

| Composant | Choix | Raison |
|---|---|---|
| UI | SwiftUI | Natif, moderne |
| Données locales | SwiftData | Natif iOS 17+, remplace CoreData |
| Réseau | URLSession + async/await | Standard, pas de dépendance |
| Auth tokens | Keychain via KeychainAccess | Stockage sécurisé |
| Graphiques | Swift Charts | Natif iOS 16+, intégré SwiftUI |
| Minimum iOS | iOS 17 | SwiftData requis |

---

## Seed catégories embarqué (fallback offline)

Catégories système (isSystem = true) à inclure dans l'app bundle en JSON :

```json
[
  { "id": "...", "name": "Alimentation", "emoji": "🍎", "subcategories": [
    { "name": "Courses", "emoji": "🛒" },
    { "name": "Restaurants", "emoji": "🍽️" }
  ]},
  { "id": "...", "name": "Transport", "emoji": "🚗", "subcategories": [
    { "name": "Carburant", "emoji": "⛽" },
    { "name": "Transports en commun", "emoji": "🚇" }
  ]},
  { "id": "...", "name": "Logement", "emoji": "🏠", "subcategories": [
    { "name": "Loyer", "emoji": "🔑" },
    { "name": "Charges", "emoji": "💡" }
  ]},
  { "id": "...", "name": "Santé", "emoji": "🏥" },
  { "id": "...", "name": "Loisirs", "emoji": "🎮" },
  { "id": "...", "name": "Vêtements", "emoji": "👕" },
  { "id": "...", "name": "Épargne", "emoji": "💰" },
  { "id": "...", "name": "Autres", "emoji": "📦" }
]
```

Le seed réel sera complété depuis le serveur au premier lancement avec connexion.

---

## Priorité de développement (phases)

### Phase 1 — Local-only MVP
1. SwiftData schema + seed catégories
2. Dashboard + navigation principale
3. Vue Transactions unifiée (CRUD dépenses + revenus, `TransactionItem` enum)
4. Budget mensuel (lecture + édition)
5. Bilan (budget vs réel)

### Phase 2 — Récurrents & Historique
1. CRUD Récurrents + génération mensuelle automatique
2. Historique avec graphiques
3. Duplication dépense/revenu

### Phase 3 — Mode connecté
1. Auth (email + Apple + Google)
2. Sync catégories (one-shot)
3. Upload foyer local → serveur
4. Pull/push données (mois courant)
5. Gestion membres + invitations
