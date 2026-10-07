import SwiftUI
import UniformTypeIdentifiers

// MARK: - OnboardingView

struct OnboardingView: View {

    @ObservedObject var manager: DeviceManager
    @Binding var isComplete: Bool

    @State private var showingPairingPicker = false
    @State private var isConnecting = false
    @State private var statusMessage = ""
    @State private var showError = false
    @State private var animateContent = false
    @State private var startPulse = false

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 16) {
                    Image("AppIconImage")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
                        .scaleEffect(startPulse ? 1.04 : 1.0)
                        .animation(
                            Animation.easeInOut(duration: 2.2).repeatForever(autoreverses: true),
                            value: startPulse
                        )

                    VStack(spacing: 6) {
                        Text("ByeTunes")
                            .font(.system(size: 34, weight: .bold))
                            .tracking(0.4)
                        Text("Sync music directly to your iPhone")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .scaleEffect(animateContent ? 1 : 0.85)
                .opacity(animateContent ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.72), value: animateContent)
                .padding(.horizontal, 24)
                .padding(.bottom, 36)

                Spacer()

                connectCard
                    .offset(y: animateContent ? 0 : 50)
                    .opacity(animateContent ? 1 : 0)
                    .animation(.easeOut(duration: 0.5).delay(0.18), value: animateContent)
                    .padding(.horizontal, 20)

                Spacer().frame(height: 32)
            }
        }
        .onAppear {
            animateContent = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                startPulse = true
            }
        }
        .sheet(isPresented: $showingPairingPicker) {
            DocumentPicker(types: [.data, .xml, .propertyList, .item]) { url in
                handlePairingImport(url: url)
            }
        }
        .onChange(of: manager.heartbeatReady, perform: { ready in
            if ready {
                isConnecting = false
                showError = false
                withAnimation {
                    isComplete = true
                }
            }
        })
        .onChange(of: manager.connectionStatus, perform: { newStatus in
            if isConnecting {
                statusMessage = newStatus
                if newStatus.contains("Failed") || newStatus.contains("Invalid") || newStatus.contains("Lost") {
                    isConnecting = false
                    showError = true
                }
            }
        })
    }

    // MARK: - Connect Card
    @ViewBuilder
    private var connectCard: some View {
        VStack(spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("One-time Setup")
                        .font(.headline)
                    Text("This only needs to be done once.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                StepRow(number: "1", text: "Export \(manager.expectedPairingFileDescription) from your computer", isLast: false)
                StepRow(number: "2", text: "Transfer the file to this iPhone", isLast: false)
                StepRow(number: "3", text: "Connect to your Tunnel VPN", isLast: false)
                StepRow(number: "4", text: "Tap the button below to import", isLast: true)
            }

            Divider()

            VStack(spacing: 14) {
                if !statusMessage.isEmpty {
                    HStack(spacing: 8) {
                        if isConnecting {
                            ProgressView().scaleEffect(0.8)
                        }
                        Text(statusMessage)
                            .font(.subheadline)
                            .foregroundColor(showError ? .red : .primary)
                            .animation(.easeInOut, value: statusMessage)
                    }
                    .padding(.vertical, 4)
                }

                Button {
                    showingPairingPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.doc.fill")
                        Text("Import \(manager.expectedPairingFileTitle)")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.accentColor)
                            .shadow(color: Color.accentColor.opacity(0.28), radius: 10, x: 0, y: 5)
                    )
                }
                .disabled(isConnecting)
                .opacity(isConnecting ? 0.65 : 1)

                if showError && manager.hasValidExpectedPairingFile {
                    Button {
                        retryConnection()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry Connection")
                        }
                        .font(.headline)
                        .foregroundColor(.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.accentColor.opacity(0.10))
                        )
                    }
                    .disabled(isConnecting)
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 20, x: 0, y: 10)
        )
    }

    // MARK: - Pairing Import
    func handlePairingImport(url: URL?) {
        guard let url = url else { return }
        do {
            try manager.importPairingFile(from: url)
            isConnecting = true
            statusMessage = "Connecting..."
            showError = false
            manager.startHeartbeat { success in
                if success { return }
                DispatchQueue.main.async {
                    isConnecting = false
                    statusMessage = manager.connectionStatus
                    showError = true
                }
            }
        } catch {
            statusMessage = error.localizedDescription
            showError = true
        }
    }

    func retryConnection() {
        isConnecting = true
        statusMessage = "Connecting..."
        showError = false
        manager.startHeartbeat(forceReconnect: true) { success in
            if success { return }
            DispatchQueue.main.async {
                isConnecting = false
                statusMessage = manager.connectionStatus
                showError = true
            }
        }
    }
}

// MARK: - StepRow

struct StepRow: View {
    let number: String
    let text: String
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Color(.systemGray6))
                        .frame(width: 28, height: 28)
                    Text(number)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                }
                if !isLast {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(width: 2, height: 22)
                        .padding(.vertical, 3)
                }
            }

            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }
}
