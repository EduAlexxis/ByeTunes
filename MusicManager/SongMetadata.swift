import Foundation
import AVFoundation


struct SongMetadata: Identifiable {
    let id = UUID()
    
    var localURL: URL
    var title: String
    var artist: String
    var album: String
    var albumArtist: String?
    var genre: String
    var year: Int
    var durationMs: Int
    var fileSize: Int
    var remoteFilename: String
    var artworkData: Data?
    
    var trackNumber: Int?
    var trackCount: Int?
    var discNumber: Int?
    var discCount: Int?
    var lyrics: String?
    
    
    var artworkToken: String {
        return "local://\(remoteFilename)"
    }
    
    
    static func generateRemoteFilename(withExtension ext: String? = nil) -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let randomName = String((0..<4).map { _ in letters.randomElement()! })
        let e = (ext?.isEmpty == false) ? ext!.lowercased() : "mp3"
        return "\(randomName).\(e)"
    }
    
    
    static func generatePersistentId() -> Int64 {
        return Int64.random(in: 1_000_000_000_000_000_000...Int64.max)
    }
    
    
    static func generateGroupingKey(_ text: String) -> Data {
        guard !text.isEmpty else { return Data() }
        
        var result = [UInt8]()
        for char in text.uppercased() {
            if char >= "A" && char <= "Z" {
                result.append(UInt8(char.asciiValue! - Character("A").asciiValue! + 1))
            } else if char == " " {
                result.append(0x04)
            } else if char == "/" {
                result.append(0x0A)
            }
        }
        return Data(result)
    }

    
    static func fromURL(_ url: URL) async throws -> SongMetadata {
        let asset = AVURLAsset(url: url)
        
        
        let duration = try await asset.load(.duration)
        let durationMs = Int(CMTimeGetSeconds(duration) * 1000)
        
        
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        
        
        let filenameWithoutExt = url.deletingPathExtension().lastPathComponent
        var title = filenameWithoutExt
        var artist = "Unknown Artist"
        var album = "Unknown Album"
        var albumArtist: String?
        var genre = "Unknown Genre"
        var year = Calendar.current.component(.year, from: Date())
        var artworkData: Data?
        
        var trackNumber: Int?
        var trackCount: Int?
        var discNumber: Int?
        var discCount: Int?
        var lyrics: String?
        
        
        if filenameWithoutExt.contains(" - ") {
            let parts = filenameWithoutExt.components(separatedBy: " - ")
            if parts.count >= 2 {
                
                title = parts[0].trimmingCharacters(in: .whitespaces)
                artist = parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        
        
        let commonMetadata = try await asset.load(.commonMetadata)
        
        for item in commonMetadata {
            guard let key = item.commonKey else { continue }
            
            switch key {
            case .commonKeyTitle:
                if let value = try? await item.load(.stringValue), !value.isEmpty {
                    title = value
                }
            case .commonKeyArtist:
                if let value = try? await item.load(.stringValue), !value.isEmpty {
                    artist = value
                }
            case .commonKeyAlbumName:
                if let value = try? await item.load(.stringValue), !value.isEmpty {
                    album = value
                }
            case .commonKeyType:
                if let value = try? await item.load(.stringValue), !value.isEmpty {
                    genre = value
                }
            case .commonKeyCreationDate:
                if let value = try? await item.load(.stringValue),
                   let extracted = extractYear(from: value) {
                    year = extracted
                }
            case .commonKeyArtwork:
                if let data = try? await item.load(.dataValue) {
                    artworkData = data
                    print("[SongMetadata] Extracted artwork: \(data.count) bytes")
                }
            default: break
            }
        }
        
        
        let allMetadata = try await asset.load(.metadata)
        
        
        for item in allMetadata {
            
            var keyString = ""
            if let strKey = item.key as? String {
                keyString = strKey
            } else if let intKey = item.key as? Int {
                
                
                keyString = "\(intKey)"
            }
            
            let identifier = item.identifier?.rawValue ?? ""
            let combined = "\(identifier)|\(keyString)".uppercased()
            
            
            
            
            if trackNumber == nil {
                if combined.contains("TRCK") || combined.contains("TRACK") || combined.contains("TRKN") || keyString.lowercased() == "trkn" {
                    
                    if let stringVal = try? await item.load(.stringValue) {
                        let components = stringVal.components(separatedBy: "/")
                        if let t = Int(components[0]) { trackNumber = t }
                        if components.count > 1, let tc = Int(components[1]) { trackCount = tc }
                    }
                    
                    else if let dataVal = try? await item.load(.dataValue), dataVal.count >= 8 {
                        
                        let track = dataVal.withUnsafeBytes { $0.load(fromByteOffset: 2, as: UInt16.self).bigEndian }
                        let total = dataVal.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt16.self).bigEndian }
                        if track > 0 { trackNumber = Int(track) }
                        if total > 0 { trackCount = Int(total) }
                    }
                }
            }
            
            
            if discNumber == nil {
                if combined.contains("TPOS") || combined.contains("DISC") || combined.contains("DISK") || keyString.lowercased() == "disk" {
                     if let stringVal = try? await item.load(.stringValue) {
                        let components = stringVal.components(separatedBy: "/")
                        if let d = Int(components[0]) { discNumber = d }
                        if components.count > 1, let dc = Int(components[1]) { discCount = dc }
                     } else if let dataVal = try? await item.load(.dataValue), dataVal.count >= 6 { 
                         
                         let disc = dataVal.withUnsafeBytes { $0.load(fromByteOffset: 2, as: UInt16.self).bigEndian }
                         let total = dataVal.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt16.self).bigEndian }
                         if disc > 0 { discNumber = Int(disc) }
                         if total > 0 { discCount = Int(total) }
                     }
                }
            }

            
            if artworkData == nil {
                
                if combined.contains("ARTWORK") || combined.contains("PICTURE") || combined.contains("APIC") || combined.contains("COVR") {
                    if let data = try? await item.load(.dataValue), !data.isEmpty {
                        artworkData = data
                        print("[SongMetadata] Deep Scan extracted artwork: \(data.count) bytes (Key: \(combined))")
                    }
                }
            }

            
            if let val = try? await item.load(.stringValue), !val.isEmpty {
                if (combined.contains("TITLE") || combined.contains("NAM")) && title == filenameWithoutExt { title = val }
                if (combined.contains("ARTIST") || combined.contains("PERFORMER")) && !combined.contains("ALBUMARTIST") && artist == "Unknown Artist" { artist = val }
                if combined.contains("ALBUM") && !combined.contains("ALBUMARTIST") && album == "Unknown Album" { album = val }
                if (combined.contains("GENRE") || combined.contains("GEN")) && genre == "Unknown Genre" { genre = val }
                
                
                if (combined.contains("ALBUMARTIST") || combined.contains("TPE2") || combined.contains("AART")) {
                   let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
                   if !trimmed.isEmpty && trimmed.lowercased() != "unknown artist" {
                       albumArtist = trimmed
                       print("[SongMetadata] Extracted Album Artist: \(trimmed) from key: \(combined)")
                   } else {
                       print("[SongMetadata] Ignored invalid Album Artist: '\(val)'")
                   }
                }

                
                if year == Calendar.current.component(.year, from: Date()) {
                    if combined.contains("DATE") || combined.contains("YEAR") || combined.contains("TYER") || combined.contains("TDRC") || combined.contains("DAY") {
                        if let extracted = extractYear(from: val) {
                            year = extracted
                            print("[SongMetadata] Extracted year: \(year) from key: \(combined) (Val: \(val))")
                        }
                    }
                }
                
                // Lyrics Extraction
                if lyrics == nil {
                    if combined.contains("USLT") || combined.contains("LYRICS") || combined.contains("UNSYNC") || keyString == "\u{00A9}lyr" {
                         lyrics = SongMetadata.cleanLyrics(val)
                         print("[SongMetadata] Extracted and cleaned lyrics from key: \(combined)")
                    }
                }
            }
        }
        
        
        if let aa = albumArtist, (aa.isEmpty || aa.lowercased() == "unknown artist") {
            albumArtist = nil
        }
        
        print("[SongMetadata] Final: title=\(title), artist=\(artist), album=\(album), track=\(trackNumber ?? 0)/\(trackCount ?? 0)")
        
        return SongMetadata(
            localURL: url,
            title: title,
            artist: artist,
            album: album,
            albumArtist: albumArtist,
            genre: genre,
            year: year,
            durationMs: durationMs,
            fileSize: fileSize,
            remoteFilename: generateRemoteFilename(withExtension: url.pathExtension),
            artworkData: artworkData,
            trackNumber: trackNumber,
            trackCount: trackCount,
            discNumber: discNumber,
            discCount: discCount,
            lyrics: lyrics
        )
    }
    
    
    static private func extractYear(from string: String) -> Int? {
        
        
        
        
        do {
            let regex = try NSRegularExpression(pattern: "\\b(19|20)\\d{2}\\b")
            let nsString = string as NSString
            let results = regex.matches(in: string, range: NSRange(location: 0, length: nsString.length))
            
            if let first = results.first {
                let match = nsString.substring(with: first.range)
                if let y = Int(match), y >= 1900 && y <= 2100 {
                    return y
                }
            }
        } catch {
            return nil
        }
        
        
        if let prefixInt = Int(string.prefix(4)), prefixInt >= 1900 && prefixInt <= 2100 {
            return prefixInt
        }
        
        return nil
    }
    
    static private func cleanLyrics(_ rawLyrics: String) -> String {
        // 1. Remove metadata headers like [ti:Title], [ar:Artist], etc.
        // regex: \[([a-z]+):.*\]
        let withoutHeaders = rawLyrics.replacingOccurrences(of: #"\[([a-z]+):.*\]"#, with: "", options: .regularExpression)
        
        // 2. Remove timestamps like [00:21.26] or [00:21]
        // regex: \[\d{2,}:\d{2}(\.\d{2,})?\]
        let withoutTimestamps = withoutHeaders.replacingOccurrences(of: #"\[\d{2,}:\d{2}(\.\d{2,})?\]"#, with: "", options: .regularExpression)
        
        // 3. Clean up extra whitespace/newlines
        let lines = withoutTimestamps.components(separatedBy: .newlines)
        let cleanLines = lines.map { $0.trimmingCharacters(in: .whitespaces) }
                              .filter { !$0.isEmpty }
        
        return cleanLines.joined(separator: "\n")
    }
}



struct iTunesSearchResult: Codable {
    let results: [iTunesSong]
}

struct iTunesSong: Codable, Identifiable {
    var id: Int { trackId ?? Int.random(in: 0...Int.max) }
    let trackId: Int?
    let trackName: String?
    let artistName: String?
    let collectionName: String?
    let primaryGenreName: String?
    let releaseDate: String?
    let artworkUrl100: String?
    let trackNumber: Int?
    let trackCount: Int?
    let discNumber: Int?
    let discCount: Int?
}



extension SongMetadata {
    
    
    static func searchiTunes(query: String) async -> [iTunesSong] {
        let region = UserDefaults.standard.string(forKey: "storeRegion") ?? "US"
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://itunes.apple.com/search?term=\(encodedQuery)&entity=song&limit=10&country=\(region)") else {
            return []
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try JSONDecoder().decode(iTunesSearchResult.self, from: data)
            return result.results
        } catch {
            print("[SongMetadata] iTunes search failed: \(error)")
            return []
        }
    }
    
    
    static func applyiTunesMatch(_ match: iTunesSong, to song: SongMetadata) async -> SongMetadata {
        var newSong = song
        
        
        if let t = match.trackName { newSong.title = t }
        if let a = match.artistName { newSong.artist = a }
        if let c = match.collectionName { newSong.album = c }
        if let g = match.primaryGenreName { newSong.genre = g }
        
        if let tn = match.trackNumber { newSong.trackNumber = tn }
        if let tc = match.trackCount { newSong.trackCount = tc }
        if let dn = match.discNumber { newSong.discNumber = dn }
        if let dc = match.discCount { newSong.discCount = dc }
        
        if let dateStr = match.releaseDate,
           let yearInt = Int(dateStr.prefix(4)) {
            newSong.year = yearInt
        }
        
        
        if let artUrl = match.artworkUrl100 {
            
            let highResUrlString = artUrl.replacingOccurrences(of: "100x100bb", with: "1200x1200bb")
            if let highResUrl = URL(string: highResUrlString),
               let (artData, _) = try? await URLSession.shared.data(from: highResUrl) {
                newSong.artworkData = artData
                print("[SongMetadata] Updated artwork with iTunes High-Res version: \(artData.count) bytes")
            }
        }
        
        return newSong
    }

    
    static func enrichWithiTunesMetadata(_ song: SongMetadata) async -> SongMetadata {
        print("[SongMetadata] Searching iTunes for: \(song.artist) - \(song.title)")
        
        let query = "\(song.artist) \(song.title)"
        let results = await searchiTunes(query: query)
        
        
        var bestMatch: iTunesSong?
        
        for match in results {
            guard let remoteArtist = match.artistName,
                  let remoteTitle = match.trackName else { continue }
            
            
            if song.artist != "Unknown Artist" {
                let localNorm = song.artist.lowercased().filter { !$0.isPunctuation }
                let remoteNorm = remoteArtist.lowercased().filter { !$0.isPunctuation }
                
                
                if localNorm.contains(remoteNorm) || remoteNorm.contains(localNorm) {
                    bestMatch = match
                    print("[SongMetadata] ✓ Validated match: \(remoteTitle) by \(remoteArtist)")
                    break 
                } else {
                    print("[SongMetadata] x Rejected match: \(remoteTitle) by \(remoteArtist) (Artist mismatch)")
                }
            } else {
                
                bestMatch = match
                break
            }
        }
        
        guard let match = bestMatch else {
            print("[SongMetadata] No valid iTunes match found after filtering.")
            return song
        }
        
        return await applyiTunesMatch(match, to: song)
    }
}



