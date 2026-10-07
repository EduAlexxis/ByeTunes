import Foundation

struct Config {
    static let byeTunesApiUrl: String = {
        if let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path),
           let url = dict["ByeTunesApiUrl"] as? String {
            return url
        }
        return "https://127.0.0.1"
    }()
    
    static let byeTunesApiHost: String = {
        return URL(string: byeTunesApiUrl)?.host ?? ""
    }()

    static let downloadBackendLabel = "Download Server"
}
