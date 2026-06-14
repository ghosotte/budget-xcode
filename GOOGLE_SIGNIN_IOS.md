# Configuration Google Sign-In iOS

Ce projet utilise `GoogleSignIn-iOS` pour obtenir un `id_token` Google, puis l'envoie au backend Symfony via `POST /budget/auth/google`.

## Valeurs du projet

- Bundle ID iOS : `com.guilhemhosotte.budget`
- `GIDClientID` : `121213499962-k5r7nvfcamgusvotj0dftdhhrp42rp68.apps.googleusercontent.com`
- URL scheme iOS : `com.googleusercontent.apps.121213499962-k5r7nvfcamgusvotj0dftdhhrp42rp68`
- `GIDServerClientID` : `121213499962-uqsrq78q6v1c84jff4isqcdd13s4k6o2.apps.googleusercontent.com`
- Client serveur actuel : `121213499962-uqsrq78q6v1c84jff4isqcdd13s4k6o2.apps.googleusercontent.com`
- Fichier Google telecharge : `/Users/gui/Desktop/client_121213499962-k5r7nvfcamgusvotj0dftdhhrp42rp68.apps.googleusercontent.com.plist`

## Creer le client OAuth iOS

1. Ouvrir Google Cloud Console.
2. Aller dans **APIs & Services** > **Credentials**.
3. Cliquer **Create Credentials** > **OAuth client ID**.
4. Choisir le type d'application **iOS**.
5. Donner un nom explicite, par exemple `Budget iOS`.
6. Renseigner le Bundle ID exact :

```text
com.guilhemhosotte.budget
```

7. Creer le client.
8. Copier le **Client ID** iOS obtenu. Il ressemble a :

```text
1234567890-abcdef123456.apps.googleusercontent.com
```

9. Copier aussi le **iOS URL scheme** affiche par Google. Il ressemble a :

```text
com.googleusercontent.apps.1234567890-abcdef123456
```

## Mettre a jour `Info.plist`

`budget/Info.plist` est configure avec le client iOS :

```xml
<key>GIDClientID</key>
<string>121213499962-k5r7nvfcamgusvotj0dftdhhrp42rp68.apps.googleusercontent.com</string>
```

et le scheme inverse :

```xml
<string>com.googleusercontent.apps.121213499962-k5r7nvfcamgusvotj0dftdhhrp42rp68</string>
```

Conserver `GIDServerClientID` avec le client OAuth web/backend :

```xml
<key>GIDServerClientID</key>
<string>121213499962-uqsrq78q6v1c84jff4isqcdd13s4k6o2.apps.googleusercontent.com</string>
```

## Verifier le backend

Le backend Symfony valide actuellement le claim `aud` du token Google avec `GOOGLE_CLIENT_ID`.

Avec `GoogleSignIn-iOS` et `GIDServerClientID`, l'`id_token` envoye au backend doit avoir pour audience le client serveur. Si le backend renvoie `Invalid Google token`, verifier :

1. `GIDServerClientID` dans `budget/Info.plist`.
2. `GOOGLE_CLIENT_ID` dans l'environnement Symfony.
3. Que les deux valeurs sont identiques.

## Tester

1. Nettoyer et builder l'app dans Xcode.
2. Lancer l'app sur simulateur ou appareil.
3. Aller dans **Reglages** > **Compte** > **Se connecter**.
4. Appuyer sur le bouton Google.
5. Completer le flow Google.
6. Verifier que l'app est connectee et que le backend renvoie bien les tokens budget.

## References

- Google Sign-In iOS setup : https://developers.google.com/identity/sign-in/ios/start-integrating
- OAuth 2.0 native apps : https://developers.google.com/identity/protocols/oauth2/native-app
