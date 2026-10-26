# CapuTune

The CapuTune Flutter app — a cross-platform music player (Android, iOS, web,
and desktop) with a shared codebase in `lib/`.

## Attributions

- Search results are provided by YouTube Music; the Dart-native search
  client in `lib/services/ytm/` is adapted from
  [ytmusicapi](https://github.com/sigma67/ytmusicapi) (MIT License,
  Copyright (c) sigma67).

## Features

- Search, stream, and play music with full player controls
- Create and manage playlists
- Download songs for offline listening
- Recently played history and play counts
- Library export/import (JSON and M3U8)
- Dark/Light theme and audio quality settings
- In-app updates on Android

## Requirements

- Flutter `stable` (Dart SDK `>=3.4.0 <4.0.0`)
- Android builds need the Android SDK and a JDK 17 toolchain

## Getting started

```bash
flutter pub get
flutter run
```

## Checks

```bash
flutter analyze          # must stay clean
flutter test             # unit tests
```

## Build

```bash
flutter build apk --release      # Android
flutter build web                # Web
```

Release APKs are built and published by
`.github/workflows/release-android.yml` on every push to `main`, which bumps the
version, tags `vX.Y.Z`, and attaches `caputune-vX.Y.Z-android.apk` plus its
`.sha256` checksum to the GitHub Release.

## In-app updates (Android)

The app checks GitHub Releases for a newer version and, when one exists:

- downloads the release APK and verifies it against the published SHA-256,
- prefers a build-type-specific asset for the device's supported ABIs,
- validates the APK's package name, signature, and version before installing,
- hands the verified APK to the system installer.

The OS still shows its own confirmation and signature check — there is no silent
install. Install permission is requested only at install time, and the app routes
you to the "install unknown apps" setting when it is not yet granted.

## App identity

Android package/id and iOS/macOS bundle ids are `com.example.caputune`.

> **Note:** the rebrand changed the Android `applicationId` from
> `com.example.nekomusic` to `com.example.caputune`. Android treats this as a new
> app — installs built from older `com.example.nekomusic` APKs will not upgrade in
> place and their stored data does not carry over automatically. Install the new
> build fresh and move data with **Export library** → **Import**.
