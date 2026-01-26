# ByeTunes 🎵

**Say goodbye to iTunes sync!**

ByeTunes is a native iOS app that lets you inject music (MP3, M4A, FLAC, WAV) and ringtones directly into your device's media library—without needing a computer connection for every sync. It communicates directly with the iOS media database, giving you the power to manage your music on your terms.

## Features

-   **Direct Music Injection**: Add songs to your Apple Music library without a PC.
-   **Ringtone Manager**: Inject custom ringtones (`.m4r` and `.mp3` auto-conversion).
-   **Playlist Support**: Create and manage playlists on the fly.
-   **No Computer Needed** (after setup): Once paired, you're free!
-   **Metadata Editing**: Auto-fetched from iTunes or Deezer.

## Compilation Instructions

To build ByeTunes yourself, you'll need a Mac with Xcode.

### Prerequisites

1.  **Xcode**: Version 15+ recommended.
2.  **iOS Device**: Running iOS 17.0 or later.

### External Libraries

ByeTunes relies on `idevice` (a `libimobiledevice` alternative) to talk to the iOS internal file system. **These files are NOT included in this repository** for licensing/size reasons.

To compile the app, you need to obtain these two files and place them in the `MusicManager/` directory:

1.  `libidevice_ffi.a` (Static Library)
2.  `idevice.h` (Header File)

You can find idevice and compile it from here: [https://github.com/jkcoxson/idevice](https://github.com/jkcoxson/idevice)

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

## How to Use

1.  **Pairing**:
    -   On first launch, you'll see an "Import Pairing File" screen.
    -   You need to get a `pairing file`.
    -   Export this file from your computer and Airdrop/Save it to your iPhone.
    -   Import it into ByeTunes.
2.  **Add Music**:
    -   Tap "Add Songs" and select files from your Files app.
    -   Hit "Inject to Device" and watch the magic happen.
3.  **Ringtones**:
    -   Go to the Ringtones tab, add your file, and inject!

## Notes

-   **Signed Apps**: If you install this via a signing service (Signulous, AltStore, etc.), the app includes a fix (`asCopy: true`) to ensure file importing works correctly without crashing.
-   **Backup**: Always good to have a backup of your music library before messing with database injection!

## Support & Bug Reporting

Found a bug? We'd love to fix it!

1.  **Report Issues**: Open a ticket on [GitHub Issues](https://github.com/EduAlexxis/ByeTunes/issues).
2.  **Join the Community**: Chat with us on [Discord](https://discord.gg/sKeckvz8g).
3.  **Attach Debug Logs**:
    *   If you are experiencing injection failures, please use the **Debug Release** provided in the GitHub Releases.
    *   This version includes a "Debug Logs" screen in Settings where you can copy the app logs.
    *   Please attach these logs to your issue report—they help us solve problems much faster!

---
*Created with ❤️ by EduAlexxis*
