import SwiftUI
import UniformTypeIdentifiers

struct MaintenancePanelView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingLogViewer = false
    @State private var lastAction: String?
    @ObservedObject private var manager = DeviceManager.shared
    @State private var showingDatabasePicker = false
    @State private var pendingDatabaseURL: URL?
    @State private var showingInjectConfirm = false
    @State private var isInjectingDatabase = false
    @State private var injectStatus = ""

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
                    Button {
                        showingDatabasePicker = true
                    } label: {
                        HStack {
                            Text(isInjectingDatabase ? injectStatus : "Inject Database")
                            Spacer()
                            if isInjectingDatabase {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isInjectingDatabase || !manager.heartbeatReady)

                    NavigationLink("Database Editor") {
                        DatabaseEditorView()
                    }
                } header: {
                    Text("Database")
                } footer: {
                    Text("Replaces the library on the connected device with a MediaLibrary.sqlitedb file you choose. Make a backup first.")
                }

                Section {
                    Button("Clear Persisted Queues", role: .destructive) {
                        QueuePersistenceStore.clearMusicQueue()
                        QueuePersistenceStore.clearDownloadQueue()
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
        .sheet(isPresented: $showingDatabasePicker) {
            DocumentPicker(types: [.data, .item]) { url in
                guard let url else { return }
                pendingDatabaseURL = url
                showingInjectConfirm = true
            }
        }
        .alert("Inject Database?", isPresented: $showingInjectConfirm) {
            Button("Inject", role: .destructive) {
                if let url = pendingDatabaseURL {
                    injectDatabase(from: url)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDatabaseURL = nil
            }
        } message: {
            Text("This replaces the music library on your device with \(pendingDatabaseURL?.lastPathComponent ?? "the selected file"). Your current library will be overwritten.")
        }
    }

    private func injectDatabase(from url: URL) {
        isInjectingDatabase = true
        injectStatus = "Injecting..."
        manager.injectDatabase(from: url) { message in
            DispatchQueue.main.async {
                injectStatus = message
            }
        } completion: { success, message in
            DispatchQueue.main.async {
                isInjectingDatabase = false
                pendingDatabaseURL = nil
                lastAction = success ? message : "Injection failed: \(message)"
            }
        }
    }
}
