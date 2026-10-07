import SwiftUI
import UniformTypeIdentifiers

// MARK: - Injection
extension MusicView {
    func injectSongs() {
        guard !songs.isEmpty else { return }
        
        isInjecting = true
        injectProgress = 0
        totalInjectCount = songs.count
        currentInjectIndex = 0
        isMinimalBatchInjectionMode = songs.count >= Self.largeBatchThreshold
        
        
        manager.startHeartbeat(forceReconnect: true) { success in
            guard success else {
                DispatchQueue.main.async {
                    self.showToast(title: "Connection Failed", icon: "exclamationmark.triangle.fill")
                    self.isInjecting = false
                    self.isMinimalBatchInjectionMode = false
                }
                return
            }
            
            
            DispatchQueue.main.async {
                self.startInjectionProcess()
            }
        }
    }
    
    func startInjectionProcess() {
        
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if self.injectProgress < 0.9 {
                self.injectProgress += 0.02
            }
        }
        
        var lastProcessedIndex = 0
        let songsToInfect = songs 
        
        manager.injectSongs(songs: songsToInfect, progress: { progressText in
            DispatchQueue.main.async {
                
                if let range = progressText.range(of: #"(\d+)/\d+"#, options: .regularExpression),
                   let index = Int(progressText[range].split(separator: "/").first ?? "") {
                    self.currentInjectIndex = index
                    
                    self.injectProgress = CGFloat(index) / CGFloat(self.totalInjectCount) * 0.9
                    
                    if !self.isMinimalBatchInjectionMode {
                        while lastProcessedIndex < index && !self.songs.isEmpty {
                            _ = self.songs.removeFirst()
                            lastProcessedIndex += 1
                        }
                    }
                }
            }
        }) { success in
            DispatchQueue.main.async {
                progressTimer.invalidate()
                
                withAnimation(.easeOut(duration: 0.3)) {
                    self.injectProgress = 1.0
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.isInjecting = false
                    self.isMinimalBatchInjectionMode = false
                    self.injectProgress = 0
                    
                    if success {
                        for song in songsToInfect {
                            if !SongMetadata.shouldPreserveLocalFile(song.localURL) {
                                try? FileManager.default.removeItem(at: song.localURL)
                            }
                        }

                        self.showToast(title: "Injection Complete", icon: "checkmark.circle.fill")
                        withAnimation {
                            self.songs.removeAll()
                        }
                    } else {
                        if lastProcessedIndex > 0 {
                            let unconfirmedSongs = Array(songsToInfect.prefix(lastProcessedIndex))
                            withAnimation {
                                self.songs.insert(contentsOf: unconfirmedSongs, at: 0)
                            }
                        }
                        self.showToast(title: "Injection Failed", icon: "xmark.circle.fill")
                    }
                }
            }
        }

    
    }

    func injectAsPlaylist(name: String? = nil, pid: Int64? = nil) {
        guard !songs.isEmpty else { return }
        if name == nil && pid == nil { return }
        
        isInjecting = true
        injectProgress = 0
        totalInjectCount = songs.count
        currentInjectIndex = 0
        isMinimalBatchInjectionMode = songs.count >= Self.largeBatchThreshold

        
        
        manager.startHeartbeat(forceReconnect: true) { success in
            guard success else {
                DispatchQueue.main.async {
                    self.showToast(title: "Connection Failed", icon: "exclamationmark.triangle.fill")
                    self.isInjecting = false
                    self.isMinimalBatchInjectionMode = false
                }
                return
            }
             
            DispatchQueue.main.async {
                self.startPlaylistInjection(name: name, pid: pid)
            }
        }
    }

    func startPlaylistInjection(name: String?, pid: Int64?) {
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if self.injectProgress < 0.9 {
                self.injectProgress += 0.02
            }
        }
        
        var lastProcessedIndex = 0
        let songsToInfect = songs
        
        manager.injectSongsAsPlaylist(songs: songsToInfect, playlistName: name, targetPlaylistPid: pid, progress: { progressText in
            DispatchQueue.main.async {
                if let range = progressText.range(of: #"(\d+)/\d+"#, options: .regularExpression),
                   let index = Int(progressText[range].split(separator: "/").first ?? "") {
                    self.currentInjectIndex = index
                    self.injectProgress = CGFloat(index) / CGFloat(self.totalInjectCount) * 0.9
                    
                    if !self.isMinimalBatchInjectionMode {
                        while lastProcessedIndex < index && !self.songs.isEmpty {
                            _ = self.songs.removeFirst()
                            lastProcessedIndex += 1
                        }
                    }
                }
            }
        }) { success in
            DispatchQueue.main.async {
                progressTimer.invalidate()
                
                withAnimation(.easeOut(duration: 0.3)) {
                    self.injectProgress = 1.0
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.isInjecting = false
                    self.isMinimalBatchInjectionMode = false
                    self.injectProgress = 0
                    
                    if success {
                        for song in songsToInfect {
                            if !SongMetadata.shouldPreserveLocalFile(song.localURL) {
                                try? FileManager.default.removeItem(at: song.localURL)
                            }
                        }

                        self.showToast(title: "Playlist Updated", icon: "checkmark.circle.fill")
                        withAnimation {
                            self.songs.removeAll()
                        }
                    } else {
                        if lastProcessedIndex > 0 {
                            let unconfirmedSongs = Array(songsToInfect.prefix(lastProcessedIndex))
                            withAnimation {
                                self.songs.insert(contentsOf: unconfirmedSongs, at: 0)
                            }
                        }
                        self.showToast(title: "Playlist Failed", icon: "xmark.circle.fill")
                    }
                }
            }
        }
    }
}
