import SwiftUI
import UniformTypeIdentifiers

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
                    ZStack {
                        Image("AppIconImage")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                    }
                    .scaleEffect(animateContent ? 1 : 0.8)
                    .opacity(animateContent ? 1 : 0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7), value: animateContent)
                    .scaleEffect(startPulse ? 1.05 : 1.0)
                    .animation(Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: startPulse)
                    
                    VStack(spacing: 8) {
                        Text("ByeTunes")
                            .font(.system(size: 34, weight: .bold, design: .default))
                            .tracking(0.5)
                        
                        Text("Sync music directly to your iPhone")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .offset(y: animateContent ? 0 : 20)
                    .opacity(animateContent ? 1 : 0)
                    .animation(.easeOut(duration: 0.5).delay(0.1), value: animateContent)
                }
                .padding(.bottom, 40)
                
                Spacer()
                
                
                VStack(spacing: 24) {
                    
                    HStack {
                        Text("Setup Required")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    
                    VStack(alignment: .leading, spacing: 0) {
                        StepRow(number: "1", text: "Export pairing file from computer", isLast: false)
                        StepRow(number: "2", text: "Transfer file to this iPhone", isLast: false)
                        StepRow(number: "3", text: "Tap button below to import", isLast: true)
                    }
                    
                    Divider()
                    
                    
                    VStack(spacing: 16) {
                        if !statusMessage.isEmpty {
                            HStack(spacing: 8) {
                                if isConnecting {
                                    ProgressView()
                                        .scaleEffect(0.8)
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
                            HStack {
                                Image(systemName: "arrow.up.doc.fill")
                                Text("Import Pairing File")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.accentColor)
                                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                            )
                        }
                        .disabled(isConnecting)
                        .opacity(isConnecting ? 0.7 : 1)
                    }
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.05), radius: 20, x: 0, y: 10)
                )
                .padding(.horizontal, 20)
                .offset(y: animateContent ? 0 : 50)
                .opacity(animateContent ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.2), value: animateContent)
                
                Spacer()
                    .frame(height: 20)
            }
        }
        .onAppear {
            animateContent = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
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
                self.isConnecting = false
                self.statusMessage = "Successfully Connected!"
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation {
                        self.isComplete = true
                    }
                }
            }
        })
        .onChange(of: manager.connectionStatus, perform: { newStatus in
            if isConnecting {
                self.statusMessage = newStatus
                if newStatus.contains("Failed") {
                    self.showError = true
                }
            }
        })
    }
    
    func handlePairingImport(url: URL?) {
        guard let url = url else { return }
        
        // Since we are using asCopy: true, we don't need security scoped access
        
        let destination = manager.pairingFile
        
        do {
            let directory = destination.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            
            isConnecting = true
            statusMessage = "Connecting..."
            showError = false
            
            isConnecting = true
            statusMessage = "Connecting..."
            showError = false
            
            manager.startHeartbeat()
        } catch {
            statusMessage = "Import failed"
            showError = true
        }
    }
}

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
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                }
                
                if !isLast {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(width: 2, height: 24)
                        .padding(.vertical, 4)
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
