import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var supportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SUPPORT")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .tracking(0.5)

            VStack(spacing: 0) {
                Button {
                    openURL(URL(string: "https://buymeacoffee.com/EduAlexxis")!)
                } label: {
                    HStack {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Buy Me a Coffee")
                                .font(.body)
                                .foregroundColor(.primary)
                            Text("Support ByeTunes development")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundColor(Color(.systemGray3))
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }

                Divider().padding(.leading, 44)

                HStack(alignment: .top) {
                    Image(systemName: "heart.fill")
                        .font(.body)
                        .foregroundColor(.pink)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Supporters")
                            .font(.body)
                            .foregroundColor(.primary)

                        if !supportersLoaded {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(height: 20)
                        } else if supporters.isEmpty {
                            Text("Be the first to support!")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            FlowLayout(spacing: 6) {
                                ForEach(supporters, id: \.self) { name in
                                    Text(name)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color(.systemGray6))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
            .task {
                await fetchSupporters()
            }
        }
    }

    var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ABOUT")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .tracking(0.5)

            VStack(spacing: 0) {
                Button {
                    if let settingsUpdate {
                        openURL(settingsUpdate.releaseURL)
                    } else {
                        checkForSettingsUpdate()
                    }
                } label: {
                    HStack {
                        Image(systemName: "info.circle")
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Version")
                                .font(.body)
                                .foregroundColor(.primary)

                            Text(settingsUpdate == nil ? "Tap to check for updates" : "Tap to download the latest release")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if isCheckingForUpdate {
                            ProgressView()
                        } else {
                            Text(settingsUpdate.map { "Update \($0.version)" } ?? AppUpdateChecker.currentVersion)
                                .font(.subheadline)
                                .foregroundColor(settingsUpdate == nil ? .secondary : .accentColor)
                        }
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .disabled(isCheckingForUpdate)

                Divider().padding(.leading, 56)

                HStack {
                    Image(systemName: "music.note")
                        .font(.body)
                        .foregroundColor(.primary)
                        .frame(width: 28)

                    Text("Music Formats")
                        .font(.body)

                    Spacer()

                    Text("MP3, FLAC, M4A, WAV, Opus")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)

                Divider().padding(.leading, 56)

                HStack {
                    Image(systemName: "bell.badge")
                        .font(.body)
                        .foregroundColor(.primary)
                        .frame(width: 28)

                    Text("Ringtone Formats")
                        .font(.body)

                    Spacer()

                    Text("M4R, MP3 (Ringtones injection disabled for now")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
        }
    }

    var creditsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CREDITS")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .tracking(0.5)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                        .frame(width: 28)

                    Link("EduAlexxis", destination: URL(string: "https://github.com/EduAlexxis")!)
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)

                    Spacer()
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)

                Divider().padding(.leading, 56)

                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.indigo)
                        .frame(width: 28)

                    Link("stossy11", destination: URL(string: "https://github.com/stossy11")!)
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)

                    Spacer()
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)

                Divider().padding(.leading, 56)

                HStack(spacing: 12) {
                    Image(systemName: "paintbrush.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.orange)
                        .frame(width: 28)

                    Text("u/Zephyrax_g14")
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)

                    Spacer()
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)

                Divider().padding(.leading, 56)

                HStack(spacing: 12) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.gray)
                        .frame(width: 28)

                    Link("jkcoxson", destination: URL(string: "https://github.com/jkcoxson/idevice")!)
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)

                    Spacer()
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
        }
    }

    var dangerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DANGER ZONE")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .tracking(0.5)

            Button {
                showingDeleteAlert = true
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                        .font(.body)
                        .foregroundColor(.red)
                        .frame(width: 28)

                    Text("Delete Music Library")
                        .font(.body)
                        .foregroundColor(.red)

                    Spacer()
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemGray5), lineWidth: 1)
                )
            }
        }
    }
}
