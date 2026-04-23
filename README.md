# ByeTunes 🎵

**Say goodbye to iTunes sync.**

ByeTunes is a native iOS app that imports audio files, enriches their metadata, and injects them directly into the on-device Music library database. It also includes playlist injection, in-app download queueing, backup and restore tools, debug exports, and iOS 26.4+ artwork repair utilities.

## What ByeTunes does

ByeTunes is built for people who want local control over their music library on iPhone or iPad without depending on traditional desktop iTunes/Finder syncing every time they add tracks.

After pairing your device and connecting through a local tunnel/VPN, ByeTunes can:

- Import local audio files from the Files app
- Read embedded metadata and artwork
- Enrich metadata from multiple providers
- Fetch lyrics automatically
- Inject songs directly into the Music library database
- Inject songs as a playlist
- Queue and download tracks/albums from the in-app Download tab
- Export the media database for debugging
- Create and restore local snapshot backups
- Repair missing artwork/colors on iOS 26.4+

---

## Features

### Music import and injection
- Direct music injection into the device music library
- Supported audio import formats:
  - MP3
  - M4A
  - FLAC
  - WAV
  - AIFF
- Playlist injection support
- Duplicate detection during import
- Manual metadata editing before injection
- Large-import mode for big queues
- Auto-inject support when sharing files into the app from other apps

### Metadata
ByeTunes can use one metadata source, or all of them together:

- Local file metadata
- All Providers
- iTunes API
- Deezer API
- Apple Music
- YouTube

Optional metadata features:

- Autofetch metadata on import
- Rich Apple metadata
  - store IDs
  - XID
  - copyright
- Store region selection for iTunes-based lookup
- Lyrics fetching from:
  - LRCLIB
  - Musixmatch fallback
  - NetEase fallback
- Apple Music subscription lyrics option

### Download tab
- Built-in search and download flow
- Song and album result pages
- Per-track queueing
- Album track selection
- Queue progress UI
- Retry support for failed downloads
- Selectable download backend:
  - Auto
  - Yoinkify
  - HiFi One
  - HiFi Two
- Optional persistent storage for downloaded songs
- Optional custom download folder bookmark

### Backup, restore, and debug
- Snapshot/database backup
- Restore latest backup
- Optional full backup mode for database + media files
- Debug console/log viewer
- Export database bundle
- Library deletion tools

### iOS 26.4+ support
- RP Pairing File flow for newer iOS versions
- iOS 26+ UI path
- Artwork/color repair tool for songs added before iOS 26.4

---

## Current limitations

- **Ringtone injection is currently disabled in-app due to instability**
- The ringtone tab is only surfaced on older tab layouts and should be treated as experimental / not currently supported
- The Music app should be closed before injection for the most reliable results
- Large imports may take time because artwork and metadata are processed in batches

---

## Requirements

### Device
- iPhone or iPad running **iOS 16.0 or later**

### Development
- A **Mac**
- **Xcode 15+** recommended
- Rust toolchain for building the `idevice` static library

### External dependency
ByeTunes relies on `idevice` (a `libimobiledevice` alternative) to communicate with the device filesystem and services.

These files are **not** included in the repository and must be added manually to `MusicManager/`:

1. `libidevice_ffi.a`
2. `idevice.h`

Source:
- https://github.com/jkcoxson/idevice

If these files are missing, the project will not compile.

---

## Building the project

### 1. Install Rust
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

### 2. Add the iOS target
```bash
rustup target add aarch64-apple-ios
```

### 3. Install Xcode command line tools
```bash
xcode-select --install
```

### 4. Clone `idevice`
```bash
git clone https://github.com/jkcoxson/idevice
```

### 5. Set a deployment target
```bash
export IPHONEOS_DEPLOYMENT_TARGET=16.0
```

Adjust this if you need a newer deployment target.

### 6. Build the static library
```bash
cargo build --release --package idevice-ffi --target aarch64-apple-ios
```

### 7. Copy required files into the Xcode project
From the `idevice` build output, move:

- `idevice.h`
- `libidevice_ffi.a`

into the `MusicManager/` folder in this project.

### 8. Add the bridging header
Create `Bridging-Header.h` in the Xcode project and include:

```c
#import "idevice.h"
```

