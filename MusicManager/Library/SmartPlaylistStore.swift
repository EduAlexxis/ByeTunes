import Foundation

struct SmartPlaylistRecord: Codable, Identifiable {
    var id: Int64 { containerPid }
    let name: String
    let containerPid: Int64
    let rule: SmartPlaylistRule
}

enum SmartPlaylistStore {
    private static let storageKey = "smartPlaylistRecords.v1"

    static func loadAll() -> [SmartPlaylistRecord] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SmartPlaylistRecord].self, from: data) else {
            return []
        }
        return decoded
    }

    static func record(forPid pid: Int64) -> SmartPlaylistRecord? {
        loadAll().first { $0.containerPid == pid }
    }

    static func save(_ record: SmartPlaylistRecord) {
        var all = loadAll().filter { $0.containerPid != record.containerPid }
        all.append(record)
        persist(all)
    }

    static func remove(forPid pid: Int64) {
        let all = loadAll().filter { $0.containerPid != pid }
        persist(all)
    }

    private static func persist(_ records: [SmartPlaylistRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
