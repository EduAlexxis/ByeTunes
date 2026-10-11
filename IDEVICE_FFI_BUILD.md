# idevice FFI Build Notes

This project currently targets iOS `16.0`, so `libidevice_ffi.a` must be built with the same minimum deployment version.

## Source

- Upstream repo: `https://github.com/jkcoxson/idevice`
- Build crate: `/tmp/idevice/ffi`

## Required build settings

- Rust target: `aarch64-apple-ios`
- iOS minimum: `16.0` (must match Xcode target deployment)

## Build command

```bash
cd /tmp/idevice/ffi
cargo clean --target aarch64-apple-ios
RUSTFLAGS="-C link-arg=-miphoneos-version-min=16.0" \
BINDGEN_EXTRA_CLANG_ARGS="--sysroot=$(xcrun --sdk iphoneos --show-sdk-path)" \
IPHONEOS_DEPLOYMENT_TARGET=16.0 \
cargo build --release --target aarch64-apple-ios --features obfuscate
```

## Copy artifacts into app

```bash
cp /tmp/idevice/ffi/idevice.h /Users/edualexxis/Documents/MusicManager/MusicManager/idevice.h
cp /tmp/idevice/target/aarch64-apple-ios/release/libidevice_ffi.a /Users/edualexxis/Documents/MusicManager/MusicManager/libidevice_ffi.a
```

## Verify

```bash
xcodebuild -project /Users/edualexxis/Documents/MusicManager/MusicManager.xcodeproj \
  -scheme MusicManager \
  -configuration Debug \
  -destination 'generic/platform=iOS' build
```

