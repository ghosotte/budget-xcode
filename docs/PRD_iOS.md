# PRD — Budget iOS

## 1. Résumé

Budget est une application iOS native de gestion budgétaire personnelle et familiale. Le produit permet de suivre ses revenus, ses dépenses, son budget mensuel, son historique et ses foyers, avec un fonctionnement local-first par défaut et une synchronisation cloud optionnelle.

L'utilisateur doit pouvoir utiliser l'application sans compte pour un usage solo sur un appareil. Le compte cloud ajoute la valeur serveur : synchronisation multi-appareil, foyer partagé, recherche cloud, historique agrégé et dépenses récurrentes générées côté backend.

## 2. Objectifs produit

- Donner une vision claire du mois : revenus, dépenses, solde, budget prévu et réel.
- Permettre la saisie rapide des transactions et des lignes budgétaires.
- Fonctionner hors ligne sans bloquer les usages essentiels.
- Synchroniser de façon fiable les données d'un foyer cloud quand l'utilisateur est connecté.
- Préparer une monétisation progressive autour des fonctionnalités qui ont un coût serveur ou une forte valeur : récurrences, partage, historique avancé, exports, notifications.

## 3. Non-objectifs V1

- Import bancaire automatique.
- Import CSV massif.
- Catégories personnalisées éditables par l'utilisateur.
- Analyse IA ou coaching financier avancé.
- Gestion d'épargne, crédits, patrimoine ou comptabilité professionnelle.
- Synchronisation temps réel collaborative.

## 4. Utilisateurs cibles

### Utilisateur solo local

Veut suivre son budget mensuel sans créer de compte. Toutes ses données restent sur l'appareil. Il peut gérer ses transactions, budgets, bilans, foyers locaux et paramètres.

### Utilisateur multi-appareil

Veut retrouver son budget sur plusieurs appareils. Il crée un compte et utilise un foyer cloud. Les modifications locales sont envoyées au serveur et récupérées sur les autres appareils.

### Foyer partagé

Couple, colocation ou famille qui veut gérer un budget commun. Le serveur devient nécessaire pour gérer les membres, invitations, droits d'accès et données communes.

## 5. Proposition de valeur

- Saisie locale rapide et disponible hors ligne.
- Vision mensuelle simple : prévu vs réel.
- Séparation claire entre dépenses et revenus.
- Foyers multiples pour séparer les contextes de budget.
- Cloud optionnel, non obligatoire pour l'usage de base.
- Récurrences gérées par le backend afin de garantir une génération cohérente entre appareils.

## 6. Périmètre fonctionnel iOS

### Dashboard

Le dashboard est l'écran d'accueil. Il affiche le foyer actif, les indicateurs du mois courant, le solde, les totaux de dépenses et revenus, les transactions récentes, les opérations à venir et un accès aux récurrences.

Responsabilités iOS :

- Calculer et afficher les agrégats locaux du mois actif.
- Afficher les données SwiftData disponibles immédiatement.
- Déclencher un rafraîchissement mensuel si le foyer actif est cloud.
- Afficher les erreurs de synchronisation via une bannière utilisateur.

### Transactions

L'utilisateur peut consulter, créer, modifier, supprimer et dupliquer des dépenses et revenus.

Responsabilités iOS :

- Enregistrer immédiatement la mutation dans SwiftData.
- Marquer l'entité `pendingUpload` si le foyer est cloud.
- Tenter le push après modification.
- Garder les entités en attente si le réseau est indisponible.
- Fusionner dépenses et revenus dans une liste unique côté UI.

Règles :

- Une dépense est stockée avec un montant positif mais affichée comme sortie.
- Un revenu est stocké avec un montant positif et affiché comme entrée.
- Le mois effectif est `accountingMonth` si renseigné, sinon le mois de la date de transaction.
- Le statut réel/prévu est dérivé de la date par rapport à aujourd'hui.

### Budget mensuel

