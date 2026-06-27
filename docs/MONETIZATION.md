# Plan de monétisation

> Proposition de stratégie de monétisation et de découpage par tiers utilisateurs.

## Principe de découpage

Trois barrières naturelles, alignées sur la techno :

1. **Local pur** (offline, zéro compte) → marche sans backend. Coût serveur = 0.
2. **Cloud** (nécessite login) → foyer partagé, sync multi-device, récurrences. Coût serveur réel.
3. **Premium** (cloud + paiement) → fonctions à forte valeur + déplafonnement des limites.

Règle : ne jamais mettre derrière login ce qui peut rester local. Le login doit débloquer une **valeur ressentie** (partage, multi-device), pas brider l'usage solo.

## Tableau des 3 tiers

| Domaine | Non connecté (gratuit) | Connecté (gratuit) | Connecté payant (Premium) |
|---|---|---|---|
| Transactions | ✅ illimité local | ✅ + sync | ✅ |
| Catégories | ✅ par défaut | ✅ | ✅ custom illimitées |
| Budget / lignes | ✅ mois courant | ✅ | ✅ |
| Dashboard / Bilan | ✅ basique | ✅ | ✅ avancé (tendances, projections) |
| Search | ✅ local | ✅ | ✅ |
| History | ✅ 3 mois local | ✅ cloud limité | ✅ illimité |
| **Récurrences** | ❌ (impossible sans backend) | ⚠️ 1-2 max | ✅ illimitées |
| **Foyer partagé** | ❌ | ⚠️ 1 invité | ✅ membres illimités |
| **Multi-device sync** | ❌ | ✅ | ✅ |
| Notifications push | ❌ | ✅ basiques | ✅ + alertes dépassement |
| Export (CSV/PDF) | ❌ | ⚠️ CSV simple | ✅ PDF + comptable |

Légende : ✅ inclus · ⚠️ limité · ❌ absent.

### Logique de conversion

- **Non connecté → connecté** : déclencheur = « je veux récurrences / 2e appareil / partager avec conjoint ».
- **Connecté → payant** : déclencheur = limites atteintes (récurrences, membres foyer, historique).

## Roadmap features à venir (par tier cible)

### Gratuit (acquisition / rétention)
- Widgets iOS (solde, budget restant) — local
- « Score budget » mensuel
- Import relevé bancaire CSV manuel

### Connecté gratuit (active le compte)
- Sync de base
- 1 récurrence + 1 invité (teaser premium)
- Catégories partagées dans le foyer

### Premium (la valeur payante)
- Récurrences illimitées + règles avancées (proratisation, fin de série)
- Foyer multi-membres + permissions (lecture/écriture)
- Projections & prévisionnel (« à ce rythme, fin de mois = X »)
- Alertes intelligentes (dépassement catégorie, facture à venir)
- Export comptable PDF/Excel
- Multi-foyers (perso + colocation + pro)
- Connexion bancaire automatique (Open Banking — type Bridge/Powens) ← gros argument premium

## Modèle économique

**Abonnement** (pas achat unique) — coûts serveur récurrents = revenu récurrent.

- Mensuel ~3,99 € · Annuel ~29,99 € (économie ~40 % pousse l'annuel).
- **Free trial 7-14 j** sur l'annuel (StoreKit 2).
- Pas de freemium agressif : le gratuit doit rester confortable en solo, sinon mauvaise note App Store.

### Placement paywall (non bloquant)
- Au tap sur feature premium (récurrence #2, invité #2).
- Pas de paywall au lancement (tue l'onboarding).

## Implémentation technique

```
Entitlement (source de vérité) :
  StoreKit 2 → Transaction.currentEntitlements
  → flag local `isPremium` (cache Keychain/UserDefaults)
  → vérif côté backend à la session (App Attest déjà dispo)

Feature gating :
  enum Feature { recurring, sharedHousehold, export, ... }
  func can(_ f: Feature) -> Bool  // selon tier
```

- Backend valide le reçu (App Store Server Notifications v2) → marque le foyer cloud comme premium. Évite le partage de compte premium entre foyers.
- Limites (récurrences = 1, membres = 1) = constantes serveur, modifiables sans update app.
- `AuthSession` existe déjà → ajouter `tier` au `/me`.

## Décisions à trancher

1. Prix exacts mensuel / annuel.
2. Agressivité du tier gratuit (limites précises).
3. Open Banking : oui / non (coût API vs argument de vente fort).
