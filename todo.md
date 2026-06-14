
  1. Test de bout en bout (premier objectif)
  - Confirmer le domaine API réel → corriger APIConfig.baseURL si besoin
  - Vérifier que la migration est passée en prod (SELECT * FROM application WHERE code='budget')
  - Sur l'iPhone : Réglages → Compte → créer un compte. Ça déclenche le vrai flux App Attest (challenge → attestation → enregistrement), puis
  la première sync. Croiser avec le web : les données doivent apparaître des deux côtés
  - Points de friction probables au premier essai : attestation refusée (vérifier app_attest_allow_development=1 en prod tant que tu testes en
  build Xcode), et Sign in with Apple (capability à activer sur l'App ID dans le portail développeur + config Apple côté serveur — audience =
  bundle id)

  2. Fin du périmètre Phase 3 (dev restant)
  - Partage d'un foyer local : bouton "Partager ce foyer" → POST /budget/households + upload complet des données locales + bascule en foyer
  connecté (la migration locale → serveur du spec)
  - UI membres & invitations : écran membres du foyer serveur, génération de lien d'invitation, acceptation — endpoints prêts ; il y a même une
  doc universal links dans le repo Symfony (documentation/ios-budget-universal-links.md) pour ouvrir /invite/{token} directement dans l'app
  - Switch de foyer serveur : brancher /budget/auth/switch-household dans l'écran Foyers (aujourd'hui il ne gère que les foyers locaux)

  3. Durcissement avant TestFlight/App Store
  - Entitlement App Attest development → production + app_attest_allow_development=0 côté serveur
  - Nettoyer les entitlements hérités du template (CloudKit/aps non utilisés)
  - Icône, écran de lancement, archive TestFlight

  Je recommande de commencer par le 1 — il valide toute la chaîne avant d'investir dans le 2. Donne-moi le domaine réel et le résultat du
  premier login, et j'enchaîne.