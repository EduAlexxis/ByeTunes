import SwiftUI
import UIKit

struct LogViewer: View {
    @ObservedObject var logger = Logger.shared
    @Environment(\.presentationMode) var presentationMode

    @State private var shareItem: SharedLogFile?
    @State private var showCopiedBanner = false
    @State private var showingPreviousSession = false
    @State private var previousSessionText = ""

    private var displayedLogs: String {
        showingPreviousSession ? previousSessionText : logger.logs
    }

    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(displayedLogs.isEmpty && showingPreviousSession ? "No log from a previous session." : displayedLogs)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .id("bottom")
                }
                .onChange(of: logger.logs, perform: { _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                })
            }
            .safeAreaInset(edge: .top) {
                Picker("Session", selection: $showingPreviousSession) {
                    Text("This Session").tag(false)
                    Text("Previous Session").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .onChange(of: showingPreviousSession) { showing in
                if showing {
                    previousSessionText = Logger.previousSessionLog()
                }
            }
            .navigationTitle("Debug Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear") {
                        logger.clear()
                    }
                    .disabled(showingPreviousSession)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        UIPasteboard.general.string = displayedLogs
                        showCopiedBanner = true
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .disabled(displayedLogs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        if showingPreviousSession {
                            if FileManager.default.fileExists(atPath: Logger.previousSessionFileURL.path) {
                                shareItem = SharedLogFile(url: Logger.previousSessionFileURL)
                            }
                        } else if let url = logger.saveLogs() {
                            shareItem = SharedLogFile(url: url)
                        }
                    }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(item: $shareItem) { item in
                LogShareSheet(activityItems: [item.url])
            }
            .overlay(alignment: .bottom) {
                if showCopiedBanner {
                    Text("Logs copied")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showCopiedBanner)
            .onChange(of: showCopiedBanner) { copied in
                guard copied else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showCopiedBanner = false
                }
            }
        }
    }
}

private struct SharedLogFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct LogShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
