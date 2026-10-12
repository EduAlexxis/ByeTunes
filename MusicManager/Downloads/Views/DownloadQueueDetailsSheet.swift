import SwiftUI
import Combine
import UIKit
import CryptoKit
import AVFoundation
import CommonCrypto
import SafariServices

struct DownloadQueueDetailsSheet: View {
    @ObservedObject var vm: DownloadViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var spotifySearchItem: DownloadQueueSnapshot.Item?
    @State private var deezerSearchItem: DownloadQueueSnapshot.Item?
    @State private var copiedItemID: String?
    @State private var copiedDeezerItemID: String?
    @State private var showCopiedBanner = false

    private func trackSearchQuery(for item: DownloadQueueSnapshot.Item) -> String {
        let strippedFeaturing = item.name.replacingOccurrences(
            of: #"\s*[\(\[](?:feat(?:\.|uring)?|ft\.?)\b[^\)\]]*[\)\]]"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let query = strippedFeaturing
            .trimmingCharacters(in: .whitespaces)
            .folding(options: .diacriticInsensitive, locale: nil)
            .lowercased()
        return query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
    }

    private func spotifySearchURL(for item: DownloadQueueSnapshot.Item) -> URL {
        let encoded = trackSearchQuery(for: item)
        return URL(string: "https://open.spotify.com/search/\(encoded)") ?? URL(string: "https://open.spotify.com")!
    }

    private func deezerSearchURL(for item: DownloadQueueSnapshot.Item) -> URL {
        let encoded = trackSearchQuery(for: item)
        return URL(string: "https://www.deezer.com/search/\(encoded)") ?? URL(string: "https://www.deezer.com")!
    }

    private func findOnSpotify(_ item: DownloadQueueSnapshot.Item) {
        UIPasteboard.general.string = "\(item.artist) \(item.name)"
        copiedItemID = item.id
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedItemID == item.id {
                copiedItemID = nil
            }
        }
        spotifySearchItem = item
    }

