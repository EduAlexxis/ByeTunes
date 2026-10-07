import Foundation
import Combine

struct BackendHealthRecord: Codable, Identifiable {
    var id: String { label }
    let label: String
    var lastOutcome: String
    var lastUpdatedAt: Date
    var successCount: Int
    var failureCount: Int
    var lastError: String?
}

@MainActor
final class BackendHealthStore: ObservableObject {
    static let shared = BackendHealthStore()

    @Published private(set) var records: [BackendHealthRecord] = []
    @Published private(set) var lastUsedLabel: String?

    private let recordsKey = "backendHealth.records.v1"
    private let lastUsedKey = "backendHealth.lastUsed.v1"

    private init() {
        load()
    }

    func recordSuccess(label: String) {
        mutateRecord(label: label, success: true, error: nil)
        lastUsedLabel = label
        persist()
    }

    func recordFailure(label: String, error: String) {
        mutateRecord(label: label, success: false, error: error)
        persist()
    }

    private func mutateRecord(label: String, success: Bool, error: String?) {
        if let index = records.firstIndex(where: { $0.label == label }) {
            records[index].lastOutcome = success ? "Healthy" : "Failing"
            records[index].lastUpdatedAt = Date()
            if success {
                records[index].successCount += 1
                records[index].lastError = nil
            } else {
                records[index].failureCount += 1
                records[index].lastError = error
            }
            return
        }

        records.append(
            BackendHealthRecord(
                label: label,
                lastOutcome: success ? "Healthy" : "Failing",
                lastUpdatedAt: Date(),
                successCount: success ? 1 : 0,
                failureCount: success ? 0 : 1,
                lastError: success ? nil : error
            )
        )
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: recordsKey),
           let decoded = try? JSONDecoder().decode([BackendHealthRecord].self, from: data) {
            records = decoded
        }
        lastUsedLabel = UserDefaults.standard.string(forKey: lastUsedKey)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: recordsKey)
        }
        UserDefaults.standard.set(lastUsedLabel, forKey: lastUsedKey)
    }
}
