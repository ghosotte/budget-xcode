import AuthenticationServices
import GoogleSignIn
import SwiftData
import SwiftUI
import UIKit
import BudgetKit

struct LoginView: View {
    private enum Mode: String, CaseIterable {
        case login, register

        var label: String {
            switch self {
            case .login:    return NSLocalizedString("Connexion", comment: "")
            case .register: return NSLocalizedString("Inscription", comment: "")
            }
        }

        var eyebrow: String? {
            switch self {
            case .login:    return NSLocalizedString("CONNEXION", comment: "")
            case .register: return nil
            }
        }

        var title: String {
            switch self {
            case .login:    return NSLocalizedString("Bon retour", comment: "")
            case .register: return NSLocalizedString("Créez votre compte", comment: "")
            }
        }

        var actionTitle: String {
            switch self {
            case .login:    return NSLocalizedString("Se connecter", comment: "")
            case .register: return NSLocalizedString("Créer mon compte", comment: "")
            }
        }
    }

    @Environment(AuthSession.self) private var session
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

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
                GoogleLogo()
                    .frame(width: 22, height: 22)
                    .frame(width: 56, height: 56)
                    .background(googleButtonBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(googleButtonBorder, lineWidth: 1)
                    }
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

    private var googleButtonBackground: Color {
        colorScheme == .dark ? Color(hex: "#131314") : Color(hex: "#FFFFFF")
    }

    private var googleButtonBorder: Color {
        colorScheme == .dark ? Color(hex: "#8E918F") : Color(hex: "#747775")
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
            errorMessage = NSLocalizedString("Client OAuth iOS Google manquant dans Info.plist.", comment: "")
            return
        }

        guard let presentingViewController = UIApplication.shared.keyWindowRootViewController else {
            errorMessage = NSLocalizedString("Impossible d'ouvrir la connexion Google.", comment: "")
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
                    errorMessage = NSLocalizedString("Google n'a pas renvoyé d'id token.", comment: "")
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
            try await SyncEngineProvider.shared(modelContext.container).pullCategories()
            try? modelContext.save()
        } catch {
            errorMessage = String(format: NSLocalizedString("Connecté, mais la synchronisation a échoué : %@", comment: ""), error.localizedDescription)
        }
        // Foyer actif = local `isDefault` (peut différer du foyer cloud) → applique ses settings.
        if let active = (try? modelContext.fetch(FetchDescriptor<Household>()))?.first(where: \.isDefault) {
            Currency.setActive(active.currencyCode)
            AppLocale.setActive(active.locale)
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

private struct GoogleLogo: View {
    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let offset = CGPoint(
                x: (size.width - side) / 2,
                y: (size.height - side) / 2
            )
            let transform = CGAffineTransform(translationX: offset.x, y: offset.y)
                .scaledBy(x: side / 48, y: side / 48)

            context.fill(GoogleLogoPath.red.applying(transform), with: .color(Color(hex: "#EA4335")))
            context.fill(GoogleLogoPath.blue.applying(transform), with: .color(Color(hex: "#4285F4")))
            context.fill(GoogleLogoPath.yellow.applying(transform), with: .color(Color(hex: "#FBBC05")))
            context.fill(GoogleLogoPath.green.applying(transform), with: .color(Color(hex: "#34A853")))
        }
        .accessibilityHidden(true)
    }
}

private enum GoogleLogoPath {
    static var red: Path {
        var path = Path()
        path.move(to: CGPoint(x: 24, y: 9.5))
        path.addCurve(to: CGPoint(x: 33.21, y: 13.1), control1: CGPoint(x: 27.54, y: 9.5), control2: CGPoint(x: 30.71, y: 10.72))
        path.addLine(to: CGPoint(x: 40.06, y: 6.25))
        path.addCurve(to: CGPoint(x: 24, y: 0), control1: CGPoint(x: 35.9, y: 2.38), control2: CGPoint(x: 30.47, y: 0))
        path.addCurve(to: CGPoint(x: 2.56, y: 13.22), control1: CGPoint(x: 14.62, y: 0), control2: CGPoint(x: 6.51, y: 5.38))
        path.addLine(to: CGPoint(x: 10.54, y: 19.41))
        path.addCurve(to: CGPoint(x: 24, y: 9.5), control1: CGPoint(x: 12.43, y: 13.72), control2: CGPoint(x: 17.74, y: 9.5))
        path.closeSubpath()
        return path
    }

    static var blue: Path {
        var path = Path()
        path.move(to: CGPoint(x: 46.98, y: 24.55))
        path.addCurve(to: CGPoint(x: 46.6, y: 20), control1: CGPoint(x: 46.98, y: 22.98), control2: CGPoint(x: 46.83, y: 21.46))
        path.addLine(to: CGPoint(x: 24, y: 20))
        path.addLine(to: CGPoint(x: 24, y: 29.02))
        path.addLine(to: CGPoint(x: 36.94, y: 29.02))
        path.addCurve(to: CGPoint(x: 32.16, y: 36.2), control1: CGPoint(x: 36.36, y: 31.98), control2: CGPoint(x: 34.68, y: 34.5))
        path.addLine(to: CGPoint(x: 39.89, y: 42.2))
        path.addCurve(to: CGPoint(x: 46.98, y: 24.55), control1: CGPoint(x: 44.4, y: 38.02), control2: CGPoint(x: 46.98, y: 31.84))
        path.closeSubpath()
        return path
    }

    static var yellow: Path {
        var path = Path()
        path.move(to: CGPoint(x: 10.53, y: 28.59))
        path.addCurve(to: CGPoint(x: 9.77, y: 24), control1: CGPoint(x: 10.05, y: 27.14), control2: CGPoint(x: 9.77, y: 25.6))
        path.addCurve(to: CGPoint(x: 10.53, y: 19.41), control1: CGPoint(x: 9.77, y: 22.4), control2: CGPoint(x: 10.04, y: 20.86))
        path.addLine(to: CGPoint(x: 2.55, y: 13.22))
        path.addCurve(to: CGPoint(x: 0, y: 24), control1: CGPoint(x: 0.92, y: 16.46), control2: CGPoint(x: 0, y: 20.12))
        path.addCurve(to: CGPoint(x: 2.56, y: 34.78), control1: CGPoint(x: 0, y: 27.88), control2: CGPoint(x: 0.92, y: 31.54))
        path.addLine(to: CGPoint(x: 10.53, y: 28.59))
        path.closeSubpath()
        return path
    }

    static var green: Path {
        var path = Path()
        path.move(to: CGPoint(x: 24, y: 48))
        path.addCurve(to: CGPoint(x: 39.89, y: 42.19), control1: CGPoint(x: 30.48, y: 48), control2: CGPoint(x: 35.93, y: 45.87))
        path.addLine(to: CGPoint(x: 32.16, y: 36.19))
        path.addCurve(to: CGPoint(x: 24, y: 38.49), control1: CGPoint(x: 30.01, y: 37.64), control2: CGPoint(x: 27.24, y: 38.49))
        path.addCurve(to: CGPoint(x: 10.53, y: 28.58), control1: CGPoint(x: 17.74, y: 38.49), control2: CGPoint(x: 12.43, y: 34.27))
        path.addLine(to: CGPoint(x: 2.55, y: 34.77))
        path.addCurve(to: CGPoint(x: 24, y: 48), control1: CGPoint(x: 6.51, y: 42.62), control2: CGPoint(x: 14.62, y: 48))
        path.closeSubpath()
        return path
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
