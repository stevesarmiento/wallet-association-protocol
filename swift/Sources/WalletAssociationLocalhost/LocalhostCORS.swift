import Foundation

public enum LocalhostCORS {
    public static func isValidBrowserOrigin(_ origin: String) -> Bool {
        guard let url = URL(string: origin), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }
}
