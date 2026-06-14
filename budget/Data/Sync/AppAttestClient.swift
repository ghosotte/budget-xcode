import CryptoKit
import DeviceCheck
import Foundation

enum AppAttestError: LocalizedError {
    case unsupported
    case serverRejected(String)

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "App Attest n'est pas disponible sur cet appareil."
        case .serverRejected(let message):
            return message
        }
    }
}

final class AppAttestClient: Sendable {
    static let shared = AppAttestClient()

    private static let keyIdKey = "attest.keyId"
    private static let attestedKey = "attest.confirmed"

    private init() {}

    var isAttested: Bool {
        KeychainStore.get(Self.attestedKey) == "1" && KeychainStore.get(Self.keyIdKey) != nil
    }

    func ensureAttested() async throws {
        guard !isAttested else { return }
        guard DCAppAttestService.shared.isSupported else { throw AppAttestError.unsupported }

        let challenge = try await fetchChallenge()
        let keyId = try await DCAppAttestService.shared.generateKey()
        let clientDataHash = Data(SHA256.hash(data: Data(challenge.utf8)))
        let attestation = try await DCAppAttestService.shared.attestKey(keyId, clientDataHash: clientDataHash)

        try await registerAttestation(keyId: keyId, attestation: attestation, challenge: challenge)

        KeychainStore.set(keyId, for: Self.keyIdKey)
        KeychainStore.set("1", for: Self.attestedKey)
    }

    var keyId: String? {
        KeychainStore.get(Self.keyIdKey)
    }

    func assertionHeaders(method: String, path: String, query: String, body: Data?) async throws -> [String: String] {
        try await ensureAttested()
        return try await buildAssertionHeaders(method: method, path: path, query: query, body: body, allowRetry: true)
    }

    private func buildAssertionHeaders(method: String, path: String, query: String, body: Data?, allowRetry: Bool) async throws -> [String: String] {
        guard let keyId = KeychainStore.get(Self.keyIdKey) else { throw AppAttestError.unsupported }

        // Canonical hash: sha256Hex( METHOD + "\n" + path + "\n" + rawQuery + "\n" + sha256Hex(body) )
        let bodyHashHex = Self.sha256Hex(body ?? Data())
        let canonical = "\(method)\n\(path)\n\(query)\n\(bodyHashHex)"
        let hash = Data(SHA256.hash(data: Data(canonical.utf8)))

        do {
            let assertion = try await DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: hash)
            return [
                "X-Key-Id": keyId,
                "X-App-Assertion": assertion.base64EncodedString(),
                "X-Client-Data-Hash": hash.map { String(format: "%02x", $0) }.joined(),
            ]
        } catch let error as DCError where error.code == .invalidInput && allowRetry {
            // Stale keyId after app reinstall — Secure Enclave key was purged. Re-attest.
            reset()
            try await ensureAttested()
            return try await buildAssertionHeaders(method: method, path: path, query: query, body: body, allowRetry: false)
        }
    }

    private static func sha256Hex(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).map { String(format: "%02x", $0) }.joined()
    }

    func reset() {
        KeychainStore.delete(Self.keyIdKey)
        KeychainStore.delete(Self.attestedKey)
    }

    // MARK: — Bootstrap calls (no auth, no assertion)

    private func fetchChallenge() async throws -> String {
        struct ChallengeResponse: Decodable {
            let success: Bool
            let challenge: String?
            let error: String?
        }

        let payload = [
            "application_code": APIConfig.applicationCode,
            "installation_id": APIConfig.installationId,
        ]
        let response: ChallengeResponse = try await postJSON(path: "/mobile/security/challenge", payload: payload)
        guard response.success, let challenge = response.challenge else {
            throw AppAttestError.serverRejected(response.error ?? "Challenge refusé par le serveur.")
        }
        return challenge
    }

    private func registerAttestation(keyId: String, attestation: Data, challenge: String) async throws {
        struct AttestResponse: Decodable {
            let success: Bool
            let error: String?
        }

        let payload = [
            "application_code": APIConfig.applicationCode,
            "installation_id": APIConfig.installationId,
            "key_id": keyId,
            "attestation": attestation.base64EncodedString(),
            "challenge": challenge,
        ]
        let response: AttestResponse = try await postJSON(path: "/mobile/security/attest", payload: payload)
        guard response.success else {
            throw AppAttestError.serverRejected(response.error ?? "Attestation refusée par le serveur.")
        }
    }

    private func postJSON<T: Decodable>(path: String, payload: [String: String]) async throws -> T {
        var request = URLRequest(url: APIConfig.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
