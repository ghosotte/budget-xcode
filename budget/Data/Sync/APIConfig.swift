import Foundation

enum APIConfig {
    static let applicationCode = "budget"

    static var baseURL: URL {
        if let raw = UserDefaults.standard.string(forKey: "apiBaseURL"), let url = URL(string: raw) {
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