    private func findOnDeezer(_ item: DownloadQueueSnapshot.Item) {
        UIPasteboard.general.string = "\(item.artist) \(item.name)"
        copiedDeezerItemID = item.id
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedDeezerItemID == item.id {
                copiedDeezerItemID = nil
            }
        }
        deezerSearchItem = item
    }

    var body: some View {
        let snapshot = vm.queueSnapshot()

        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        DownloadQueueIndicator(
                            progress: snapshot.aggregateProgress,
                            label: snapshot.queueCounterText,
                            symbol: vm.queueIndicatorSymbol
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Download Queue")
                                .font(.headline)
                            
                            HStack(spacing: 8) {
                                if vm.isPaused {
                                    Button {
                                        vm.resumeQueue()
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "play.fill")
                                                .font(.caption)
                                            Text("Resume")
                                                .font(.caption.weight(.semibold))
                                        }
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule()
                                                .stroke(Color.green.opacity(0.4), lineWidth: 1)
                                                .background(Color.green.opacity(0.08).clipShape(Capsule()))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                } else if vm.shouldShowPauseButton {
                                    Button {
                                        vm.pauseQueue()
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "pause.fill")
                                                .font(.caption)
                                            Text("Pause")
                                                .font(.caption.weight(.semibold))
                                        }
                                        .foregroundColor(.accentColor)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule()
                                                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                                                .background(Color.accentColor.opacity(0.08).clipShape(Capsule()))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                if vm.shouldShowCancelButton {
                                    Button {
                                        vm.cancelQueue()
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption)
                                            Text("Cancel All")
                                                .font(.caption.weight(.semibold))
                                        }
                                        .foregroundColor(.red)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule()
                                                .stroke(Color.red.opacity(0.4), lineWidth: 1)
                                                .background(Color.red.opacity(0.08).clipShape(Capsule()))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    if !snapshot.activeItems.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(snapshot.activeItems.count > 1 ? "Overall Progress" : "Current Progress")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(snapshot.aggregateProgress * 100))%")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: snapshot.aggregateProgress)
                                .tint(.accentColor)
                            HStack {
                                Text("Speed")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(formattedSpeed(snapshot.aggregateSpeedBps))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 6)
                    }
                }

                if !snapshot.activeItems.isEmpty {
                    Section("In Progress") {
                        ForEach(snapshot.activeItems) { item in
                            queueRow(item)
                        }
                    }
                }

                if !snapshot.queuedItems.isEmpty {
                    Section("Queued") {
                        ForEach(snapshot.queuedItems) { item in
                            queueRow(item)
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { snapshot.queuedItems[$0].id }
                            DispatchQueue.main.async {
                                for id in ids {
                                    vm.removeQueued(trackID: id)
                                }
                            }
                        }
                    }
                }

                if !snapshot.doneItems.isEmpty {
                    Section {
                        ForEach(snapshot.doneItems) { item in
                            queueRow(item)
                        }
                    } header: {
                        HStack {
                            Text("Completed")
                            Spacer()
                            Button("Clear All") {
                                vm.clearCompleted()
                            }
                        }
                    }
                }

                if !snapshot.failedItems.isEmpty {
                    Section {
                        ForEach(snapshot.failedItems) { item in
                            queueRow(item)
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { snapshot.failedItems[$0].id }
                            DispatchQueue.main.async {
                                for id in ids {
                                    vm.removeFailed(trackID: id)
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("Failed")
                            Spacer()
                            Button("Clear All") {
                                vm.clearAllFailed()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Queue Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $spotifySearchItem) { item in
            ZStack(alignment: .bottom) {
                SafariSheetView(url: spotifySearchURL(for: item))
                    .ignoresSafeArea()

                if showCopiedBanner {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Copied. Paste it in the search bar.")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
                    .padding(.bottom, 30)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onAppear {
                withAnimation(.spring()) {
                    showCopiedBanner = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation(.easeOut) {
                        showCopiedBanner = false
                    }
                }
            }
        }
        .sheet(item: $deezerSearchItem) { item in
            ZStack(alignment: .bottom) {
                SafariSheetView(url: deezerSearchURL(for: item))
                    .ignoresSafeArea()

                if showCopiedBanner {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Copied. Paste it in the search bar.")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
                    .padding(.bottom, 30)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onAppear {
                withAnimation(.spring()) {
                    showCopiedBanner = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation(.easeOut) {
                        showCopiedBanner = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func queueRow(_ item: DownloadQueueSnapshot.Item) -> some View {
        HStack(spacing: 12) {
            Group {
                switch item.state {
                case .downloading:
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
                case .queued:
                    Image(systemName: "clock.fill").foregroundStyle(.orange)
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed:
                    Button {
                        vm.retry(trackID: item.id)
                    } label: {
                        Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                case .idle:
                    Image(systemName: "circle").foregroundStyle(.secondary)
                }
            }
            .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(item.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(item.album)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let failureReason = item.failureReason {
                    Text(failureReason)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .padding(.top, 1)

                    if failureReason == DownloadViewModel.appleMusicUnavailableMessage {
                        HStack(spacing: 14) {
                            Button {
                                findOnSpotify(item)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: copiedItemID == item.id ? "checkmark" : "magnifyingglass")
                                        .font(.caption2)
                                    Text(copiedItemID == item.id ? "Copied, opening Spotify search…" : "Find on Spotify")
                                        .font(.caption2.weight(.semibold))
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)

                            Button {
                                findOnDeezer(item)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: copiedDeezerItemID == item.id ? "checkmark" : "magnifyingglass")
                                        .font(.caption2)
                                    Text(copiedDeezerItemID == item.id ? "Copied, opening Deezer search…" : "Find on Deezer")
                                        .font(.caption2.weight(.semibold))
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                        }
                        .padding(.top, 2)
                    }
                }
                if item.isActive, item.state == .downloading {
                    ProgressView(value: item.progress)
                        .tint(.accentColor)
                        .padding(.top, 3)
                }
            }

            Spacer()

            if let queueIndex = item.queueIndex, !item.isActive {
                Text("#\(queueIndex + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func formattedSpeed(_ bps: Double) -> String {
        guard bps > 0 else { return "0 KB/s" }
        let kb = bps / 1024
        if kb < 1024 {
            return String(format: "%.0f KB/s", kb)
        }
        return String(format: "%.2f MB/s", kb / 1024)
    }
}
