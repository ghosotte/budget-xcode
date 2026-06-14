import Foundation

enum APIConfig {
    static let applicationCode = "budget"

    static var baseURL: URL {
        // Manual override (debug menu): UserDefaults `apiBaseURL`.
        if let raw = UserDefaults.standard.string(forKey: "apiBaseURL"), let url = URL(string: raw) {
            return url
        }
        // Build-time config from Info.plist (API_BASE_URL via xcconfig).
        if let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           !raw.isEmpty,
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://api.theapp.fr")!
    }

    static var installationId: String {
        if let existing = UserDefaults.standard.string(forKey: "installationId") {
            return existing
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: "installationId")
        return new
    }
}
