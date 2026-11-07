# reLiveTV

A free, open-source live TV player for Android, Linux and Windows. It browses the
public channel list maintained by [iptv-org](https://github.com/iptv-org) and
plays the streams on your device — with search, filters, a mini player and
background play.

## Download

Get the latest build from **[Releases](https://github.com/Ken-n7/reLiveTV/releases/latest)**.

- **Android**: most phones need `relivetv-*-android-arm64-v8a.apk`. Older
  32-bit phones need `armeabi-v7a`, and emulators need `x86_64`. Open the
  APK and allow installing from unknown sources when Android asks.
- **Linux**: download `relivetv-*-linux-x64.tar.gz`. It needs libmpv
  (`libmpv2` on Debian/Ubuntu). The archive has no top-level folder, so
  extract it into its own directory:

  ```sh
  mkdir relivetv && tar xzf relivetv-*-linux-x64.tar.gz -C relivetv
  ./relivetv/tv_channels
  ```

- **Windows** (10 or 11, 64-bit): download `relivetv-*-windows-x64.zip`,
  extract it, and run `relivetv.exe`. Nothing else needs installing. The app
  isn't code-signed, so SmartScreen says "Windows protected your PC" the first
  time. Click **More info**, then **Run anyway**.

Each release includes a `SHA256SUMS` file for checking the downloads.

## Features

- **Browse and search in one place**: category rows, a search bar that matches
  names, networks, countries, broadcast areas and languages, and filters for
  country/region, language and category.
- **My List**: save channels you like; they stay on your device.
- **Resilient playback**: a stream is retried three times with pauses before the
  next source is tried, so a slow first response isn't treated as dead.
- **YouTube-style player**: mini player you can browse around with, quality
  picker, fullscreen, keyboard shortcuts on desktop (Space/K, M, F, I, arrows).
- **Background play** (off by default): picture-in-picture and a playback
  notification on Android.
- **Light on battery and data**: the channel list is saved on the device and
  refreshed at most once a day; nothing runs in the background unless you turn
  background play on.
- **Accessible**: keyboard/remote navigation with a visible focus ring, screen
  reader labels, works with large text sizes.

## Disclaimer

reLiveTV **does not host, store or provide any streams**. It only displays links
that iptv-org lists publicly and plays them on your device, the way a browser
opens a link. Availability and legality of each stream depend on its provider
and your country. Channels removed from iptv-org after a copyright complaint
(their blocklist) and adult channels are never shown.

## Privacy

No accounts, no analytics, no tracking. Your list and settings are stored only
on your device. The app talks to iptv-org's public API (channel list) and to
the stream servers of the channels you open.

## Build from source

Requires [Flutter](https://flutter.dev) (stable). On Linux it also needs
`clang`, `libgtk-3-dev` and `libmpv-dev`. On Windows it needs Visual Studio
with the "Desktop development with C++" workload.

```sh
flutter pub get
flutter run -d linux                 # desktop
flutter run -d windows               # desktop (Windows)
flutter build apk --release          # Android
```

Tests:

```sh
flutter test                         # unit tests
flutter test integration_test -d linux
```

## Credits

- Channel data: [iptv-org/iptv](https://github.com/iptv-org/iptv) and
  [iptv-org/api](https://github.com/iptv-org/api), released into the public domain.
- Playback: [media_kit](https://github.com/media-kit/media-kit) (libmpv).

## License

[MIT](LICENSE)