struct DeezerSearchResult: Codable {
    let data: [DeezerSong]
}

struct DeezerSong: Codable, Identifiable {
    let id: Int
    let title: String
    let artist: DeezerReference
    let album: DeezerAlbumReference
    let duration: Int
    
    
    var trackName: String { title }
    var artistName: String { artist.name }
    var albumName: String { album.title }
    var artworkUrl: String { album.cover_xl }
}

struct DeezerReference: Codable {
    let name: String
}

struct DeezerAlbumReference: Codable {
    let title: String
    let cover_xl: String
}

struct DeezerTrackDetails: Codable {
    let track_position: Int?
    let disk_number: Int?
    let release_date: String? 
}



extension SongMetadata {
    
    
    static func searchDeezer(query: String) async -> [DeezerSong] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://api.deezer.com/search?q=\(encodedQuery)&limit=10") else {
            return []
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try JSONDecoder().decode(DeezerSearchResult.self, from: data)
            return result.data
        } catch {
            print("[SongMetadata] Deezer search failed: \(error)")
            return []
        }
    }
    
    static func fetchDeezerTrackDetails(id: Int) async -> DeezerTrackDetails? {
        guard let url = URL(string: "https://api.deezer.com/track/\(id)") else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode(DeezerTrackDetails.self, from: data)
        } catch {
            print("[SongMetadata] Failed to fetch Deezer track details: \(error)")
            return nil
        }
    }
    
    
    static func applyDeezerMatch(_ match: DeezerSong, to song: SongMetadata) async -> SongMetadata {
        var newSong = song
        
        newSong.title = match.title
        newSong.artist = match.artist.name
        newSong.album = match.album.title
        
        
        newSong.durationMs = match.duration * 1000
        
        
        if let details = await fetchDeezerTrackDetails(id: match.id) {
            if let t = details.track_position { newSong.trackNumber = t }
            if let d = details.disk_number { newSong.discNumber = d }
            
            if let releaseDate = details.release_date {
                
                let components = releaseDate.split(separator: "-")
                if let yearStr = components.first, let yearInt = Int(yearStr) {
                    newSong.year = yearInt
                }
            }
            print("[SongMetadata] Enhanced with Deezer details: Trk \(details.track_position ?? 0), Disc \(details.disk_number ?? 0), Year \(newSong.year)")
        }
        
        
        if let artUrl = URL(string: match.album.cover_xl),
           let (artData, _) = try? await URLSession.shared.data(from: artUrl) {
            newSong.artworkData = artData
            print("[SongMetadata] Updated artwork with Deezer High-Res version: \(artData.count) bytes")
        }
        
        return newSong
    }
    
    static func enrichWithDeezerMetadata(_ song: SongMetadata) async -> SongMetadata {
        print("[SongMetadata] Searching Deezer for: \(song.artist) - \(song.title)")
        let query = "\(song.artist) \(song.title)"
        let results = await searchDeezer(query: query)
        
        if let firstMatch = results.first {
             print("[SongMetadata] ✓ Deezer match: \(firstMatch.title) by \(firstMatch.artist.name)")
             return await applyDeezerMatch(firstMatch, to: song)
        }
        
        return song
    }
}