### 9. Link the static library
In **Project Settings → Build Phases → Link Binary With Libraries**, make sure:

- `libidevice_ffi.a`

is listed.

---

## Pairing and connection model

ByeTunes uses different pairing flows depending on iOS version.

### iOS 16 through iOS 26.3
ByeTunes uses the classic **pairing file** flow.

### iOS 26.4 and newer
ByeTunes expects an **RP Pairing File** and uses the newer RP pairing tunnel path.

That means the file you import into ByeTunes depends on the OS version you are running.

---

## How to use

### 1. Start a local tunnel / VPN
Open your local tunnel/VPN app before trying to connect.

Example:
- LocalDevVPN  
  App Store / AltStore PAL:  
  https://apps.apple.com/us/app/localdevvpn/id6755608044

### 2. Generate the correct pairing file
For classic pairing:
- generate a standard pairing file

For iOS 26.4+:
- generate the RP pairing file required by the newer tunnel flow

Related project:
- https://github.com/jkcoxson/idevice_pair

### 3. Import the pairing file into ByeTunes
On first launch, or when prompted, import the correct pairing file into ByeTunes.

### 4. Add songs
- Open the **Music** tab
- Tap **Add Songs**
- Select one or more audio files or folders from Files
- Review imported tracks in the queue
- Edit metadata if needed
- Resolve duplicates if prompted

### 5. Choose metadata behavior
In **Settings → Metadata**, choose one of:

- Local Files
- All Providers
- iTunes API
- Deezer API
- Apple Music
- YouTube

Optional:
- turn on Autofetch
- enable Rich Apple Metadata
- enable lyric fetching
- enable Apple Music subscription lyrics

### 6. Inject songs
- Close the Music app
- Tap **Inject to Device**

Or:

- Tap **Inject as Playlist**
- Select an existing playlist or create a new one

### 7. Use the Download tab
You can also use the built-in **Download** tab to:

- search tracks
- search albums
- queue downloads
- download selected album tracks
- keep downloaded files locally if enabled

### 8. Back up your library
In **Settings → Backup & Restore**, you can:

- create a snapshot backup
- restore the latest backup
- enable full backup mode if you also want media files stored locally

### 9. Debug / export
In **Settings → Debug**, you can:

- open the console log viewer
- export the music database files

### 10. Repair artwork on iOS 26.4+
If your artwork/colors are broken for songs added before iOS 26.4:

- open **Settings**
- use **Fix Artwork**

---

## Open With / Share Sheet support

ByeTunes can accept audio files shared into it from other apps.

Supported shared audio types:
- MP3
- M4A
- WAV
- FLAC
- AIFF

The app can automatically queue or inject content depending on connection state and app flow.

---

## Notes

- ByeTunes checks for updates from the upstream release feed used by the app
- The app supports both legacy and newer tab layouts depending on iOS version
- Downloaded songs can optionally be preserved instead of deleted after injection
- Imported filenames are sanitized during staging to reduce bad title/artist parsing during large imports
- Embedded artwork extraction is batched for large libraries to reduce memory pressure

---

## Troubleshooting

### App stuck on white or black screen
Restart the device to force the Music library to reload.

### Songs do not show up
Restart the app and try the injection again. Also make sure the Music app was closed before injecting.

### Artwork disappeared
Restart the Music app to refresh the cache. On iOS 26.4+, use **Fix Artwork** if needed.

### Import names look wrong
Try a metadata provider in Settings, or use **All Providers** and re-import the tracks.

### Pairing file is rejected
Make sure you imported the correct file type for your iOS version:
- classic pairing file for older versions
- RP Pairing File for iOS 26.4+

---

## Support

Found a bug?

- Open an issue in this repository:  
https://github.com/NightVibes33/ByeTunes/issues
- Join the Discord community:  
  https://discord.gg/jxWhegfz
- Include debug logs or exported database files when reporting injection/database issues

---

## Credits

- EduAlexxis — original project
- NightVibes33 — fixes, maintenance, metadata and import improvements, YouTube metadata support, “All Metadata” options, GitHub Actions build support, and workflow updates
- stossy11
- u/Zephyrax_g14
- jkcoxson — `idevice`

---

## Disclaimer

ByeTunes directly edits the device media database. Use it carefully, and keep backups before making major changes.