L'utilisateur définit des lignes budgétaires de dépenses et de revenus.

Responsabilités iOS :

- Afficher les lignes actives pour le mois sélectionné.
- Créer et modifier les lignes localement.
- Gérer les fréquences `monthly` et `punctual`.
- Appliquer les règles de modification par portée : ce mois seulement ou à partir de ce mois.
- Synchroniser les lignes cloud via le backend.

### Bilan

Le bilan compare le budget prévu au réel.

Responsabilités iOS :

- Calculer localement les écarts à partir des données disponibles.
- Présenter les totaux revenus, dépenses et solde.
- Afficher le détail par catégorie et sous-catégorie.

### Historique

L'historique donne une vue agrégée sur plusieurs mois.

Responsabilités iOS :

- Afficher les mois disponibles localement pour les foyers locaux.
- Utiliser l'endpoint d'historique agrégé pour les foyers cloud.
- Permettre la navigation vers un mois précis.

### Recherche

La recherche permet de retrouver des transactions.

Responsabilités iOS :

- Résoudre les résultats serveur vers les modèles SwiftData locaux quand ils existent.
- Limiter les actions d'édition/suppression aux transactions présentes localement.
- Permettre la duplication locale d'une transaction existante.

### Récurrences

Les récurrences sont des templates de dépenses récurrentes.

Responsabilités iOS :

- Afficher les templates synchronisés depuis le backend.
- Permettre la création, modification, suppression et activation uniquement sur un foyer cloud actif.
- Bloquer la création sur un foyer local, même si l'utilisateur est connecté.
- Ne jamais générer localement les transactions issues des récurrences.
- Purger les anciennes dépenses générées localement sans `serverId`, issues d'anciens comportements.

Responsabilité backend :

- Être source de vérité des templates récurrents.
- Générer les dépenses mensuelles associées.
- Garantir l'idempotence : une même récurrence ne doit pas générer deux dépenses pour le même mois.

### Foyers

L'application supporte plusieurs foyers.

Responsabilités iOS :

- Maintenir un foyer actif via `isDefault`.
- Permettre le switch entre foyers locaux et cloud.
- Créer des foyers locaux sans compte.
- Créer, renommer, supprimer ou migrer des foyers cloud quand l'utilisateur est connecté.
- Appliquer la devise et la langue du foyer actif.

Règles :

- Un foyer local n'a pas de `serverId` ni `ownerUserId`.
- Un foyer cloud a un `serverId`, un `ownerUserId` et correspond au foyer courant du token.
- Un foyer orphelin est conservé mais ne doit pas recevoir de mutations cloud.

### Compte et authentification

Responsabilités iOS :

- Gérer connexion email/mot de passe, Google Sign-In et Sign in with Apple.
- Stocker les tokens dans le Keychain.
- Rafraîchir le token d'accès.
- Déconnecter proprement l'utilisateur et conserver un foyer local utilisable.
- Migrer un foyer local vers le cloud à la demande.

## 7. Architecture front iOS

Le front est une application native iOS 17+ en SwiftUI et SwiftData.

### Couches

- `Domain/` : modèles SwiftData (`Household`, `Expense`, `IncomeEntry`, `RecurringExpense`, catégories, lignes budgétaires).
- `Data/` : services locaux, seed de catégories, sync, API, App Attest, migration, push queue.
- `Presentation/` : vues SwiftUI par domaine fonctionnel.

### Principes

- Local-first : toute mutation utilisateur écrit d'abord dans SwiftData.
- UI réactive : les `@Query` SwiftData alimentent directement les vues.
- Sync opportuniste : le push est tenté après modification, au retour réseau, au premier plan et au lancement.
- Source cloud conditionnelle : seuls les foyers cloud sont synchronisés.
- Pas de blocage réseau pour les usages locaux.

### Stockage local

SwiftData est la base de travail du front. Elle contient :

