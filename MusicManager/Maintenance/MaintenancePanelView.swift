import SwiftUI

struct MaintenancePanelView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingLogViewer = false
    @State private var lastAction: String?

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Onboarding") {
                    Button("Show Onboarding") {
                        NotificationCenter.default.post(name: NSNotification.Name("ResetOnboardingFlow"), object: nil)
                        dismiss()
                    }
                    Button("Replay Tutorial") {
                        UserDefaults.standard.set(false, forKey: "tutorialComplete")
                        dismiss()
                    }
                }

                Section("Diagnostics") {
                    Button("View Console Logs") {
                        showingLogViewer = true
                    }
                    LabeledContent("App Version", value: appVersion)
                    LabeledContent("Connection", value: DeviceManager.shared.connectionStatus)
                    LabeledContent("Background Downloads", value: UserDefaults.standard.bool(forKey: "backgroundDownloadsEnabled") ? "On" : "Off")
                }

                Section {
                    Button("Clear Persisted Queues", role: .destructive) {
                        QueuePersistenceStore.clearMusicQueue()
                        QueuePersistenceStore.clearDownloadQueue()
                        QueuePersistenceStore.clearDeferredDownloadEnrichments()
                        QueuePersistenceStore.clearPendingDownloadedImports()
                        lastAction = "Cleared persisted queues"
                    }
                } footer: {
                    if let lastAction {
                        Text(lastAction)
                    }
                }
            }
            .navigationTitle("Maintenance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingLogViewer) {
            LogViewer()
        }
    }
}
