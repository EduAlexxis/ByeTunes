import SwiftUI

// MARK: - Legacy Tab Bar (Custom Floating Bar)
struct LegacyTabBarView: View {
    @ObservedObject var manager: DeviceManager
    @Binding var songs: [SongMetadata]
    @Binding var ringtones: [RingtoneMetadata]
    @Binding var isInjecting: Bool
    @Binding var status: String
    @Binding var selectedTab: Int
    @Binding var showingLogViewer: Bool
    private var downloadTabIndex: Int { showRingtonesTab ? 2 : 1 }
    private var settingsTabIndex: Int { showRingtonesTab ? 3 : 2 }
    private var showRingtonesTab: Bool {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return (16...18).contains(major)
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            Group {
                if selectedTab == 0 {
                    MusicView(
                        manager: manager,
                        songs: $songs,
                        isInjecting: $isInjecting,
                        status: $status
                    )
                } else if showRingtonesTab && selectedTab == 1 {
                    RingtonesView(manager: manager, ringtones: $ringtones)
                } else if selectedTab == downloadTabIndex {
                    DownloadView(songs: $songs, status: $status)
                } else {
                    SettingsView(
                        manager: manager,
                        status: $status
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                 Color.clear.frame(height: 80)
            }
            .overlay(alignment: .bottom) {
                FloatingTabBar(selectedTab: $selectedTab, showRingtonesTab: showRingtonesTab)
                    .padding(.bottom, 0)
            }
        }
        .sheet(isPresented: $showingLogViewer) {
            LogViewer()
        }
        .ignoresSafeArea(.keyboard)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.8)),
            removal: .opacity.combined(with: .scale(scale: 1.2))
        ))
    }
}

// MARK: - Modern Tab View (Standard TabBar for iOS 26+)
struct ModernTabView: View {
    @ObservedObject var manager: DeviceManager
    @Binding var songs: [SongMetadata]
    @Binding var ringtones: [RingtoneMetadata]
    @Binding var isInjecting: Bool
    @Binding var status: String
    @Binding var selectedTab: Int
    @Binding var showingLogViewer: Bool
    private var downloadTabIndex: Int { showRingtonesTab ? 2 : 1 }
    private var settingsTabIndex: Int { showRingtonesTab ? 3 : 2 }
    private var showRingtonesTab: Bool {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return (16...18).contains(major)
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            MusicView(
                manager: manager,
                songs: $songs,
                isInjecting: $isInjecting,
                status: $status
            )
            .tabItem {
                Label("Music", systemImage: "music.note")
            }
            .tag(0)
            
            if showRingtonesTab {
                RingtonesView(manager: manager, ringtones: $ringtones)
                    .tabItem {
                        Label("Ringtones", systemImage: "bell.badge.fill")
                    }
                    .tag(1)
            }

            DownloadView(songs: $songs, status: $status)
                .tabItem {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .tag(downloadTabIndex)
            SettingsView(manager: manager, status: $status)
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(settingsTabIndex)
        }
        .onAppear {
            if !showRingtonesTab && selectedTab > settingsTabIndex {
                selectedTab = settingsTabIndex
            }
        }
        .sheet(isPresented: $showingLogViewer) {
            LogViewer()
        }
    }
}
