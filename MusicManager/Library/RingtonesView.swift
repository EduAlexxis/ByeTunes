import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct RingtoneMetadata: Identifiable {
    let id = UUID()
    var url: URL
    var name: String
    var remoteFilename: String
    var fileSize: Int = 0
    var durationMs: Int = 30000
    
    static func fromURL(_ url: URL) async -> RingtoneMetadata {
        let name = url.deletingPathExtension().lastPathComponent
        
        let randomName = String((0..<4).map { _ in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".randomElement()! })
        let remoteName = "\(randomName).m4r"
        
        let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attr?[.size] as? Int) ?? 0
        
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration)) ?? .invalid
        let durationSeconds = CMTimeGetSeconds(duration)
        let durationMs = durationSeconds.isNaN ? 30000 : Int(durationSeconds * 1000)
        
        return RingtoneMetadata(url: url, name: name, remoteFilename: remoteName, fileSize: size, durationMs: durationMs)
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

    private var disabledMessageView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.slash.circle.fill")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(.orange)

            VStack(spacing: 10) {
                Text("Ringtones Injection Disabled")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                Text("ringtones injection disabled due to instability, support will return soon (hopefully)")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 28)
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
                
                
                disabledMessageView

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
                 
                 let finalURL = await convertToM4R(url)
                 
                 if let validURL = finalURL {
                     let metadata = await RingtoneMetadata.fromURL(validURL)
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
        
        let duration = (try? await asset.load(.duration)) ?? .invalid
        let durationSeconds = CMTimeGetSeconds(duration)
        let maxDuration = 30.0
        
        if durationSeconds > maxDuration {
            let start = CMTime(seconds: 0.0, preferredTimescale: 600)
            let end = CMTime(seconds: maxDuration, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: start, end: end)
            exportSession.timeRange = timeRange
        }
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
                durationMs: ringtone.durationMs,
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
