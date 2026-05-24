import Foundation

public enum LocalhostCORS {
    public static func isValidBrowserOrigin(_ origin: String) -> Bool {
        guard !origin.isEmpty, origin != "null" else { return false }
        guard let components = URLComponents(string: origin),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty
        else {
            return false
        }
        guard scheme == "http" || scheme == "https" else { return false }
        guard components.user == nil, components.password == nil else { return false }
        guard components.path.isEmpty, components.query == nil, components.fragment == nil else { return false }
        if let port = components.port, port < 0 || port > 65_535 {
            return false
        }
        return components.url?.absoluteString == origin
    }
}
