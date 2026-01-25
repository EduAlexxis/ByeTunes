import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct RingtoneMetadata: Identifiable {
    let id = UUID()
    var url: URL
    var name: String
    var remoteFilename: String
    var fileSize: Int = 0
    
    static func fromURL(_ url: URL) -> RingtoneMetadata {
        let name = url.deletingPathExtension().lastPathComponent
        
        let randomName = String((0..<4).map { _ in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".randomElement()! })
        let remoteName = "\(randomName).m4r"
        
        let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attr?[.size] as? Int) ?? 0
        
        return RingtoneMetadata(url: url, name: name, remoteFilename: remoteName, fileSize: size)
    }
}

struct RingtonesView: View {
    @ObservedObject var manager: DeviceManager
    @Binding var ringtones: [RingtoneMetadata]
    @State private var isInjecting = false
    @State private var showingPicker = false
    @State private var injectProgress: CGFloat = 0
    
    
    @State private var showToast = false
    @State private var toastTitle = ""
    @State private var toastIcon = ""
    
    
    @State private var currentInjectIndex = 0
    @State private var totalInjectCount = 0
    
    
    static var supportedTypes: [UTType] {
        let m4r = UTType(filenameExtension: "m4r") ?? .audio
        return [m4r, .mp3]
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 10) {
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text("Ringtones")
                            .font(.system(size: 34, weight: .bold))
                        
                        
                        HStack(spacing: 6) {
                            Circle()
                                .fill(manager.heartbeatReady ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(manager.connectionStatus)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                    }
                }
                .padding(.top, 0)
                
                
                VStack(spacing: 12) {
                    Button {
                        showingPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "plus")
                                .font(.body.weight(.medium))
                            Text("Add Ringtones")
                                .font(.body.weight(.medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    
                    Button {
                        injectRingtones()
                    } label: {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(Color(.systemGray6))
                                
                                
                                if isInjecting {
                                    RoundedRectangle(cornerRadius: 24)
                                        .fill(Color.black.opacity(0.15))
                                        .frame(width: geo.size.width * injectProgress)
                                        .animation(.easeInOut(duration: 0.3), value: injectProgress)
                                }
                                
                                
                                HStack {
                                    Spacer()
                                    if isInjecting {
                                        Text("Injecting \(currentInjectIndex)/\(totalInjectCount)")
                                            .font(.body.weight(.medium))
                                    } else {
                                        Image(systemName: "arrow.down.to.line")
                                            .font(.body.weight(.medium))
                                        Text("Inject to Device")
                                            .font(.body.weight(.medium))
                                    }
                                    Spacer()
                                }
                                .foregroundColor(.primary)
                            }
                        }
                        .frame(height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                    }
                    .disabled(ringtones.isEmpty || isInjecting || !manager.heartbeatReady)
                    .opacity(ringtones.isEmpty ? 0.6 : 1)
                }
                
                
                if !ringtones.isEmpty && !isInjecting {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("IMPORTANT: Ensure Settings App is closed before injecting")
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.leading)
                    }
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                    )
                }
                
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Queue")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if !ringtones.isEmpty {
                            Text("\(ringtones.count) ringtones")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if ringtones.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "bell.slash")
                                .font(.system(size: 48, weight: .light))
                                .foregroundColor(Color(.systemGray3))
                                .padding(.top, 20)
                            
                            VStack(spacing: 4) {
                                Text("No ringtones in queue")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                Text("Tap \"Add Ringtones\" to get started")
                                    .font(.subheadline)
                                    .foregroundColor(Color(.systemGray))
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("💡 NOTE FOR IOS 26+")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.secondary)
                                    .tracking(0.5)
                                
                                Text("iOS 26 and above include native ringtone management. You can still use this tool to inject custom tones if you prefer.")
                                    .font(.caption)
                                    .foregroundColor(.secondary.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(16)
                            .background(Color(.systemGray6).opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.top, 10)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(Array(ringtones.enumerated()), id: \.element.id) { index, item in
                                    VStack(spacing: 0) {
                                        HStack {
                                            Image(systemName: "waveform")
                                                .font(.title2)
                                                .foregroundColor(.purple)
                                                .frame(width: 40, height: 40)
                                                .background(Color.purple.opacity(0.1))
                                                .cornerRadius(8)
                                            
                                            VStack(alignment: .leading) {
                                                Text(item.name)
                                                    .font(.body)
                                                    .fontWeight(.medium)
                                                Text(item.remoteFilename)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            
                                            Spacer()
                                            
                                            Button {
                                                withAnimation {
                                                    ringtones.removeAll { $0.id == item.id }
                                                }
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.gray.opacity(0.5))
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        
                                        if index < ringtones.count - 1 {
                                            Divider()
                                                .padding(.leading, 68)
                                        }
                                    }
                                }
                            }
                        }
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray5), lineWidth: 1)
                        )
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            
            
            if showToast {
                HStack(spacing: 12) {
                    Image(systemName: toastIcon)
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    
                    Text(toastTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
                .padding(.horizontal, 24)
                .padding(.bottom, 50)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .sheet(isPresented: $showingPicker) {
            DocumentPicker(types: Self.supportedTypes, allowsMultiple: true) { urls in
                handleImport(urls)
            }
        }
    }
    
    private func handleImport(_ urls: [URL]?) {
        guard let urls = urls else { return }
        
        Task {
            for url in urls {
                 
                 // Since we are using asCopy: true, we don't need security scoped access
                 
                 let ext = url.pathExtension.lowercased()
                 var finalURL: URL?
                 
                 if ext == "mp3" {
                     finalURL = await convertToM4R(url)
                 } else {
                     let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                     try? FileManager.default.removeItem(at: tempURL)
                     try? FileManager.default.copyItem(at: url, to: tempURL)
                     finalURL = tempURL
                 }
                 
                 if let validURL = finalURL {
                     let metadata = RingtoneMetadata.fromURL(validURL)
                     await MainActor.run {
                         ringtones.append(metadata)
                     }
                 }
            }
        }
    }
    
    private func convertToM4R(_ sourceURL: URL) async -> URL? {
        let asset = AVURLAsset(url: sourceURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            return nil
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let filename = sourceURL.deletingPathExtension().lastPathComponent
        let outputURL = tempDir.appendingPathComponent("\(filename).m4a")
        
        try? FileManager.default.removeItem(at: outputURL)
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        
        
        
        
        
        
        
        
        await exportSession.export()

        if exportSession.status == .completed {
             let m4rURL = tempDir.appendingPathComponent("\(filename).m4r")
             try? FileManager.default.removeItem(at: m4rURL)
             do {
                 try FileManager.default.moveItem(at: outputURL, to: m4rURL)
                 return m4rURL
             } catch {
                 return nil
             }
        } else {
             return nil
        }
    }
    
    private func injectRingtones() {
        guard !ringtones.isEmpty else { return }
        isInjecting = true
        injectProgress = 0
        totalInjectCount = ringtones.count
        currentInjectIndex = 0
        
        
        manager.startHeartbeat { success in
            guard success else {
                DispatchQueue.main.async {
                    self.showToast(title: "Connection Failed", icon: "exclamationmark.triangle.fill")
                    self.isInjecting = false
                }
                return
            }
            
            
            DispatchQueue.main.async {
                self.startRingtoneInjection()
            }
        }
    }

    private func startRingtoneInjection() {
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if self.injectProgress < 0.9 {
                self.injectProgress += 0.02
            }
        }
        
        let songs = ringtones.map { ringtone in
            SongMetadata(
                localURL: ringtone.url,
                title: ringtone.name,
                artist: "Ringtone",
                album: "Ringtones",
                genre: "Ringtone",
                year: 2024,
                durationMs: 30000,
                fileSize: ringtone.fileSize,
                remoteFilename: ringtone.remoteFilename,
                artworkData: nil
            )
        }
        
        manager.injectRingtones(ringtones: songs) { progressText in
            DispatchQueue.main.async {
                
                if let range = progressText.range(of: #"(\d+)/\d+"#, options: .regularExpression),
                   let index = Int(progressText[range].split(separator: "/").first ?? "") {
                    self.currentInjectIndex = index
                    self.injectProgress = CGFloat(index) / CGFloat(self.totalInjectCount) * 0.9
                }
            }
        } completion: { success in
            DispatchQueue.main.async {
                progressTimer.invalidate()
                
                withAnimation(.easeOut(duration: 0.3)) {
                    self.injectProgress = 1.0
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isInjecting = false
                    injectProgress = 0
                    
                    if success {
                        showToast(title: "Ringtones Injected!", icon: "checkmark.circle.fill")
                        ringtones.removeAll()
                    } else {
                        showToast(title: "Injection Failed", icon: "xmark.circle.fill")
                    }
                }
            }
        }
    }
    
    private func showToast(title: String, icon: String) {
        withAnimation(.spring()) {
            self.toastTitle = title
            self.toastIcon = icon
            self.showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showToast = false }
        }
    }
}
