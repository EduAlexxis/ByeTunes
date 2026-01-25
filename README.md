# ByeTunes 🎵

**Say goodbye to iTunes sync!**

ByeTunes is a native iOS app that lets you inject music (MP3, M4A, FLAC) and ringtones directly into your device's media library—without needing a computer connection for every sync. It communicates directly with the iOS media database, giving you the power to manage your music on your terms.

## ✨ Features

-   **Direct Music Injection**: Add songs to your Apple Music library without a PC.
-   **Ringtone Manager**: Inject custom ringtones (`.m4r` and `.mp3` auto-conversion).
-   **Playlist Support**: Create and manage playlists on the fly.
-   **No Computer Needed** (after setup): Once paired, you're free!
-   **Metadata Editing**: Edit artist, album, and artwork details before injecting.

## 🛠 Compilation Instructions

To build ByeTunes yourself, you'll need a Mac with Xcode.

### Prerequisites

1.  **Xcode**: Version 14+ recommended.
2.  **iOS Device**: Running iOS 15.0 or later.

### ⚠️ The "Missing Reference"

ByeTunes relies on a proprietary FFI wrapper for `libimobiledevice` to talk to the iOS internal file system. **These files are NOT included in this repository** for licensing/size reasons.

To compile the app, you need to obtain these two files and place them in the `MusicManager/` directory:

1.  `libidevice_ffi.a` (Static Library)
2.  `idevice.h` (Header File)

*If you don't have these files, the project will not compile.*

### Build Steps

1.  Clone the repo:
    ```bash
    git clone https://github.com/EduAlexxis/ByeTunes.git
    cd ByeTunes
    ```
2.  **Add the missing libraries**:
    -   Copy `libidevice_ffi.a` and `idevice.h` into the `MusicManager/` folder.
3.  Open `MusicManager.xcodeproj` in Xcode.
4.  Switch the Signing Team to your own Apple ID.
5.  Build & Run on your device!

## 📱 How to Use

1.  **Pairing**:
    -   On first launch, you'll see an "Import Pairing File" screen.
    -   You need to get a `pairing file` (often created when you trust a computer).
    -   Export this file from your computer and Airdrop/Save it to your iPhone.
    -   Import it into ByeTunes.
2.  **Add Music**:
    -   Tap "Add Songs" and select files from your Files app.
    -   Hit "Inject to Device" and watch the magic happen.
3.  **Ringtones**:
    -   Go to the Ringtones tab, add your file, and inject!

## 📝 Notes

-   **Signed Apps**: If you install this via a signing service (Signulous, AltStore, etc.), the app includes a fix (`asCopy: true`) to ensure file importing works correctly without crashing.
-   **Backup**: Always good to have a backup of your music library before messing with database injection!

---
*Created with ❤️ by EduAlexxis*