- foyers et membres ;
- catégories et sous-catégories ;
- transactions ;
- lignes budgétaires ;
- templates récurrents synchronisés ;
- statuts de sync.

Les catégories ont un seed embarqué pour que l'application fonctionne sans réseau.

## 8. Responsabilités backend

Le backend est l'API Budget exposée sous `https://api.theapp.fr` avec le code applicatif `budget`. Le dépôt backend référencé est `/Users/gui/Projects/symfony/theApp`, branche `API-budget`.

Le backend est responsable de tout ce qui nécessite une source de vérité partagée, de la sécurité serveur ou une génération déterministe multi-appareil.

### Authentification

Le backend doit fournir :

- inscription ;
- connexion email/mot de passe ;
- connexion Google ;
- connexion Apple ;
- refresh token ;
- logout ;
- endpoint `/me`.

Il doit émettre des access tokens courts et des refresh tokens rotatifs. Les tokens sont liés à l'installation mobile et protégés par App Attest.

### Foyers cloud

Le backend doit :

- lister les foyers accessibles à l'utilisateur ;
- créer, renommer, supprimer un foyer ;
- gérer la devise et la langue ;
- gérer les membres ;
- gérer les invitations et leur acceptation ;
- gérer le switch de foyer courant.

Le foyer courant côté token doit correspondre au foyer cloud actif côté iOS pour autoriser les mutations.

### Synchronisation des données

Le backend doit exposer les données par foyer et par mois quand c'est pertinent :

- transactions ;
- lignes budgétaires ;
- catégories ;
- catégories de revenus ;
- récurrences ;
- historique agrégé ;
- recherche.

Le backend doit renvoyer des `serverId` stables afin que l'app puisse réconcilier les entités locales.

### Récurrences

Les récurrences sont backend-first.

Le backend doit :

- créer, modifier, supprimer et activer/désactiver les templates ;
- générer les dépenses mensuelles associées ;
- éviter les doublons ;
- renvoyer les dépenses générées dans les pulls mensuels ;
- rester la source de vérité si plusieurs appareils sont connectés.

### Sécurité

Le backend doit vérifier :

- les Bearer tokens ;
- l'accès au foyer demandé ;
- les assertions App Attest ;
- l'association entre utilisateur, installation et foyer courant ;
- les droits d'écriture avant toute mutation.

### Observabilité backend attendue

Le backend doit journaliser :

- erreurs d'authentification ;
- erreurs App Attest ;
- mutations de foyers ;
- erreurs de sync ;
- génération des récurrences ;
- conflits ou entités inconnues lors des pushs.

## 9. Contrats API principaux

Routes utilisées ou attendues par l'app :

| Domaine | Routes |
|---|---|
| Auth | `/budget/auth/register`, `/budget/auth/login`, `/budget/auth/google`, `/budget/auth/apple`, `/budget/auth/refresh`, `/budget/auth/logout`, `/budget/auth/me` |
| Foyers | `/budget/households`, `/budget/households/{id}`, `/budget/auth/switch-household`, `/budget/household/import`, `/budget/household/import-new` |
| Invitations | `/budget/household/invite`, `/budget/household/invitations`, `/budget/household/invite/accept`, `/budget/household/invitations/{id}/revoke` |
| Catégories | `/budget/categories`, `/budget/income-categories` |
| Transactions | `/budget/transactions`, `/budget/transactions/{id}`, `/budget/transactions/search` |
| Budget | `/budget/budget`, `/budget/budget/expense-lines`, `/budget/budget/expense-lines/{id}`, `/budget/budget/income-lines`, `/budget/budget/income-lines/{id}` |
| Récurrences | `/budget/recurring`, `/budget/recurring/{id}`, `/budget/recurring/{id}/toggle` |
| Historique | `/budget/history/overview` |

## 10. Synchronisation

### Déclencheurs iOS

