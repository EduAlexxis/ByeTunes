import SwiftUI
import UniformTypeIdentifiers

extension MusicView {
    var playlistSelectionSheet: some View {
        VStack(spacing: 0) {
            
            HStack {
                Text("Select Playlist")
                    .font(.system(size: 24, weight: .bold))
                Spacer()
                Button {
                    showingPlaylistSheet = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary.opacity(0.6))
                }
            }
            .padding([.top, .horizontal], 20)
            .padding(.bottom, 10)
            .background(Color(.systemBackground))
            
            ScrollView {
                VStack(spacing: 20) {
                    
                    Button {
                        showingPlaylistSheet = false
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showPlaylistAlert = true
                        }
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.1))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.accentColor)
                            }
                            
                            Text("Create New Playlist")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                        .padding(16)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                    }
                    
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("EXISTING PLAYLISTS")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                        
                        if existingPlaylists.isEmpty {
                            Text("No playlists found")
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                        } else {
                            ForEach(existingPlaylists) { playlist in
                                Button {
                                    showingPlaylistSheet = false
                                    injectAsPlaylist(name: playlist.name, pid: playlist.pid)
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.gray.opacity(0.1))
                                                .frame(width: 40, height: 40)
                                            Image(systemName: "music.note.list")
                                                .foregroundColor(.gray)
                                        }
                                        
                                        Text(playlist.name)
                                            .font(.system(size: 17))
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(Color(uiColor: .tertiaryLabel))
                                    }
                                    .padding(12)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .cornerRadius(16)
                                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}
