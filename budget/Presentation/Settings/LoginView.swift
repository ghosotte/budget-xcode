import AuthenticationServices
import GoogleSignIn
import SwiftData
import SwiftUI
import UIKit

struct LoginView: View {
    private enum Mode: String, CaseIterable {
        case login, register

        var label: String {
            switch self {
            case .login:    return "Connexion"
            case .register: return "Inscription"
            }
        }

        var eyebrow: String? {
            switch self {
            case .login:    return "CONNEXION"
            case .register: return nil
            }
        }

        var title: String {
            switch self {
            case .login:    return "Bon retour"
            case .register: return "Créez votre compte"
            }
        }

        var actionTitle: String {
            switch self {
            case .login:    return "Se connecter"
            case .register: return "Créer mon compte"
            }
        }
    }

    @Environment(AuthSession.self) private var session
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var mode = Mode.login
    @State private var email = ""
    @State private var password = ""
    @State private var firstName = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var appleCoordinator: AppleSignInCoordinator?

    private var trimmedFirstName: String {
        firstName.trimmingCharacters(in: .whitespaces)
    }

    private var isValid: Bool {
        guard email.contains("@"), password.count >= 8 else { return false }
        guard mode == .register else { return true }
        return !trimmedFirstName.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                socialSignIn
                divider
                fields
                submitButton
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.budgetBg.ignoresSafeArea())
        .navigationTitle("Compte")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(isWorking)
        .tint(.budgetPrimary)
        .onChange(of: mode) {
            errorMessage = nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 6)

            if let eyebrow = mode.eyebrow {
                Text(eyebrow)
                    .font(.caption.weight(.medium))
                    .tracking(0.8)
                    .foregroundStyle(Color.budgetTextFaint)
            }

            Text(mode.title)
                .font(.system(size: 36, weight: .bold, design: .serif))
                .foregroundStyle(Color.budgetText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var socialSignIn: some View {
        HStack(spacing: 12) {
            Spacer()
            Button {
                startGoogleSignIn()
            } label: {
                Text("G")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color(hex: "#4285F4"))
                    .frame(width: 56, height: 56)
                    .background(Color.budgetSurfaceMute, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            .accessibilityLabel("Continuer avec Google")

            Button {
                startAppleSignIn()
            } label: {
                Image(systemName: "apple.logo")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.budgetText)
                    .frame(width: 56, height: 56)
                    .background(Color.budgetSurfaceMute, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            .accessibilityLabel("Continuer avec Apple")
            Spacer()
        }
    }

    private var divider: some View {
        HStack(spacing: 14) {
            Rectangle()
                .fill(Color.budgetBorder)
                .frame(height: 1)
            Text("OU")
                .font(.caption)
                .foregroundStyle(Color.budgetTextFaint)
            Rectangle()
                .fill(Color.budgetBorder)
                .frame(height: 1)
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 16) {
            AuthFieldLabel("Adresse email") {
                TextField("", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            if mode == .register {
                AuthFieldLabel("Prénom") {
                    TextField("", text: $firstName)
                        .textContentType(.givenName)
                }
            }

            AuthFieldLabel("Mot de passe") {
                SecureField("", text: $password)
                    .textContentType(mode == .login ? .password : .newPassword)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.budgetDanger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack {
                Spacer()
                if isWorking {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(mode.actionTitle)
                        .font(.body.weight(.semibold))
                }
                Spacer()
            }
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isValid && !isWorking ? Color.budgetPrimary : Color.budgetPrimary.opacity(0.45))
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(!isValid || isWorking)
    }

    private func startGoogleSignIn() {
        errorMessage = nil

        guard let clientID = Bundle.main.googleClientID else {
            errorMessage = "Client OAuth iOS Google manquant dans Info.plist."
            return
        }

        guard let presentingViewController = UIApplication.shared.keyWindowRootViewController else {
            errorMessage = "Impossible d'ouvrir la connexion Google."
            return
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: clientID,
            serverClientID: Bundle.main.googleServerClientID
        )

        isWorking = true
        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, error in
            Task { @MainActor in
                if let error {
                    isWorking = false
                    errorMessage = error.localizedDescription
                    return
                }

                guard let idToken = result?.user.idToken?.tokenString else {
                    isWorking = false
                    errorMessage = "Google n'a pas renvoyé d'id token."
                    return
                }

                await submitGoogle(idToken: idToken)
            }
        }
    }

    private func submitGoogle(idToken: String) async {
        do {
            try await session.loginWithGoogle(idToken: idToken)
            await postLoginSync()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func submit() async {
        isWorking = true
        errorMessage = nil
        do {
            if mode == .login {
                try await session.login(email: email, password: password)
            } else {
                try await session.register(
                    email: email,
                    password: password,
                    firstName: trimmedFirstName
                )
            }
            await postLoginSync()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func startAppleSignIn() {
        errorMessage = nil

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let coordinator = AppleSignInCoordinator { result in
            Task { @MainActor in
                await handleApple(result)
                appleCoordinator = nil
            }
        }
        appleCoordinator = coordinator

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = coordinator
        controller.presentationContextProvider = coordinator
        controller.performRequests()
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        guard case .success(let auth) = result,
              let credential = auth.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            if case .failure(let error) = result, (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
            return
        }

        isWorking = true
        errorMessage = nil
        do {
            try await session.loginWithApple(
                identityToken: identityToken,
                firstName: credential.fullName?.givenName
            )
            await postLoginSync()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func postLoginSync() async {
        do {
            try await SyncService.syncAll(session: session, context: modelContext)
            try await SyncService.pullCategories(context: modelContext)
            try? modelContext.save()
        } catch {
            errorMessage = "Connecté, mais la synchronisation a échoué : \(error.localizedDescription)"
        }
    }
}

private extension Bundle {
    var googleClientID: String? {
        let value = object(forInfoDictionaryKey: "GIDClientID") as? String
        guard let value, !value.hasPrefix("REPLACE_WITH_") else { return nil }
        return value
    }

    var googleServerClientID: String? {
        object(forInfoDictionaryKey: "GIDServerClientID") as? String
    }
}

private extension UIApplication {
    var keyWindowRootViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}

private struct AuthFieldLabel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.budgetTextMute)
            content
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.budgetSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.budgetBorder, lineWidth: 1)
                }
        }
    }
}

private final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let completion: (Result<ASAuthorization, Error>) -> Void

    init(completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.completion = completion
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        completion(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