| Déclencheur | Comportement |
|---|---|
| Lancement à froid | bootstrap session, catégories, foyers, push pending |
| Connexion | récupération des foyers cloud et données de base |
| Retour réseau | `quickSync` et push des opérations en attente |
| Retour premier plan | sync légère si délai suffisant |
| Sauvegarde formulaire | mutation locale puis tentative de push |
| Affichage mois | pull transactions + budget lines du mois |
| Affichage récurrences | pull templates récurrents si foyer cloud |

### Statuts de sync

- `local` : donnée locale-only, jamais envoyée.
- `synced` : donnée alignée avec le serveur.
- `pendingUpload` : donnée créée ou modifiée localement, à pousser.
- `pendingDelete` : donnée supprimée localement, suppression serveur en attente.

### Règles d'échec

- Hors ligne : garder l'opération en attente.
- Erreur 5xx : garder l'opération et réessayer plus tard.
- Erreur 4xx : considérer l'opération invalide ou non autorisée selon le cas et éviter une boucle infinie.
- 401 après refresh : invalider la session locale et revenir à un foyer local.

## 11. Exigences UX

- L'application doit rester utilisable sans compte.
- Les actions principales doivent être accessibles en peu de taps.
- Les erreurs de sync doivent être visibles mais non bloquantes pour les foyers locaux.
- Les actions impossibles sur foyer local doivent être explicitement bloquées, notamment les récurrences.
- La langue, la devise et les formats doivent suivre le foyer actif.
- Le nom de l'application affiché sur iOS doit être `Budget`.

## 12. Exigences non fonctionnelles

- iOS 17 minimum.
- SwiftUI et SwiftData.
- Stockage local fiable.
- App Attest pour les appels authentifiés.
- Tokens en Keychain.
- Logs `os_log` pour auth, sync, data, UI et attest.
- MetricKit activé pour diagnostiquer les problèmes post-déploiement.
- Pas de dépendance au réseau pour les écrans local-first.

## 13. Monétisation envisagée

Le modèle cible est freemium :

- Gratuit local : transactions, budget, dashboard, foyers locaux.
- Gratuit connecté : sync de base, partage limité, récurrences limitées.
- Premium : récurrences illimitées, membres supplémentaires, historique avancé, exports, alertes et fonctionnalités cloud coûteuses.

Le paywall ne doit pas bloquer l'onboarding. Il doit apparaître au moment où l'utilisateur atteint une limite ou demande une fonctionnalité premium.

## 14. Indicateurs de succès

- Taux de création d'une première transaction.
- Taux de création d'une première ligne budget.
- Rétention J7 et J30.
- Nombre moyen de mois consultés.
- Taux de connexion après usage local.
- Taux de migration local vers cloud.
- Taux d'échec sync.
- Nombre d'opérations `pendingUpload` âgées de plus de 24h.
- Usage des récurrences sur foyers cloud.

## 15. Risques

- Divergence entre modèle local et modèle backend.
- Données en attente non poussées si les règles de retry sont insuffisantes.
- Confusion utilisateur entre foyer local et foyer cloud.
- Doublons si la génération des récurrences n'est pas strictement idempotente côté backend.
- Perte de confiance si la sync échoue silencieusement.

## 16. Décisions produit actées

- L'application fonctionne sans compte.
- Le cloud est optionnel mais requis pour le partage, le multi-device et les récurrences.
- Les récurrences ne sont pas créées sur un foyer local.
- Les dépenses issues de récurrences sont générées par le backend, pas par iOS.
- Le foyer actif pilote les écrans, la devise et la langue.
- Le front garde une copie locale des données cloud pour l'affichage rapide et l'usage partiellement offline.

## 17. Questions ouvertes

- Limites exactes du tier gratuit connecté : nombre de récurrences, membres, historique.
- Politique de résolution de conflit détaillée en cas d'édition simultanée multi-device.
- Niveau de permissions par membre de foyer.
- Stratégie de notifications push pour les factures à venir et dépassements budget.
- Format et périmètre des exports Premium.
