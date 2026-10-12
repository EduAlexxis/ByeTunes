import SwiftUI
import UniformTypeIdentifiers

// MARK: - Editor
struct DatabaseEditorView: View {
    @StateObject private var store = DatabaseEditorStore()
    @ObservedObject private var manager = DeviceManager.shared

    @State private var showingPicker = false
    @State private var isBusy = false
    @State private var busyMessage = ""
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var showingInjectConfirm = false
    @State private var showingDiscardConfirm = false
    @State private var songTotal = 0
    @State private var tableTotal = 0

    var body: some View {
        List {
            Section("Source") {
                Button {
                    showingPicker = true
                } label: {
                    Label("Import Database File", systemImage: "square.and.arrow.down")
                }
                .disabled(isBusy)

                Button {
                    pullFromDevice()
                } label: {
                    Label("Pull From Device", systemImage: "iphone.and.arrow.forward")
                }
                .disabled(isBusy || !manager.heartbeatReady)

                if store.isOpen {
                    LabeledContent("Open", value: store.sourceName)
                }
            }

            if store.isOpen {
                Section("Browse") {
                    NavigationLink {
                        DatabaseSongsView(store: store)
                    } label: {
                        LabeledContent("Songs", value: "\(songTotal)")
                    }
                    NavigationLink {
                        DatabaseTablesView(store: store)
                    } label: {
                        LabeledContent("All Tables", value: "\(tableTotal)")
                    }
                }

                Section {
                    Button {
                        store.save()
                        statusMessage = "Changes saved."
                    } label: {
                        Label("Save Changes", systemImage: "checkmark.circle")
                    }
                    .disabled(store.pendingChanges == 0 || isBusy)

                    Button(role: .destructive) {
                        showingDiscardConfirm = true
                    } label: {
                        Label("Discard Changes", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(store.pendingChanges == 0 || isBusy)

                    Button {
                        showingInjectConfirm = true
                    } label: {
                        Label("Inject Into Device", systemImage: "square.and.arrow.up.on.square")
                    }
                    .disabled(isBusy || !manager.heartbeatReady)
                } header: {
                    Text("Changes")
                } footer: {
                    Text(store.pendingChanges == 0 ? "No unsaved edits." : "\(store.pendingChanges) unsaved edit\(store.pendingChanges == 1 ? "" : "s").")
                }
            }

            if isBusy || statusMessage != nil {
                Section {
                    if isBusy {
                        HStack {
                            ProgressView()
                            Text(busyMessage)
                                .padding(.leading, 8)
                        }
                    } else if let statusMessage {
                        Text(statusMessage)
                    }
                }
            }
        }
        .navigationTitle("Database Editor")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPicker) {
            DocumentPicker(types: [.data, .item]) { url in
                guard let url else { return }
                openFile(url)
            }
        }
        .alert("Inject Database?", isPresented: $showingInjectConfirm) {
            Button("Inject", role: .destructive) { inject() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This saves your edits and replaces the music library on your device with this database. Your current library will be overwritten.")
        }
        .alert("Discard Changes?", isPresented: $showingDiscardConfirm) {
            Button("Discard", role: .destructive) {
                store.discard()
                refreshCounts()
                statusMessage = "Changes discarded."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All unsaved edits will be lost.")
        }
        .alert("Database Editor", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: store.revision) { _ in refreshCounts() }
    }

    private func refreshCounts() {
        songTotal = store.songCount(search: "")
        tableTotal = store.tables().count
    }

    private func openFile(_ url: URL) {
        do {
            try store.open(copying: url, displayName: url.lastPathComponent)
            refreshCounts()
            statusMessage = "Opened \(url.lastPathComponent)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func pullFromDevice() {
        isBusy = true
        busyMessage = "Pulling library from device..."
        statusMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            guard manager.ensureActiveTransport(reason: "pulling the library for the database editor") else {
                DispatchQueue.main.async {
                    isBusy = false
                    errorMessage = "Device connection unavailable."
                }
                return
            }
            guard let context = manager.stageCurrentMediaLibraryForMutation(label: "db_editor") else {
                DispatchQueue.main.async {
                    isBusy = false
                    errorMessage = "Could not read the library from the device."
                }
                return
            }
            DispatchQueue.main.async {
                defer {
                    try? FileManager.default.removeItem(at: context.tempDir)
                    isBusy = false
                }
                do {
                    try store.open(copying: context.dbURL, displayName: "Device library")
                    refreshCounts()
                    statusMessage = "Pulled the library from the device."
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func inject() {
        store.commitForExport()
        isBusy = true
        busyMessage = "Injecting..."
        statusMessage = nil
        manager.injectDatabase(from: store.workingURL) { message in
            DispatchQueue.main.async {
                busyMessage = message
            }
        } completion: { success, message in
            DispatchQueue.main.async {
                isBusy = false
                if success {
                    statusMessage = message
                } else {
                    errorMessage = message
                }
            }
        }
    }
}
